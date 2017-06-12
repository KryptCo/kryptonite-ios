//
//  Silo.swift
//  Kryptonite
//
//  Created by Alex Grinman on 9/8/16.
//  Copyright © 2016 KryptCo, Inc. All rights reserved.
//

import Foundation
import JSON
import AwesomeCache


struct InvalidRequestTimeError:Error{}
struct RequestPendingError:Error{}

struct SiloCacheCreationError:Error{}

struct UserRejectedError:Error, CustomDebugStringConvertible {
    static let rejectedConstant = "rejected"
    
    var debugDescription:String {
        return UserRejectedError.rejectedConstant
    }
    
    static func isRejected(errorString:String) -> Bool {
        return errorString == rejectedConstant
    }
}


typealias CacheKey = String
extension CacheKey {
    init(_ session:Session, _ request:Request) {
        self = "\(session.id)_\(request.id)"
    }
}

class Silo {
    
    var mutex = Mutex()

    var requestCache: Cache<NSData>?
    //  store requests waiting for user approval
    var pendingRequests: Cache<NSString>?
    
    // singelton
    private static var sharedSiloMutex = Mutex()
    private static var sharedSilo:Silo?
    class var shared:Silo {
        defer { sharedSiloMutex.unlock() }
        sharedSiloMutex.lock()
        
        guard let ss = sharedSilo else {
            sharedSilo = Silo()
            return sharedSilo!
        }
        return ss
    }

    
    init() {
        requestCache = try? Cache<NSData>(name: "silo_cache", directory: sharedDirectory)
        pendingRequests = try? Cache<NSString>(name: "silo_pending_requests", directory: sharedDirectory)
    }
    
    lazy var sharedDirectory:URL? = {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_SECURITY_ID)?.appendingPathComponent("cache")
    }()


    
    //MARK: Handle Logic
    func handle(request:Request, session:Session, communicationMedium: CommunicationMedium, completionHandler: (()->Void)? = nil) throws {
        mutex.lock()
        defer { mutex.unlock() }

        guard let _ = SessionManager.shared.get(id: session.id) else {
            throw SessionRemovedError()
        }

        if let _ = request.unpair {
            Analytics.postEvent(category: "device", action: "unpair", label: "request")
            
            SessionManager.shared.remove(session: session)
            TransportControl.shared.remove(session: session, sendUnpairResponse: false)
            
            throw SessionRemovedError()
        }

        let now = Date().timeIntervalSince1970
        if abs(now - Double(request.unixSeconds)) > Properties.requestTimeTolerance {
            throw InvalidRequestTimeError()
        }
        
        requestCache?.removeExpiredObjects()
        if  let cachedResponseData = requestCache?[CacheKey(session, request)] as Data? {
            let json:Object = try JSON.parse(data: cachedResponseData)
            let response = try Response(json: json)
            try TransportControl.shared.send(response, for: session, completionHandler: completionHandler)
            return
        }
        
        
        // if it's signature request: check if we need a user approval
        // then exit and wait for approval
        if let signRequest = request.sign, Policy.needsUserApproval(for: session, and: signRequest) {
            try handleRequestRequiresApproval(request: request, session: session, communicationMedium: communicationMedium, completionHandler: completionHandler)
            return
        }
        
        // if it's a git-commit signature request: check if we need user approval
        // then exit and wait for approval
        if let _ = request.gitSign, Policy.needsUserApproval(for: session) {
            try handleRequestRequiresApproval(request: request, session: session, communicationMedium: communicationMedium, completionHandler: completionHandler)
            return
        }

        if request.isNoOp() {
            return
        }

        // otherwise, continue with creating and sending the response
        let response = try responseFor(request: request, session: session, signatureAllowed: true)
        
        // analytics / notify user on error for sign response
        if response.sign != nil {
            Analytics.postEvent(category: "signature", action: "automatic approval", label: communicationMedium.rawValue)
            
            if let error = response.sign?.error {
                Policy.notifyUser(errorMessage: error, session: session)
            } else {
                Policy.notifyUser(session: session, request: request)
            }
            
            if request.sign?.verifiedHostAuth == nil {
                Analytics.postEvent(category: "host", action: "unknown")
            }
        }
        
        // analytics / notify user on error for gitSign response
        if response.gitSign != nil {
            Analytics.postEvent(category: "git-commit-signature", action: "automatic approval", label: communicationMedium.rawValue)
            
            if let error = response.gitSign?.error {
                Policy.notifyUser(errorMessage: error, session: session)
            } else {
                Policy.notifyUser(session: session, request: request)
            }
        }

        
        try TransportControl.shared.send(response, for: session, completionHandler: completionHandler)
    }

    func handleRequestRequiresApproval(request: Request, session: Session, communicationMedium: CommunicationMedium, completionHandler: (() -> ())?) throws {
        pendingRequests?.removeExpiredObjects()
        if pendingRequests?.object(forKey: CacheKey(session, request)) != nil {
            throw RequestPendingError()
        }
        pendingRequests?.setObject("", forKey: CacheKey(session, request), expires: .seconds(Properties.requestTimeTolerance * 2))
        
        Policy.addPendingAuthorization(session: session, request: request)
        Policy.requestUserAuthorization(session: session, request: request)
        
        if request.sendACK {
            let arn = (try? KeychainStorage().get(key: KR_ENDPOINT_ARN_KEY)) ?? ""
            let ack = Response(requestID: request.id, endpoint: arn, approvedUntil: Policy.approvedUntilUnixSeconds(for: session), ack: AckResponse(), trackingID: (Analytics.enabled ? Analytics.userID : "disabled"))
            do {
                try TransportControl.shared.send(ack, for: session)
            } catch (let e) {
                log("ack send error \(e)")
            }
        }
        
        Analytics.postEvent(category: "signature", action: "requires approval", label:communicationMedium.rawValue)
        completionHandler?()
    }
    
    
    // MARK: Response
    
    func lockResponseFor(request:Request, session:Session, signatureAllowed:Bool) throws -> Response {
        mutex.lock()
        defer { mutex.unlock() }
        return try responseFor(request: request, session: session, signatureAllowed: signatureAllowed)
    }
    
    // precondition: mutex locked
    func responseFor(request:Request, session:Session, signatureAllowed:Bool) throws -> Response {
        let requestStart = Date().timeIntervalSince1970
        defer { log("response took \(Date().timeIntervalSince1970 - requestStart) seconds") }
        var sign:SignResponse?
        var me:MeResponse?
        var gitSign:GitSignResponse?
        
        if let signRequest = request.sign {
            let kp = try KeyManager.sharedInstance()

            if try kp.keyPair.publicKey.fingerprint() != signRequest.fingerprint.fromBase64() {
                throw KeyManagerError.keyDoesNotExist
            }

            var sig:String?
            var err:String?
            do {
                
                if signatureAllowed {
                    
                    // if host auth provided, check known hosts
                    // fails in invalid signature -or- hostname not provided
                    if let verifiedHostAuth = signRequest.verifiedHostAuth {
                        try KnownHostManager.shared.checkOrAdd(verifiedHostAuth: verifiedHostAuth)
                    }
                    
                    // only place where signature should occur
                    sig = try kp.keyPair.signAppendingSSHWirePubkeyToPayload(data: signRequest.data, digestType: signRequest.digestType.based(on: request.version))
                    
                    LogManager.shared.save(theLog: SSHSignatureLog(session: session.id, hostAuth: signRequest.verifiedHostAuth, signature: sig ?? "<err>", displayName: signRequest.display), deviceName: session.pairing.name)
                } else {
                    throw UserRejectedError()
                }

            }
            catch let error as UserRejectedError {
                LogManager.shared.save(theLog: SSHSignatureLog(session: session.id, hostAuth: signRequest.verifiedHostAuth, signature: "request failed", displayName: "rejected: \(signRequest.display)"), deviceName: session.pairing.name)
                err = "\(error)"
            }
            catch let error as HostMistmatchError {
                LogManager.shared.save(theLog: SSHSignatureLog(session: session.id, hostAuth: signRequest.verifiedHostAuth, signature: "request failed", displayName: "rejected: \(error)"), deviceName: session.pairing.name)
                err = "\(error)"
            }
            catch {
                err = "\(error)"
            }

            sign = SignResponse(sig: sig, err: err)
        }
        
        if let gitSignRequest = request.gitSign {            
            var sig:String?
            var err:String?
            do {                
                if signatureAllowed {
                    // only place where git signature should occur
                    
                    let keyManager = try KeyManager.sharedInstance()
                    let keyID = try keyManager.getPGPPublicKeyID()                    
                    let _ = keyManager.updatedUserIDs(for: gitSignRequest.userId)
                    
                    switch gitSignRequest.git {
                    case .commit(let commit):
                        
                        let asciiArmoredSig = try keyManager.keyPair.signGitCommit(with: commit, keyID: keyID)
                        let signature = asciiArmoredSig.packetData.toBase64()
                        sig = signature
                        
                        let commitHash = try commit.commitHash(asciiArmoredSignature: asciiArmoredSig.toString()).hex
                        LogManager.shared.save(theLog: CommitSignatureLog(session: session.id, signature: signature, commitHash: commitHash, commit: commit), deviceName: session.pairing.name)

                    case .tag(let tag):

                        let signature = try keyManager.keyPair.signGitTag(with: tag, keyID: keyID).packetData.toBase64()
                        sig = signature
                        
                        LogManager.shared.save(theLog: TagSignatureLog(session: session.id, signature: signature, tag: tag), deviceName: session.pairing.name)
                    }
                    
                } else {
                    
                    switch gitSignRequest.git {
                    case .commit(let commit):
                        LogManager.shared.save(theLog: CommitSignatureLog(session: session.id, signature: CommitSignatureLog.rejectedConstant, commitHash: "", commit: commit), deviceName: session.pairing.name)
                    case .tag(let tag):
                        LogManager.shared.save(theLog: TagSignatureLog(session: session.id, signature: TagSignatureLog.rejectedConstant, tag: tag), deviceName: session.pairing.name)
                    }

                    throw UserRejectedError()
                }
                
            }  catch {
                err = "\(error)"
            }
            
            gitSign = GitSignResponse(sig: sig, err: err)
        }
        
        if let meRequest = request.me {
            let keyManager = try KeyManager.sharedInstance()
            
            var pgpPublicKey:Data?
            if let pgpUserID = meRequest.pgpUserId {
                pgpPublicKey = try keyManager.loadPGPPublicKey(for: pgpUserID).packetData
            }
            
            me = MeResponse(me: MeResponse.Me(email: try keyManager.getMe(), publicKeyWire: try keyManager.keyPair.publicKey.wireFormat(), pgpPublicKey: pgpPublicKey))
        }
        
        let arn = (try? KeychainStorage().get(key: KR_ENDPOINT_ARN_KEY)) ?? ""
        
        let response = Response(requestID: request.id, endpoint: arn, approvedUntil: Policy.approvedUntilUnixSeconds(for: session), sign: sign, gitSign: gitSign, me: me, trackingID: (Analytics.enabled ? Analytics.userID : "disabled"))
        
        let responseData = try response.jsonData() as NSData
        
        requestCache?.setObject(responseData, forKey: CacheKey(session, request), expires: .seconds(Properties.requestTimeTolerance * 2))
        
        return response

    }
    
    func cachedResponse(for session:Session,with request:Request) -> Response? {
        if  let cachedResponseData = requestCache?[CacheKey(session, request)] as Data?,
            let json:Object = try? JSON.parse(data: cachedResponseData),
            let response = try? Response(json: json)
        {
            return response
        }

        return nil
    }

}
