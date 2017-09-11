//
//  RASUtils.swift
//  mpush-client
//
//  Created by OHUN on 16/6/8.
//  Copyright © 2016年 OHUN. All rights reserved.
//

import Foundation

//
//  SwiftyRSA.swift
//  SwiftyRSA
//
//  Created by Loïs Di Qual on 7/2/15.
//  Copyright (c) 2015 Scoop Technologies, Inc. All rights reserved.
//

import Foundation
import Security


open class RSAError: NSError {
    init(message: String) {
        super.init(domain: "com.takescoop.SwiftyRSA", code: 500, userInfo: [
            NSLocalizedDescriptionKey: message
            ])
    }
    
    
    @available(*, unavailable)
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


@objc
public final class RSAUtils: NSObject {
    
    @objc public enum DigestType: Int {
        case sha1
        case sha224
        case sha256
        case sha384
        case sha512
    }

    fileprivate var keyTags: [Data] = []
    fileprivate static let defaultPadding: SecPadding = .PKCS1
    
    public class func encrypt(_ data: Data, publicKeyPEM: String, padding: SecPadding = defaultPadding) throws -> Data {
        let rsa = RSAUtils()
        let key = try rsa.publicKeyFromPEMString(publicKeyPEM)
        return try rsa.encryptData(data, publicKey: key, padding: padding)
    }

    public class func decrypt(_ data: Data, privateKeyPEM: String, padding: SecPadding = defaultPadding) throws -> Data {
        let rsa = RSAUtils()
        let key = try rsa.privateKeyFromPEMString(privateKeyPEM)
        return try rsa.decryptData(data, privateKey: key, padding: padding)
    }
    
    // MARK: - Public Advanced Methods
    
    public override init() {
        super.init()
    }
    
    public func publicKeyFromDERData(_ keyData: Data) throws -> SecKey {
        return try addKey(keyData, isPublic: true)
    }
    
    public func publicKeyFromPEMString(_ key: String) throws -> SecKey {
        let data = try dataFromPEMKey(key)
        return try addKey(data, isPublic: true)
    }
    
    public func privateKeyFromPEMString(_ key: String) throws -> SecKey {
        let data = try dataFromPEMKey(key)
        return try addKey(data, isPublic: false)
    }
    
    // Encrypts data with a RSA key
    public func encryptData(_ data: Data, publicKey: SecKey, padding: SecPadding) throws -> Data {
        let blockSize = SecKeyGetBlockSize(publicKey)
        let maxChunkSize = blockSize - 11
        
        var decryptedDataAsArray = [UInt8](repeating: 0, count: data.count / MemoryLayout<UInt8>.size)
        (data as NSData).getBytes(&decryptedDataAsArray, length: data.count)
        
        var encryptedData = [UInt8](repeating: 0, count: 0)
        var idx = 0
        while (idx < decryptedDataAsArray.count) {
            
            let idxEnd = min(idx + maxChunkSize, decryptedDataAsArray.count)
            let chunkData = [UInt8](decryptedDataAsArray[idx..<idxEnd])
            
            var encryptedDataBuffer = [UInt8](repeating: 0, count: blockSize)
            var encryptedDataLength = blockSize
            
            let status = SecKeyEncrypt(publicKey, padding, chunkData, chunkData.count, &encryptedDataBuffer, &encryptedDataLength)
            
            guard status == noErr else {
                throw RSAError(message: "Couldn't encrypt chunk at index \(idx)")
            }
            
            encryptedData += encryptedDataBuffer
            
            idx += maxChunkSize
        }
        
        return Data(bytes: UnsafePointer<UInt8>(encryptedData), count: encryptedData.count)
    }
    
    // Decrypt an encrypted data with a RSA key
    public func decryptData(_ encryptedData: Data, privateKey: SecKey, padding: SecPadding) throws -> Data {
        let blockSize = SecKeyGetBlockSize(privateKey)
        
        var encryptedDataAsArray = [UInt8](repeating: 0, count: encryptedData.count / MemoryLayout<UInt8>.size)
        (encryptedData as NSData).getBytes(&encryptedDataAsArray, length: encryptedData.count)
        
        var decryptedData = [UInt8](repeating: 0, count: 0)
        var idx = 0
        while (idx < encryptedDataAsArray.count) {
            
            let idxEnd = min(idx + blockSize, encryptedDataAsArray.count)
            let chunkData = [UInt8](encryptedDataAsArray[idx..<idxEnd])
            
            var decryptedDataBuffer = [UInt8](repeating: 0, count: blockSize)
            var decryptedDataLength = blockSize
            
            let status = SecKeyDecrypt(privateKey, padding, chunkData, idxEnd-idx, &decryptedDataBuffer, &decryptedDataLength)
            guard status == noErr else {
                throw RSAError(message: "Couldn't decrypt chunk at index \(idx)")
            }
            
            decryptedData += [UInt8](decryptedDataBuffer[0..<decryptedDataLength])
            
            idx += blockSize
        }
        
        return Data(bytes: UnsafePointer<UInt8>(decryptedData), count: decryptedData.count)
    }
    
    // MARK: - Private
    
    fileprivate func addKey(_ keyData: Data, isPublic: Bool) throws -> SecKey {
        
        var keyData = keyData
        
        // Strip key header if necessary
        if isPublic {
            try keyData = stripPublicKeyHeader(keyData)
        }
        
        let tag = UUID().uuidString
        let tagData = Data(bytes: UnsafePointer<UInt8>(tag), count: tag.lengthOfBytes(using: String.Encoding.utf8))
        removeKeyWithTagData(tagData)
        
        // Add persistent version of the key to system keychain
//        let persistKey = UnsafeMutablePointer<AnyObject?>(nil)
        var persistKey: UnsafeMutablePointer<AnyObject?>?
        let keyClass   = isPublic ? kSecAttrKeyClassPublic : kSecAttrKeyClassPrivate
        
        // Add persistent version of the key to system keychain
        let keyDict = NSMutableDictionary()
        keyDict.setObject(kSecClassKey,         forKey: kSecClass as! NSCopying)
        keyDict.setObject(tagData,              forKey: kSecAttrApplicationTag as! NSCopying)
        keyDict.setObject(kSecAttrKeyTypeRSA,   forKey: kSecAttrKeyType as! NSCopying)
        keyDict.setObject(keyData,              forKey: kSecValueData as! NSCopying)
        keyDict.setObject(keyClass,             forKey: kSecAttrKeyClass as! NSCopying)
        keyDict.setObject(NSNumber(value: true as Bool), forKey: kSecReturnPersistentRef as! NSCopying)
        keyDict.setObject(kSecAttrAccessibleWhenUnlocked, forKey: kSecAttrAccessible as! NSCopying)
        
        var secStatus = SecItemAdd(keyDict as CFDictionary, persistKey)
        if secStatus != noErr && secStatus != errSecDuplicateItem {
            throw RSAError(message: "Provided key couldn't be added to the keychain")
        }
        
        keyTags.append(tagData)
        
        // Now fetch the SecKeyRef version of the key
        var keyRef: AnyObject? = nil
        keyDict.removeObject(forKey: kSecValueData)
        keyDict.removeObject(forKey: kSecReturnPersistentRef)
        keyDict.setObject(NSNumber(value: true as Bool), forKey: kSecReturnRef as! NSCopying)
        keyDict.setObject(kSecAttrKeyTypeRSA,   forKey: kSecAttrKeyType as! NSCopying)
//        secStatus = SecItemCopyMatching(keyDict as CFDictionaryRef, &keyRef)
        secStatus = SecItemCopyMatching(keyDict as CFDictionary, &keyRef)
        
        guard let unwrappedKeyRef = keyRef else {
            throw RSAError(message: "Couldn't get key reference from the keychain")
        }
        
        return unwrappedKeyRef as! SecKey
    }
    
    fileprivate func dataFromPEMKey(_ key: String) throws -> Data {
        
        let lines = key.components(separatedBy: "\n").filter { line in
            return !line.hasPrefix("-----BEGIN") && !line.hasPrefix("-----END")
        }
        
        guard lines.count != 0 else {
            throw RSAError(message: "Couldn't get data from PEM key: no data available after stripping headers")
        }
        
        // Decode base64 key
        let base64EncodedKey = lines.joined(separator: "")
        let keyData = Data(base64Encoded: base64EncodedKey, options: .ignoreUnknownCharacters)
        
        guard let unwrappedKeyData = keyData, unwrappedKeyData.count != 0 else {
            throw RSAError(message: "Couldn't decode PEM key data (base64)")
        }
        
        return unwrappedKeyData
    }
    
    /**
     This method strips the x509 from a provided ASN.1 DER public key.
     If the key doesn't contain a header, the DER data is returned as is.
     
     Supported formats are:
     
     Headerless:
     SEQUENCE
     INTEGER (1024 or 2048 bit) -- modulo
     INTEGER -- public exponent
     
     With x509 header:
     SEQUENCE
     SEQUENCE
     OBJECT IDENTIFIER 1.2.840.113549.1.1.1
     NULL
     BIT STRING
     SEQUENCE
     INTEGER (1024 or 2048 bit) -- modulo
     INTEGER -- public exponent
     
     Example of headerless key:
     https://lapo.it/asn1js/#3082010A0282010100C1A0DFA367FBC2A5FD6ED5A071E02A4B0617E19C6B5AD11BB61192E78D212F10A7620084A3CED660894134D4E475BAD7786FA1D40878683FD1B7A1AD9C0542B7A666457A270159DAC40CE25B2EAE7CCD807D31AE725CA394F90FBB5C5BA500545B99C545A9FE08EFF00A5F23457633E1DB84ED5E908EF748A90F8DFCCAFF319CB0334705EA012AF15AA090D17A9330159C9AFC9275C610BB9B7C61317876DC7386C723885C100F774C19830F475AD1E9A9925F9CA9A69CE0181A214DF2EB75FD13E6A546B8C8ED699E33A8521242B7E42711066AEC22D25DD45D56F94D3170D6F2C25164D2DACED31C73963BA885ADCB706F40866B8266433ED5161DC50E4B3B0203010001
     
     Example of key with X509 header (notice the additional ASN.1 sequence):
     https://lapo.it/asn1js/#30819F300D06092A864886F70D010101050003818D0030818902818100D0674615A252ED3D75D2A3073A0A8A445F3188FD3BEB8BA8584F7299E391BDEC3427F287327414174997D147DD8CA62647427D73C9DA5504E0A3EED5274A1D50A1237D688486FADB8B82061675ABFA5E55B624095DB8790C6DBCAE83D6A8588C9A6635D7CF257ED1EDE18F04217D37908FD0CBB86B2C58D5F762E6207FF7B92D0203010001
     */
    fileprivate func stripPublicKeyHeader(_ keyData: Data) throws -> Data {
        let count = keyData.count / MemoryLayout<CUnsignedChar>.size
        
        guard count > 0 else {
            throw RSAError(message: "Provided public key is empty")
        }
        
        var byteArray = [UInt8](repeating: 0, count: count)
        (keyData as NSData).getBytes(&byteArray, length: keyData.count)
        
        var index = 0
        guard byteArray[index] == 0x30 else {
            throw RSAError(message: "Provided key doesn't have a valid ASN.1 structure (first byte should be 0x30 == SEQUENCE)")
        }
        
        index += 1
        if byteArray[index] > 0x80 {
            index += Int(byteArray[index]) - 0x80 + 1
        }
        else {
            index += 1
        }
        
        // If current byte marks an integer (0x02), it means the key doesn't have a X509 header and just
        // contains its modulo & public exponent. In this case, we can just return the provided DER data as is.
        if Int(byteArray[index]) == 0x02 {
            return keyData
        }
        
        // Now that we've excluded the possibility of headerless key, we're looking for a valid X509 header sequence.
        // It should look like this:
        // 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00
        guard Int(byteArray[index]) == 0x30 else {
            throw RSAError(message: "Provided key doesn't have a valid X509 header")
        }
        
        index += 15
        if byteArray[index] != 0x03 {
            throw RSAError(message: "Invalid byte at index \(index - 1) (\(byteArray[index - 1])) for public key header")
        }
        
        index += 1
        if byteArray[index] > 0x80 {
            index += Int(byteArray[index]) - 0x80 + 1
        }
        else {
            index += 1
        }
        
        guard byteArray[index] == 0 else {
            throw RSAError(message: "Invalid byte at index \(index - 1) (\(byteArray[index - 1])) for public key header")
        }
        
        index += 1
        
        let strippedKeyBytes = [UInt8](byteArray[index...keyData.count - 1])
        let data = Data(bytes: UnsafePointer<UInt8>(strippedKeyBytes), count: keyData.count - index)
        
        return data
    }
    
    fileprivate func removeKeyWithTagData(_ tagData: Data) {
        let publicKey = NSMutableDictionary()
        publicKey.setObject(kSecClassKey,       forKey: kSecClass as! NSCopying)
        publicKey.setObject(kSecAttrKeyTypeRSA, forKey: kSecAttrKeyType as! NSCopying)
        publicKey.setObject(tagData,            forKey: kSecAttrApplicationTag as! NSCopying)
        SecItemDelete(publicKey as CFDictionary)
    }
    
    deinit {
        for tagData in keyTags {
            removeKeyWithTagData(tagData)
        }
    }
}
