// RecipientResolver.swift
//
// Resolve a recipient string to one or more email addresses.
// No framework dependencies — pure Swift, fully unit testable.

import Foundation

public struct MailContact {
    public let name: String
    public let emails: [String]

    public init(name: String, emails: [String]) {
        self.name   = name
        self.emails = emails
    }
}

public struct AddressEntry: Equatable {
    public let name: String
    public let email: String

    public init(name: String, email: String) {
        self.name  = name
        self.email = email
    }

    /// Formatted as "Name <email>" for use in To/Cc fields.
    public var formatted: String {
        name.isEmpty ? email : "\(name) <\(email)>"
    }
}

/// Resolve a recipient string to one or more AddressEntry values.
///
/// Resolution order:
///   1. Exact group name (case-insensitive) → all members
///   2. Raw email address (contains @) → direct
///   3. Fuzzy contact match (name or email) → primary email
///   4. No match → empty array
public func resolveRecipients(
    _ input: String,
    groups:   [String: [AddressEntry]],
    contacts: [MailContact]
) -> [AddressEntry] {
    let q  = input.trimmingCharacters(in: .whitespaces)
    let ql = q.lowercased()

    // 1. Exact group name
    if let members = groups.first(where: { $0.key.caseInsensitiveCompare(q) == .orderedSame })?.value {
        return members
    }

    // 2. Raw email address — use exactly as given, look up name from contacts
    if q.contains("@") {
        let name = contacts.first(where: { $0.emails.contains(where: { $0.caseInsensitiveCompare(q) == .orderedSame }) })?.name ?? ""
        return [AddressEntry(name: name, email: q)]
    }

    // 3. Fuzzy contact match: exact name, prefix, contains, email contains
    func score(_ c: MailContact) -> Int? {
        let name = c.name.lowercased()
        if name == ql                                           { return 0 }
        if name.hasPrefix(ql)                                   { return 1 }
        if name.contains(ql)                                    { return 2 }
        if c.emails.contains(where: { $0.lowercased().contains(ql) }) { return 3 }
        return nil
    }
    let matched = contacts
        .compactMap { c in score(c).map { (c, $0) } }
        .sorted { $0.1 < $1.1 }
        .map { $0.0 }
    if let first = matched.first, let email = first.emails.first {
        return [AddressEntry(name: first.name, email: email)]
    }

    return []
}
