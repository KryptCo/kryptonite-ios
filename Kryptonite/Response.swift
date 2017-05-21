//
//  Request.swift
//  Kryptonite
//
//  Created by Alex Grinman on 9/2/16.
//  Copyright © 2016 KryptCo, Inc. All rights reserved.
//

import Foundation
import JSON

final class Response:Jsonable {
    
    var requestID:String
    var snsEndpointARN:String
    var version:Version?
    var approvedUntil:Int?
    var sign:SignResponse?
    var gitSign:GitSignResponse?
    var me:MeResponse?
    var unpair:UnpairResponse?
    var ack:AckResponse?
    var trackingID:String?

    init(requestID:String, endpoint:String, approvedUntil:Int? = nil, sign:SignResponse? = nil, gitSign:GitSignResponse? = nil, me:MeResponse? = nil, unpair:UnpairResponse? = nil, ack:AckResponse? = nil, trackingID:String? = nil) {
        self.requestID = requestID
        self.snsEndpointARN = endpoint
        self.approvedUntil = approvedUntil
        self.sign = sign
        self.gitSign = gitSign
        self.me = me
        self.unpair = unpair
        self.ack = ack
        self.trackingID = trackingID
        self.version = Properties.currentVersion
    }
    
    init(json: Object) throws {
        self.requestID = try json ~> "request_id"
        self.snsEndpointARN = try json ~> "sns_endpoint_arn"
        self.version = try Version(string: json ~> "v")

        if let approvedUntil:Int = try? json ~> "approved_until" {
            self.approvedUntil = approvedUntil
        }

        if let json:Object = try? json ~> "sign_response" {
            self.sign = try SignResponse(json: json)
        }

        if let json:Object = try? json ~> "git_sign_response" {
            self.gitSign = try GitSignResponse(json: json)
        }
        
        if let json:Object = try? json ~> "me_response" {
            self.me = try MeResponse(json: json)
        }

        if let json:Object = try? json ~> "unpair_response" {
            self.unpair = UnpairResponse(json: json)
        }

        if let json:Object = try? json ~> "ack_response" {
            self.ack = AckResponse(json: json)
        }

        if let trackingID:String = try? json ~> "tracking_id" {
            self.trackingID = trackingID
        }
    }
    
    var object:Object {
        var json:[String:Any] = [:]
        json["request_id"] = requestID
        json["sns_endpoint_arn"] = snsEndpointARN
        
        if let approvedUntil = approvedUntil {
            json["approved_until"] = approvedUntil
        }

        if let s = sign {
            json["sign_response"] = s.object
        }

        if let gitSign = gitSign {
            json["git_sign_response"] = gitSign.object
        }
        
        if let m = me {
            json["me_response"] = m.object
        }

        if let u = unpair {
            json["unpair_response"] = u.object
        }

        if let a = ack {
            json["ack_response"] = a.object
        }

        if let trackingID = self.trackingID {
            json["tracking_id"] = trackingID
        }

        if let v = self.version {
            json["v"] = v.string
        }

        return json
    }
}

//MARK: Responses

// Sign

struct SignResponse:Jsonable {
    var signature:String?
    var error:String?
    
    init(sig:String?, err:String? = nil) {
        self.signature = sig
        self.error = err
    }
    
    init(json: Object) throws {
        
        if let sig:String = try? json ~> "signature" {
            self.signature = sig
        }
        
        if let err:String = try? json ~> "error" {
            self.error = err
        }
    }
    
    var object: Object {
        var map = [String:Any]()

        if let sig = signature {
            map["signature"] = sig
        }
        if let err = error {
            map["error"] = err
        }
        return map
    }
}

struct GitSignResponse:Jsonable {
    var signature:String?
    var error:String?
    
    init(sig:String?, err:String? = nil) {
        self.signature = sig
        self.error = err
    }
    
    init(json: Object) throws {
        
        if let sig:String = try? json ~> "signature" {
            self.signature = sig
        }
        
        if let err:String = try? json ~> "error" {
            self.error = err
        }
    }
    
    var object: Object {
        var map = [String:Any]()
        
        if let sig = signature {
            map["signature"] = sig
        }
        if let err = error {
            map["error"] = err
        }
        return map
    }
}



// Me
struct MeResponse:Jsonable {
    
    struct Me:Jsonable {
        var email:String
        var publicKeyWire:Data
        var pgpPublicKey:Data?
        
        init(email:String, publicKeyWire:Data, pgpPublicKey: Data? = nil) {
            self.email = email
            self.publicKeyWire = publicKeyWire
            self.pgpPublicKey = pgpPublicKey
        }
        
        init(json: Object) throws {
            self.email = try json ~> "email"
            self.publicKeyWire = try ((json ~> "public_key_wire") as String).fromBase64()
            self.pgpPublicKey = try ((json ~> "pgp_pk") as String).fromBase64()
        }
        
        var object: Object {
            var json = ["email": email, "public_key_wire": publicKeyWire.toBase64()]
            if let pgpPublicKey = pgpPublicKey {
                json["pgp_pk"] = pgpPublicKey.toBase64()
            }
            return json
        }
    }
    
    var me:Me
    
    init(me:Me) {
        self.me = me
    }
    init(json: Object) throws {
        self.me = try Me(json: json ~> "me")

    }
    var object: Object {
        return ["me": me.object]
    }
}

// Unpair
struct UnpairResponse:Jsonable {
    init(){}
    init(json: Object) {

    }
    var object: Object {
        return [:]
    }
}

// Ack
struct AckResponse:Jsonable {
    init(){}
    init(json: Object) {
        
    }
    var object: Object {
        return [:]
    }}
