// SendCommand.swift
//
// Build and send a JMAP email from parsed send arguments.

import Foundation

public struct SendResult {
    public let summary: String
    public let logDesc: String
}

/// Build and send (or save as draft) a JMAP email.
///
/// - Parameters:
///   - args:     Raw send arguments after stripping the "send" keyword.
///   - config:   Loaded mail config with identities and default sender.
///   - client:   Authenticated JMAP client.
///   - contacts: Resolved contacts for recipient lookup.
///   - groups:   Contact groups for group-address expansion.
/// - Returns:    A `SendResult` with summary text and activity log description for the caller to output.
public func runSend(
    args:     [String],
    config:   MailConfig,
    client:   JMAPClient,
    contacts: [MailContact],
    groups:   [String: [AddressEntry]]
) async throws -> SendResult {
    guard let msg = parseSendArgs(args), !msg.to.isEmpty else {
        throw MailError.sendFailed("provide a recipient")
    }

    let fromEmail = msg.from ?? config.defaultFrom
    guard let identity = config.identity(for: fromEmail) else {
        throw MailError.noMatchingIdentity(fromEmail)
    }

    let (toAddrs, ccAddrs) = buildRecipients(to: msg.to, cc: msg.cc,
                                             groups: groups, contacts: contacts)
    guard !toAddrs.isEmpty else {
        throw MailError.sendFailed("Could not resolve recipient: \(msg.to)")
    }

    let bodyText: String
    if !msg.body.isEmpty && FileManager.default.fileExists(atPath: msg.body) {
        bodyText = (try? String(contentsOfFile: msg.body)) ?? msg.body
    } else {
        bodyText = msg.body
    }

    // Upload attachments
    var attachmentObjects: [[String: Any]] = []
    for path in msg.attachments {
        let blob = try await client.uploadAttachment(path: path)
        attachmentObjects.append(["blobId": blob.blobId, "name": blob.name,
                                  "type": blob.type, "size": blob.size,
                                  "disposition": "attachment"])
    }

    // Resolve Drafts and Sent mailboxes
    guard let draftsId = try await client.findMailboxId(role: "drafts") else {
        throw MailError.jmapError("Could not find Drafts mailbox")
    }
    guard let sentId = try await client.findMailboxId(role: "sent") else {
        throw MailError.jmapError("Could not find Sent mailbox")
    }

    // Build message body structure
    let bodyStructure: [String: Any]
    if attachmentObjects.isEmpty {
        bodyStructure = ["type": "text/plain", "partId": "1"]
    } else {
        var subParts: [[String: Any]] = [["type": "text/plain", "partId": "1"]]
        subParts += attachmentObjects.map { a -> [String: Any] in
            var p: [String: Any] = ["blobId": a["blobId"]!, "type": a["type"]!,
                                    "disposition": "attachment"]
            if let name = a["name"] { p["name"] = name }
            return p
        }
        bodyStructure = ["type": "multipart/mixed", "subParts": subParts]
    }

    var emailCreate: [String: Any] = [
        "mailboxIds":    [draftsId: true],
        "keywords":      ["$draft": true],
        "from":          [["name": identity.name, "email": identity.email]],
        "to":            toAddrs.map { ["name": $0.name, "email": $0.email] },
        "subject":       msg.subject,
        "bodyStructure": bodyStructure,
        "bodyValues":    ["1": ["value": bodyText]],
    ]
    if !ccAddrs.isEmpty { emailCreate["cc"] = ccAddrs.map { ["name": $0.name, "email": $0.email] } }

    let createResponses = try await client.post(
        using: ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail",
                "urn:ietf:params:jmap:submission"],
        methodCalls: [
            ["Email/set", ["accountId": client.session.accountId,
                           "create": ["e1": emailCreate]] as [String: Any], "0"]
        ]
    )
    let createResult = try client.methodResult("Email/set", from: createResponses)

    if let notCreated = createResult["notCreated"] as? [String: Any], !notCreated.isEmpty {
        let desc = (notCreated["e1"] as? [String: Any])?["description"] as? String ?? "unknown"
        throw MailError.sendFailed(desc)
    }
    guard let created  = createResult["created"]  as? [String: Any],
          let emailObj = created["e1"]             as? [String: Any],
          let emailId  = emailObj["id"]             as? String else {
        throw MailError.sendFailed("Email not created")
    }

    if msg.isDraft {
        let toStr = toAddrs.map { $0.formatted }.joined(separator: ", ")
        let summary = "Saved draft to \(toStr)\(msg.subject.isEmpty ? "" : " — \(msg.subject)")"
        return SendResult(summary: summary, logDesc: "draft: \(toStr)")
    }

    let submitResponses = try await client.post(
        using: ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail",
                "urn:ietf:params:jmap:submission"],
        methodCalls: [
            ["EmailSubmission/set", [
                "accountId": client.session.accountId,
                "create": ["s1": ["emailId": emailId, "identityId": identity.id]],
                "onSuccessUpdateEmail": [
                    "#s1": [
                        "keywords/$draft":          NSNull(),
                        "mailboxIds/\(draftsId)":   NSNull(),
                        "mailboxIds/\(sentId)":     true,
                    ]
                ],
            ] as [String: Any], "0"]
        ]
    )
    let submitResult = try client.methodResult("EmailSubmission/set", from: submitResponses)

    if let notCreated = submitResult["notCreated"] as? [String: Any], !notCreated.isEmpty {
        let desc = (notCreated["s1"] as? [String: Any])?["description"] as? String ?? "unknown"
        throw MailError.sendFailed("Submission failed: \(desc)")
    }

    let toStr = toAddrs.map { $0.formatted }.joined(separator: ", ")
    var summary = "Sent to \(toStr)"
    if !ccAddrs.isEmpty     { summary += "; cc \(ccAddrs.map { $0.formatted }.joined(separator: ", "))" }
    if !msg.subject.isEmpty { summary += " — \(msg.subject)" }
    let logDesc = msg.subject.isEmpty
        ? toStr
        : "\(toStr) Re: \(msg.subject)"

    return SendResult(summary: summary, logDesc: logDesc)
}
