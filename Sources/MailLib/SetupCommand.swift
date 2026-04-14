// SetupCommand.swift
//
// Discover Fastmail identities for the authenticated account.

import Foundation

/// Fetch all send identities from Fastmail via JMAP.
/// Token storage, config construction, and default-identity selection
/// are the caller's responsibility.
public func discoverIdentities(client: JMAPClient) async throws -> [MailIdentity] {
    let responses = try await client.post(
        using: ["urn:ietf:params:jmap:core",
                "urn:ietf:params:jmap:mail",
                "urn:ietf:params:jmap:submission"],
        methodCalls: [
            ["Identity/get",
             ["accountId": client.session.accountId, "ids": NSNull()] as [String: Any],
             "a"]
        ]
    )
    let result = try client.methodResult("Identity/get", from: responses)
    let idList = result["list"] as? [[String: Any]] ?? []

    let identities: [MailIdentity] = idList.compactMap { obj in
        guard let id    = obj["id"]    as? String,
              let email = obj["email"] as? String else { return nil }
        let name = obj["name"] as? String ?? ""
        return MailIdentity(id: id, email: email, name: name)
    }
    guard !identities.isEmpty else { throw MailError.jmapError("No identities found") }
    return identities
}
