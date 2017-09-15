//
//  TeamService.swift
//  Kryptonite
//
//  Created by Alex Grinman on 8/1/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation
import JSON
import SwiftHTTP

protocol TeamServiceAPI {
    func sendRequest<T:JsonReadable>(object:Object, _ onCompletion:@escaping (TeamService.ServerResponse<T>) -> Void) throws
}

class TeamService {

    // static instance
    static var instance:TeamService? = nil
    static let mutex = Mutex()
    
    class func shared() throws -> TeamService {
        defer { mutex.unlock() }
        mutex.lock()
        
        guard let teamIdentity = try IdentityManager.getTeamIdentity() else {
            throw Errors.noTeam
        }
        
        guard let i = instance else {
            instance = TeamService(teamIdentity: teamIdentity, mutex: mutex)
            return instance!
        }
        
        i.teamIdentity = teamIdentity
        
        return i
    }
    
    class func temporary(for teamIdentity:TeamIdentity, server:TeamServiceAPI = TeamServerHTTP()) -> TeamService {
        return TeamService(teamIdentity: teamIdentity, mutex: Mutex(), server: server)
    }

    
    enum Errors:Error {
        case noTeam
        
        case badResponse
        case badInviteSeed
        
        case payloadSignature
        case needNewestBlock
        case checkpointNotReached
        
        case missingLastBlockHash
        
        case needAdminKeypair
        case errorResponse(ServerError)
        
        case blockDidNotPost
    }
    
    struct ServerError:Error, CustomDebugStringConvertible {
        let message:String
        var debugDescription: String {
            return "Server responded with: \(message)."
        }
    }
    
    enum ServerResponse<T:JsonReadable>:JsonReadable, CustomDebugStringConvertible {
        case error(ServerError)
        case success(T)
        
        init(json: Object) throws {
            if let success:Object = try? json ~> "success" {
                self = try .success(T(json: success))
            } else if let message:String = try? json ~> "error" {
                self = .error(ServerError(message: message))
            } else {
                throw Errors.badResponse
            }
        }
        
        var debugDescription: String {
            switch self {
            case .success(let obj):
                return "SUCCESS:\n\t\t- \(obj)"
            case .error(let error):
                return "FAILURE:\n\t\t- \(error)"
            }
        }
    }
    
    enum TeamServiceResult<T> {
        case result(T)
        case error(Error)
    }
    
    struct EmptyResponse:JsonReadable {
        init() {}
        init(json: Object) throws {}
    }
    
    var teamIdentity:TeamIdentity
    var mutex:Mutex
    var server:TeamServiceAPI
    
    private init(teamIdentity:TeamIdentity, mutex:Mutex, server:TeamServiceAPI = TeamServerHTTP()) {
        self.teamIdentity = teamIdentity
        self.mutex = mutex
        self.server = server
    }
    
    /**
        Create a team and add the admin, thereby starting a new chain 
        with the admin as the first team member
     */
    func createTeam(createBlock:HashChain.Block, _ completionHandler:@escaping (TeamServiceResult<TeamService>) -> Void) throws {
        mutex.lock()
        
        // send the payload request
        let hashChainRequest = HashChain.Request(publicKey: createBlock.publicKey,
                                                 payload: createBlock.payload,
                                                 signature: createBlock.signature)
        
        try server.sendRequest(object: hashChainRequest.object) { (serverResponse:ServerResponse<EmptyResponse>) in
            defer { self.mutex.unlock() }
            
            switch serverResponse {
            case .error(let error):
                completionHandler(TeamServiceResult.error(error))

            case .success:
                completionHandler(TeamServiceResult.result(self))
            }
        }
    }
    
    /** 
        Add a team member directly (without invitation).
        Requires admin keypair
     */
    func add(member:Team.MemberIdentity, _ completionHandler:@escaping (TeamServiceResult<TeamService>) -> Void) throws {
        mutex.lock()
        
        // we need a last block hash
        guard let lastBlockhash = try teamIdentity.lastBlockHash() else {
            mutex.unlock()
            throw Errors.missingLastBlockHash
        }
        
        let operation = HashChain.Operation.addMember(member)
        let addMember = HashChain.AppendBlock(lastBlockHash: lastBlockhash, operation: operation)
        let payload = HashChain.Payload.append(addMember)
        let payloadData = try payload.jsonData()
        
        // sign the payload
        guard let signature = try KRSodium.shared().sign.signature(message: payloadData, secretKey: teamIdentity.keyPair.secretKey)
            else {
                mutex.unlock()
                throw Errors.payloadSignature
        }
        
        // send the payload request
        let payloadDataString = try payloadData.utf8String()
        let hashChainRequest = HashChain.Request(publicKey: teamIdentity.keyPair.publicKey,
                                                 payload: payloadDataString,
                                                 signature: signature)

        try server.sendRequest(object: hashChainRequest.object) { (serverResponse:ServerResponse<EmptyResponse>) in
            switch serverResponse {
                
            case .error(let error):
                completionHandler(TeamServiceResult.error(error))
                self.mutex.unlock()
                
            case .success:
                // set the block hash
                let addedBlock = HashChain.Block(publicKey: self.teamIdentity.keyPair.publicKey, payload: payloadDataString, signature: signature)
                
                do {
                    try self.teamIdentity.dataManager.add(member: member, block: addedBlock)
                } catch {
                    completionHandler(TeamServiceResult.error(error))
                    self.mutex.unlock()
                    return
                }
                
                completionHandler(TeamServiceResult.result(self))
                self.mutex.unlock()

            }
        }
    }
    
    /**
        Write an append block accepting a team invitation
        Special case: the team invitation keypair is used to sign the payload
     */
    func accept(invite:TeamInvite, _ completionHandler:@escaping (TeamServiceResult<TeamService>) -> Void ) throws {
        mutex.lock()
        
        let keyManager = try KeyManager.sharedInstance()
        let newMember = try Team.MemberIdentity(publicKey: teamIdentity.keyPair.publicKey,
                                                email: teamIdentity.email,
                                                sshPublicKey: keyManager.keyPair.publicKey.wireFormat(),
                                                pgpPublicKey: keyManager.loadPGPPublicKey(for: teamIdentity.email).packetData)
        
        // use the invite `seed` to create a nonce sodium keypair
        guard let nonceKeypair = try KRSodium.shared().sign.keyPair(seed: invite.seed) else {
            mutex.unlock()
            throw Errors.badInviteSeed
        }
        
        // get current block hash
        guard let blockHash = try teamIdentity.lastBlockHash() else {
            mutex.unlock()
            throw Errors.needNewestBlock
        }
        
        // create the payload
        let operation = HashChain.Operation.acceptInvite(newMember)
        let appendBlock = HashChain.AppendBlock(lastBlockHash: blockHash, operation: operation)
        let payload = HashChain.Payload.append(appendBlock)
        let payloadData = try payload.jsonData()

        // sign the payload json
        // Note: in this special case the nonce key pair is used to sign the payload
        
        guard let signature = try KRSodium.shared().sign.signature(message: payloadData, secretKey: nonceKeypair.secretKey)
        else {
            mutex.unlock()
            throw Errors.payloadSignature
        }
        
        let payloadDataString = try payloadData.utf8String()
        let hashChainRequest = HashChain.Request(publicKey: nonceKeypair.publicKey,
                                                 payload: payloadDataString,
                                                 signature: signature)
        
        try server.sendRequest(object: hashChainRequest.object) { (serverResponse:ServerResponse<EmptyResponse>) in
            switch serverResponse {
                
            case .error(let error):
                completionHandler(TeamServiceResult.error(error))
                self.mutex.unlock()
                
            case .success:
                let addedBlock = HashChain.Block(publicKey: nonceKeypair.publicKey, payload: payloadDataString, signature: signature)
                                
                do {
                    try self.teamIdentity.dataManager.add(member: newMember, block: addedBlock)
                } catch {
                    completionHandler(TeamServiceResult.error(error))
                    self.mutex.unlock()
                    return
                }
                
                completionHandler(TeamServiceResult.result(self))
                self.mutex.unlock()

            }
        }

    }
    
    /**
        Send a ReadBlock request to the teams service as a non-member, using the invite nonce keypair
     */
    func getTeam(using invite:TeamInvite, _ completionHandler:@escaping (TeamServiceResult<TeamService>) -> Void) throws {
        mutex.lock()

        do {
            try getTeamUnlocked(using: invite) { result in
                completionHandler(result)
                self.mutex.unlock()

            }
        } catch {
            mutex.unlock()
            throw error
        }
    }
    
    private func getTeamUnlocked(using invite:TeamInvite, _ completionHandler:@escaping (TeamServiceResult<TeamService>) -> Void) throws {
        
        // use the invite `seed` to create a nonce sodium keypair
        guard let nonceKeypair = try KRSodium.shared().sign.keyPair(seed: invite.seed) else {
            throw Errors.badInviteSeed
        }
        
        let readBlock = try HashChain.ReadBlock(teamPointer: invite.teamPointer,
                                                nonce: Data.random(size: 32),
                                                unixSeconds: UInt64(Date().timeIntervalSince1970))
        
        let payload = HashChain.Payload.read(readBlock)
        let payloadData = try payload.jsonData()
        
        guard let signature = try KRSodium.shared().sign.signature(message: payloadData, secretKey: nonceKeypair.secretKey)
            else {
                throw Errors.payloadSignature
        }
        
        let hashChainRequest = try HashChain.Request(publicKey: nonceKeypair.publicKey,
                                                     payload: payloadData.utf8String(),
                                                     signature: signature)
        
        
        try server.sendRequest(object: hashChainRequest.object) { (serverResponse:ServerResponse<HashChain.Response>) in
            switch serverResponse {
            case .error(let error):
                completionHandler(TeamServiceResult.error(error))
                
            case .success(let response):
                do {
                    guard response.hasBlocks else {
                        
                        guard try self.teamIdentity.isCheckPointReached() else {
                            completionHandler(TeamServiceResult.error(Errors.checkpointNotReached))
                            return
                        }
                        
                        completionHandler(TeamServiceResult.result(self))
                        return
                    }
                    
                    // verify and append incoming blocks
                    try self.teamIdentity.verifyAndProcessBlocks(response: response)
                    
                    guard response.hasMore else {
                        completionHandler(TeamServiceResult.result(self))
                        return
                    }
                    
                    try self.getTeamUnlocked(using: invite, completionHandler)
                } catch {
                    completionHandler(TeamServiceResult.error(error))
                }
            }
        }
        
    }
    
    /**
        Send a ReadBlock request to the teams service, and update the team by verifying and
        digesting any new blocks
     */
    func getVerifiedTeamUpdates(_ completionHandler:@escaping (TeamServiceResult<TeamService>) -> Void) throws {
        mutex.lock()
        
        do {
            try getVerifiedTeamUpdatesUnlocked() { result in
                completionHandler(result)
                self.mutex.unlock()
            }
        } catch {
            mutex.unlock()
            throw error
        }
    }
    
    private func getVerifiedTeamUpdatesUnlocked(_ completionHandler:@escaping (TeamServiceResult<TeamService>) -> Void) throws {
        
        let readBlock = try HashChain.ReadBlock(teamPointer: teamIdentity.teamPointer(),
                                              nonce: Data.random(size: 32),
                                              unixSeconds: UInt64(Date().timeIntervalSince1970))
        
        let payload = HashChain.Payload.read(readBlock)
        let payloadData = try payload.jsonData()
        
        guard let signature = try KRSodium.shared().sign.signature(message: payloadData, secretKey: teamIdentity.keyPair.secretKey)
        else {
            throw Errors.payloadSignature
        }
        
        
        let hashChainRequest = try HashChain.Request(publicKey: teamIdentity.keyPair.publicKey,
                                                     payload: payloadData.utf8String(),
                                                     signature: signature)
        
        try server.sendRequest(object: hashChainRequest.object) { (serverResponse:ServerResponse<HashChain.Response>) in
            switch serverResponse {
                
            case .error(let error):
                completionHandler(TeamServiceResult.error(error))
                
            case .success(let response):
                do {
                    guard response.hasBlocks else {
                        
                        
                        guard try self.teamIdentity.isCheckPointReached() else {
                            completionHandler(TeamServiceResult.error(Errors.checkpointNotReached))
                            return
                        }

                        completionHandler(TeamServiceResult.result(self))
                        return
                    }
                    
                    // verify and append incoming blocks
                    try self.teamIdentity.verifyAndProcessBlocks(response: response)

                    guard response.hasMore else {
                        completionHandler(TeamServiceResult.result(self))
                        return
                    }
                    
                    try self.getVerifiedTeamUpdatesUnlocked(completionHandler)
                } catch {
                    completionHandler(TeamServiceResult.error(error))
                }
            }
        }
        
    }
}

/// TeamIdentity + TeamPointer
extension TeamIdentity {
    func teamPointer() throws -> HashChain.TeamPointer {
        if let blockHash = try self.lastBlockHash() {
            return HashChain.TeamPointer.lastBlockHash(blockHash)
        }
        
        return HashChain.TeamPointer.publicKey(self.initialTeamPublicKey)
    }
}


/// TeamInvite + TeamPointer
extension TeamInvite {
    var teamPointer:HashChain.TeamPointer {
        return HashChain.TeamPointer.publicKey(self.initialTeamPublicKey)
    }
}


