//
//  KeychainStorage.swift
//  Kryptonite
//
//  Created by Alex Grinman on 9/1/16.
//  Copyright © 2016 KryptCo, Inc. All rights reserved.
//

import Foundation

private let KrKeychainServiceName = "kr_keychain_service"

enum KeychainStorageError:Error {
    case notFound
    case unknown(OSStatus?)
}

class KeychainStorage {
    
    var service:String
    
    init(service:String = KrKeychainServiceName) {
        self.service = service
    }
    
    func setData(key:String, data:Data) -> Bool {
        let params = [String(kSecClass): kSecClassGenericPassword,
                      String(kSecAttrService): service,
                      String(kSecAttrAccount): key,
                      String(kSecValueData): data,
                      String(kSecAttrAccessible): KeychainAccessiblity] as [String : Any]
        
        let deleteStatus = SecItemDelete(params as CFDictionary)
        guard deleteStatus == errSecItemNotFound || deleteStatus.isSuccess()
            else {
                log("could not delete item first", .error)
                return false
        }
        
        let status = SecItemAdd(params as CFDictionary, nil)
        guard status.isSuccess() else {
            return false
        }
        
        return true
    }

    
    func set(key:String, value:String) -> Bool {
        guard let data = value.data(using: String.Encoding.utf8) else {
            return false
        }
        
        return self.setData(key: key, data: data)
    }
    
    func getData(key:String) throws -> Data {
        let params = [String(kSecClass): kSecClassGenericPassword,
                      String(kSecAttrService): service,
                      String(kSecAttrAccount): key,
                      String(kSecReturnData): kCFBooleanTrue,
                      String(kSecMatchLimit): kSecMatchLimitOne,
                      String(kSecAttrAccessible): KeychainAccessiblity] as [String : Any]
        
        var object:AnyObject?
        let status = SecItemCopyMatching(params as CFDictionary, &object)
        
        if status == errSecItemNotFound {
            throw KeychainStorageError.notFound
        }
        
        guard let data = object as? Data, status.isSuccess() else {
            throw KeychainStorageError.unknown(status)
        }
        
        return data
    }
    
    func get(key:String) throws -> String {
        return try self.getData(key: key).utf8String()
    }

    
    func delete(key:String) -> Bool {
        let params = [String(kSecClass): kSecClassGenericPassword,
                      String(kSecAttrService): service,
                      String(kSecAttrAccount): key] as [String : Any]
        
        let status = SecItemDelete(params as CFDictionary)
        
        guard status.isSuccess() else {
            return false
        }
        
        return true
    }
    
}
