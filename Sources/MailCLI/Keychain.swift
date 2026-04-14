// Keychain.swift
//
// Store and load the JMAP token in the system Keychain.

import Foundation
import Security
import MailLib

private let keychainService = "mail-cli"
private let keychainAccount = "jmap-token"

func loadToken() throws -> String {
    let query: [String: Any] = [
        kSecClass      as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
          let data  = item as? Data,
          let token = String(data: data, encoding: .utf8) else {
        throw MailError.noToken
    }
    return token
}

func storeToken(_ token: String) throws {
    let attrs: [String: Any] = [
        kSecClass      as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount,
        kSecValueData  as String: Data(token.utf8),
    ]
    SecItemDelete(attrs as CFDictionary)
    let status = SecItemAdd(attrs as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw MailError.jmapError("Keychain store failed (OSStatus \(status))")
    }
}
