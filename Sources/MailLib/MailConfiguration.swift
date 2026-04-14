// MailConfiguration.swift
//
// Load, parse, and write the mail-cli config file.

import Foundation

public struct MailIdentity: Equatable {
    public let id:    String
    public let email: String
    public let name:  String

    public init(id: String, email: String, name: String) {
        self.id    = id
        self.email = email
        self.name  = name
    }
}

public struct MailConfig {
    public var defaultFrom: String
    public var identities:  [MailIdentity]

    public init(defaultFrom: String, identities: [MailIdentity]) {
        self.defaultFrom = defaultFrom
        self.identities  = identities
    }

    public func identity(for email: String) -> MailIdentity? {
        identities.first { $0.email.caseInsensitiveCompare(email) == .orderedSame }
    }

    public var defaultIdentity: MailIdentity? { identity(for: defaultFrom) }
}

public let configURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/mail-cli/config.toml")

public func parseConfig(_ content: String) -> MailConfig {
    var defaultFrom = ""
    var identities: [MailIdentity] = []
    var inIdentities = false

    for rawLine in content.components(separatedBy: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        if line == "[identities]" { inIdentities = true; continue }
        if line.hasPrefix("[")   { inIdentities = false; continue }

        guard let eqRange = line.range(of: "=") else { continue }
        let key   = line[..<eqRange.lowerBound].trimmingCharacters(in: .whitespaces)
        let value = line[eqRange.upperBound...]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        if inIdentities {
            // key = identity id, value = "email|display name"
            let parts = value.components(separatedBy: "|")
            if parts.count >= 2 {
                identities.append(MailIdentity(id: key, email: parts[0],
                                               name: parts[1...].joined(separator: "|")))
            }
        } else {
            if key == "default_from" { defaultFrom = value }
        }
    }

    return MailConfig(defaultFrom: defaultFrom, identities: identities)
}

public func loadConfig(from url: URL = configURL) throws -> MailConfig {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else {
        throw MailError.noConfig
    }
    return parseConfig(content)
}

public func saveConfig(_ config: MailConfig, to url: URL = configURL) throws {
    var lines = [
        "default_from = \"\(config.defaultFrom)\"",
        "",
        "[identities]",
        "# id = \"email|display name\"",
    ]
    for id in config.identities {
        lines.append("\(id.id) = \"\(id.email)|\(id.name)\"")
    }
    let content = lines.joined(separator: "\n") + "\n"
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try content.write(to: url, atomically: true, encoding: .utf8)
}
