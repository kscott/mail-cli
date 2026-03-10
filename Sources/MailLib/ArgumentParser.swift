// ArgumentParser.swift
//
// Parse `mail send` arguments into a ComposedMessage.
// No framework dependencies — pure Swift, fully unit testable.

import Foundation

public struct ComposedMessage {
    public let to: String          // unresolved recipient string
    public let cc: [String]        // unresolved cc recipient strings
    public let from: String?       // nil → use default identity
    public let subject: String
    public let body: String        // raw text; caller handles file-path expansion
    public let attachments: [String]
    public let isDraft: Bool

    public init(to: String, cc: [String], from: String?, subject: String,
                body: String, attachments: [String], isDraft: Bool) {
        self.to          = to
        self.cc          = cc
        self.from        = from
        self.subject     = subject
        self.body        = body
        self.attachments = attachments
        self.isDraft     = isDraft
    }
}

private let sendKeywords: Set<String> = ["cc", "from", "subject", "attach", "body"]

private func isKeyword(_ s: String) -> Bool {
    sendKeywords.contains(s.lowercased())
}

/// Parse everything after "send" into a ComposedMessage.
/// `to` = all tokens before the first keyword (no quoting needed for multi-word names).
/// Keywords can appear in any order; `body` must be last — it captures to end of string.
/// Returns nil if no recipient token is found.
public func parseSendArgs(_ args: [String]) -> ComposedMessage? {
    var tokens = args

    // Extract --draft flag
    let isDraft = tokens.contains("--draft")
    tokens = tokens.filter { $0 != "--draft" }

    guard !tokens.isEmpty else { return nil }

    // `to` = all tokens before the first keyword
    var toTokens: [String] = []
    var i = 0
    while i < tokens.count && !isKeyword(tokens[i]) {
        toTokens.append(tokens[i])
        i += 1
    }
    guard !toTokens.isEmpty else { return nil }
    let to = toTokens.joined(separator: " ")

    // Parse keyword sections
    var cc:          [String] = []
    var from:        String?  = nil
    var subject:     String   = ""
    var body:        String   = ""
    var attachments: [String] = []

    while i < tokens.count {
        let tok = tokens[i].lowercased()
        switch tok {
        case "body":
            i += 1
            body = tokens[i...].joined(separator: " ")
            i = tokens.count  // body captures to end — stop

        case "subject":
            i += 1
            var parts: [String] = []
            while i < tokens.count && !isKeyword(tokens[i]) {
                parts.append(tokens[i])
                i += 1
            }
            subject = parts.joined(separator: " ")

        case "from":
            i += 1
            if i < tokens.count { from = tokens[i]; i += 1 }

        case "cc":
            // cc captures tokens until next keyword (supports multi-word contact names)
            i += 1
            var ccTokens: [String] = []
            while i < tokens.count && !isKeyword(tokens[i]) {
                ccTokens.append(tokens[i])
                i += 1
            }
            if !ccTokens.isEmpty { cc.append(ccTokens.joined(separator: " ")) }

        case "attach":
            i += 1
            if i < tokens.count { attachments.append(tokens[i]); i += 1 }

        default:
            i += 1
        }
    }

    return ComposedMessage(to: to, cc: cc, from: from, subject: subject,
                           body: body, attachments: attachments, isDraft: isDraft)
}
