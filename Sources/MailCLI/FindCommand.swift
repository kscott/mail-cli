// FindCommand.swift
//
// Search for messages on Fastmail via JMAP and display results.

import Foundation
import MailLib
import GetClearKit

func handleFind(args: [String]) async throws {
    guard args.count > 1 else { fail("provide a search query") }
    let query  = args.dropFirst().joined(separator: " ")
    let token  = try loadToken()
    let client = try await JMAPClient.connect(token: token)

    let responses = try await client.post(methodCalls: [
        ["Email/query", [
            "accountId": client.session.accountId,
            "filter": ["text": query],
            "sort": [["property": "receivedAt", "isAscending": false]],
            "limit": 20,
        ] as [String: Any], "a"],
        ["Email/get", [
            "accountId": client.session.accountId,
            "#ids": ["resultOf": "a", "name": "Email/query", "path": "/ids"],
            "properties": ["subject", "from", "receivedAt"],
        ] as [String: Any], "b"],
    ])

    let emailResult = try client.methodResult("Email/get", from: responses)
    let emails      = emailResult["list"] as? [[String: Any]] ?? []

    if emails.isEmpty { print("No messages matching '\(query)'."); return }

    for (i, email) in emails.enumerated() {
        let subject  = email["subject"]    as? String ?? "(no subject)"
        let from     = (email["from"] as? [[String: Any]])?.first.map { formatAddress($0) } ?? ""
        let received = email["receivedAt"] as? String ?? ""
        let idx      = ANSI.dim(String(i + 1).leftPad(3))
        let dateStr  = ANSI.dim(formatDate(received).leftPad(8))
        let fromStr  = ANSI.dim(String(from.prefix(24)).padding(toLength: 24, withPad: " ", startingAt: 0))
        print("  \(idx)  \(dateStr)  \(fromStr)  \(ANSI.bold(subject))")
    }
}
