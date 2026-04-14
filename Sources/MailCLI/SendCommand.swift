// SendCommand.swift
//
// Load contacts and dispatch to MailLib runSend.

import Foundation
import Contacts
import MailLib
import GetClearKit

private let contactKeys: [CNKeyDescriptor] = [
    CNContactGivenNameKey    as CNKeyDescriptor,
    CNContactFamilyNameKey   as CNKeyDescriptor,
    CNContactEmailAddressesKey as CNKeyDescriptor,
]

private func loadContacts(from store: CNContactStore) -> [MailContact] {
    let request = CNContactFetchRequest(keysToFetch: contactKeys)
    var results: [MailContact] = []
    try? store.enumerateContacts(with: request) { c, _ in
        let name   = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let emails = c.emailAddresses.map { $0.value as String }
        if !emails.isEmpty { results.append(MailContact(name: name, emails: emails)) }
    }
    return results
}

private func loadGroups(from store: CNContactStore) -> [String: [AddressEntry]] {
    let groups = (try? store.groups(matching: nil)) ?? []
    let keys   = [CNContactGivenNameKey, CNContactFamilyNameKey,
                  CNContactEmailAddressesKey] as [CNKeyDescriptor]
    var result: [String: [AddressEntry]] = [:]
    for group in groups {
        let pred    = CNContact.predicateForContactsInGroup(withIdentifier: group.identifier)
        let members = (try? store.unifiedContacts(matching: pred, keysToFetch: keys)) ?? []
        let addrs: [AddressEntry] = members.compactMap { c in
            guard let email = c.emailAddresses.first?.value as String? else { return nil }
            let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            return AddressEntry(name: name, email: email)
        }
        if !addrs.isEmpty { result[group.name] = addrs }
    }
    return result
}

func handleSend(args: [String]) async throws {
    guard args.count > 1 else { fail("provide a recipient") }
    let sendArgs = Array(args.dropFirst())

    let contactStore = CNContactStore()
    let granted = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
        contactStore.requestAccess(for: .contacts) { ok, err in
            if let err = err { cont.resume(throwing: err) }
            else             { cont.resume(returning: ok) }
        }
    }
    guard granted else { fail("Contacts access denied") }

    let token   = try loadToken()
    let config  = try loadConfig()
    let client  = try await JMAPClient.connect(token: token)
    let contacts = loadContacts(from: contactStore)
    let groups   = loadGroups(from: contactStore)

    let result = try await runSend(args: sendArgs, config: config, client: client,
                                   contacts: contacts, groups: groups)
    print(result.summary)
    try? ActivityLog.write(tool: "mail", cmd: "send", desc: result.logDesc, container: nil)
}
