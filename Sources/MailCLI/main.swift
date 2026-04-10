// main.swift
//
// Entry point for mail-bin executable.
// Handles argument parsing, Keychain, JMAP, and Contacts interactions.
// Matching and parsing logic delegated to MailLib for unit testing.

import Foundation
import Contacts
import Security
import MailLib
import GetClearKit

let version = builtVersion
let versionString = "\(builtVersion) (Get Clear \(suiteVersion))"
let args    = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
    mail \(versionString) — CLI for Fastmail via JMAP

    Usage:
      mail setup [token]                   # Store JMAP token, discover identities
      mail send <to> [cc <cc>] [from <from>] [subject <subject>] [attach <file>] [body <text>] [--draft]
      mail find <query>                    # Find messages for context before composing
      mail open                            # Open Fastmail in browser

    Feedback: https://github.com/kscott/get-clear/issues
    """)
    exit(0)
}

// MARK: - Error types

enum MailError: Error, LocalizedError {
    case noToken
    case noConfig
    case noMatchingIdentity(String)
    case sendFailed(String)
    case notFound(String)
    case jmapError(String)

    var errorDescription: String? {
        switch self {
        case .noToken:                   return "No JMAP token — run 'mail setup' first"
        case .noConfig:                  return "No config — run 'mail setup' first"
        case .noMatchingIdentity(let e): return "No identity found for '\(e)' — run 'mail setup' to refresh"
        case .sendFailed(let m):         return "Send failed: \(m)"
        case .notFound(let q):           return "Not found: \(q)"
        case .jmapError(let m):          return "JMAP error: \(m)"
        }
    }
}

// MARK: - Keychain

private let keychainService = "mail-cli"
private let keychainAccount = "kscott@imap.cc"

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

// MARK: - Config

struct MailIdentity {
    let id:    String
    let email: String
    let name:  String
}

struct MailConfig {
    var defaultFrom: String
    var identities:  [MailIdentity]

    func identity(for email: String) -> MailIdentity? {
        identities.first { $0.email.caseInsensitiveCompare(email) == .orderedSame }
    }

    var defaultIdentity: MailIdentity? { identity(for: defaultFrom) }
}

private let configURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/mail-cli/config.toml")

func loadConfig() throws -> MailConfig {
    guard let content = try? String(contentsOf: configURL) else { throw MailError.noConfig }
    return parseConfig(content)
}

func parseConfig(_ content: String) -> MailConfig {
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

func saveConfig(_ config: MailConfig) throws {
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
    try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try content.write(to: configURL, atomically: true, encoding: .utf8)
}

// MARK: - JMAP session

struct JMAPSession {
    let apiUrl:    String
    let uploadUrl: String
    let accountId: String
}

/// URLSession delegate that preserves the Authorization header across redirects.
private class AuthRedirectDelegate: NSObject, URLSessionTaskDelegate {
    let token: String
    init(token: String) { self.token = token }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var r = request
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        completionHandler(r)
    }
}

func fetchSession(token: String) async throws -> JMAPSession {
    var req = URLRequest(url: URL(string: "https://api.fastmail.com/.well-known/jmap")!)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let delegate = AuthRedirectDelegate(token: token)
    let session  = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    let (data, _) = try await session.data(for: req)
    guard let json          = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let apiUrl        = json["apiUrl"]        as? String,
          let uploadUrl     = json["uploadUrl"]     as? String,
          let primaryAccts  = json["primaryAccounts"] as? [String: String],
          let accountId     = primaryAccts["urn:ietf:params:jmap:mail"] else {
        throw MailError.jmapError("Invalid JMAP session response")
    }
    return JMAPSession(apiUrl: apiUrl, uploadUrl: uploadUrl, accountId: accountId)
}

// MARK: - JMAP calls

func jmapPost(token: String, apiUrl: String,
              using caps: [String] = ["urn:ietf:params:jmap:core",
                                      "urn:ietf:params:jmap:mail"],
              methodCalls: [[Any]]) async throws -> [[Any]] {
    let body: [String: Any] = ["using": caps, "methodCalls": methodCalls]
    var req = URLRequest(url: URL(string: apiUrl)!)
    req.httpMethod = "POST"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, _) = try await URLSession.shared.data(for: req)
    guard let json      = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let responses = json["methodResponses"] as? [[Any]] else {
        throw MailError.jmapError("Invalid JMAP response")
    }
    return responses
}

func methodResult(name: String, from responses: [[Any]]) throws -> [String: Any] {
    // Check for top-level error response first
    if let errResp   = responses.first(where: { ($0[0] as? String) == "error" }),
       let errResult = errResp[1] as? [String: Any] {
        let desc = errResult["description"] as? String ?? errResult["type"] as? String ?? "unknown"
        throw MailError.jmapError(desc)
    }
    guard let resp   = responses.first(where: { ($0[0] as? String) == name }),
          let result = resp[1] as? [String: Any] else {
        throw MailError.jmapError("\(name) response missing")
    }
    return result
}

// MARK: - JMAP upload

func uploadAttachment(token: String, session: JMAPSession, path: String) async throws
    -> (blobId: String, type: String, name: String, size: Int) {
    let url  = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    let mime = mimeType(for: path)

    let uploadEndpoint = session.uploadUrl
        .replacingOccurrences(of: "{accountId}", with: session.accountId)
    var req = URLRequest(url: URL(string: uploadEndpoint)!)
    req.httpMethod = "POST"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(mime, forHTTPHeaderField: "Content-Type")
    req.httpBody = data

    let delegate = AuthRedirectDelegate(token: token)
    let uploadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    let (respData, _) = try await uploadSession.data(for: req)
    guard let json   = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
          let blobId = json["blobId"] as? String else {
        throw MailError.jmapError("Upload failed for \(path)")
    }
    return (blobId: blobId, type: mime, name: url.lastPathComponent, size: data.count)
}

func mimeType(for path: String) -> String {
    switch URL(fileURLWithPath: path).pathExtension.lowercased() {
    case "pdf":         return "application/pdf"
    case "png":         return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif":         return "image/gif"
    case "txt":         return "text/plain"
    case "html":        return "text/html"
    case "zip":         return "application/zip"
    default:            return "application/octet-stream"
    }
}

// MARK: - Mailbox lookup

func findMailboxId(role: String, token: String, session: JMAPSession) async throws -> String? {
    let responses = try await jmapPost(token: token, apiUrl: session.apiUrl, methodCalls: [
        ["Mailbox/get", ["accountId": session.accountId, "ids": NSNull()] as [String: Any], "a"]
    ])
    let result    = try methodResult(name: "Mailbox/get", from: responses)
    let mailboxes = result["list"] as? [[String: Any]] ?? []
    return mailboxes.first(where: {
        ($0["role"] as? String)?.lowercased() == role.lowercased()
    })?["id"] as? String
}

// MARK: - Contacts loading

private let keysToFetch: [CNKeyDescriptor] = [
    CNContactGivenNameKey    as CNKeyDescriptor,
    CNContactFamilyNameKey   as CNKeyDescriptor,
    CNContactEmailAddressesKey as CNKeyDescriptor,
]

func loadContacts(from store: CNContactStore) -> [MailContact] {
    let request = CNContactFetchRequest(keysToFetch: keysToFetch)
    var results: [MailContact] = []
    try? store.enumerateContacts(with: request) { c, _ in
        let name   = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        let emails = c.emailAddresses.map { $0.value as String }
        if !emails.isEmpty { results.append(MailContact(name: name, emails: emails)) }
    }
    return results
}

func loadGroups(from store: CNContactStore) -> [String: [AddressEntry]] {
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

// MARK: - Formatting helpers

func formatEmailDate(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = f.date(from: iso)
    if date == nil { f.formatOptions = [.withInternetDateTime]; date = f.date(from: iso) }
    guard let date else { return iso }

    let cal = Calendar.current
    let now = Date()
    let df  = DateFormatter()
    if cal.isDateInToday(date) {
        df.dateFormat = "h:mma"
        return df.string(from: date).lowercased()
    } else if cal.component(.year, from: date) == cal.component(.year, from: now) {
        df.dateFormat = "MMM dd"
        return df.string(from: date)
    } else {
        df.dateFormat = "yyyy MMM"
        return df.string(from: date)
    }
}

func formatEmailDateLong(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = f.date(from: iso)
    if date == nil { f.formatOptions = [.withInternetDateTime]; date = f.date(from: iso) }
    guard let date else { return iso }
    let df = DateFormatter(); df.dateStyle = .full; df.timeStyle = .short
    return df.string(from: date)
}

func formatAddr(_ a: [String: Any]) -> String {
    let name  = a["name"]  as? String ?? ""
    let email = a["email"] as? String ?? ""
    return name.isEmpty ? email : "\(name) <\(email)>"
}

func formatAddrs(_ addrs: [[String: Any]]) -> String {
    addrs.map(formatAddr).joined(separator: ", ")
}

// MARK: - Commands

func runSetup(tokenArg: String?) async throws {
    let token: String
    if let t = tokenArg {
        token = t
    } else if let existing = try? loadToken() {
        token = existing
    } else {
        print("Enter your Fastmail JMAP token: ", terminator: "")
        guard let t = readLine(strippingNewline: true), !t.isEmpty else {
            throw MailError.jmapError("No token provided")
        }
        token = t
    }

    print("Connecting to Fastmail...")
    let session = try await fetchSession(token: token)

    print("Fetching identities...")
    let responses = try await jmapPost(
        token: token, apiUrl: session.apiUrl,
        using: ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail",
                "urn:ietf:params:jmap:submission"],
        methodCalls: [
            ["Identity/get", ["accountId": session.accountId, "ids": NSNull()] as [String: Any], "a"]
        ]
    )
    let result  = try methodResult(name: "Identity/get", from: responses)
    let idList  = result["list"] as? [[String: Any]] ?? []

    let identities: [MailIdentity] = idList.compactMap { obj in
        guard let id    = obj["id"]    as? String,
              let email = obj["email"] as? String else { return nil }
        let name = obj["name"] as? String ?? ""
        return MailIdentity(id: id, email: email, name: name)
    }
    guard !identities.isEmpty else { throw MailError.jmapError("No identities found") }

    let defaultFrom = identities.first(where: { $0.email == "ken@optikos.net" })?.email
        ?? identities[0].email

    let config = MailConfig(defaultFrom: defaultFrom, identities: identities)
    try storeToken(token)
    try saveConfig(config)

    print("Setup complete. Found \(identities.count) identities:")
    for id in identities { print("  \(id.email)\(id.name.isEmpty ? "" : " (\(id.name))")") }
    print("Default sender: \(defaultFrom)")
}

func runSend(sendArgs: [String], contactStore: CNContactStore) async throws {
    guard let msg = parseSendArgs(sendArgs), !msg.to.isEmpty else { fail("provide a recipient") }

    let token  = try loadToken()
    let config = try loadConfig()

    let fromEmail = msg.from ?? config.defaultFrom
    guard let identity = config.identity(for: fromEmail) else {
        throw MailError.noMatchingIdentity(fromEmail)
    }

    // Resolve recipients via contacts
    let contacts = loadContacts(from: contactStore)
    let groups   = loadGroups(from: contactStore)

    let (toAddrs, ccAddrs) = buildRecipients(to: msg.to, cc: msg.cc, groups: groups, contacts: contacts)
    guard !toAddrs.isEmpty else { fail("Could not resolve recipient: \(msg.to)") }

    // Body: expand file path if given
    let bodyText: String
    if !msg.body.isEmpty && FileManager.default.fileExists(atPath: msg.body) {
        bodyText = (try? String(contentsOfFile: msg.body)) ?? msg.body
    } else {
        bodyText = msg.body
    }

    let session = try await fetchSession(token: token)

    // Upload attachments
    var attachmentObjects: [[String: Any]] = []
    for path in msg.attachments {
        let up = try await uploadAttachment(token: token, session: session, path: path)
        attachmentObjects.append(["blobId": up.blobId, "name": up.name,
                                  "type": up.type, "size": up.size,
                                  "disposition": "attachment"])
    }

    // Find Drafts and Sent mailboxes
    guard let draftsId = try await findMailboxId(role: "drafts", token: token, session: session) else {
        throw MailError.jmapError("Could not find Drafts mailbox")
    }
    guard let sentId = try await findMailboxId(role: "sent", token: token, session: session) else {
        throw MailError.jmapError("Could not find Sent mailbox")
    }

    // Build email create object
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

    // Create the email
    let createResponses = try await jmapPost(
        token: token, apiUrl: session.apiUrl,
        using: ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail",
                "urn:ietf:params:jmap:submission"],
        methodCalls: [
            ["Email/set", ["accountId": session.accountId,
                           "create": ["e1": emailCreate]] as [String: Any], "0"]
        ]
    )
    let createResult = try methodResult(name: "Email/set", from: createResponses)

    if let notCreated = createResult["notCreated"] as? [String: Any], !notCreated.isEmpty {
        let desc = (notCreated["e1"] as? [String: Any])?["description"] as? String ?? "unknown"
        throw MailError.sendFailed(desc)
    }
    guard let created  = createResult["created"] as? [String: Any],
          let emailObj = created["e1"]            as? [String: Any],
          let emailId  = emailObj["id"]            as? String else {
        throw MailError.sendFailed("Email not created")
    }

    if msg.isDraft {
        let toStr = toAddrs.map { $0.formatted }.joined(separator: ", ")
        print("Saved draft to \(toStr)\(msg.subject.isEmpty ? "" : " — \(msg.subject)")")
        return
    }

    // Submit
    let submitResponses = try await jmapPost(
        token: token, apiUrl: session.apiUrl,
        using: ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail",
                "urn:ietf:params:jmap:submission"],
        methodCalls: [
            ["EmailSubmission/set", [
                "accountId": session.accountId,
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
    let submitResult = try methodResult(name: "EmailSubmission/set", from: submitResponses)

    if let notCreated = submitResult["notCreated"] as? [String: Any], !notCreated.isEmpty {
        let desc = (notCreated["s1"] as? [String: Any])?["description"] as? String ?? "unknown"
        throw MailError.sendFailed("Submission failed: \(desc)")
    }

    var summary = "Sent to \(toAddrs.map { $0.formatted }.joined(separator: ", "))"
    if !ccAddrs.isEmpty    { summary += "; cc \(ccAddrs.map { $0.formatted }.joined(separator: ", "))" }
    if !msg.subject.isEmpty { summary += " — \(msg.subject)" }
    let logDesc = msg.subject.isEmpty
        ? toAddrs.map { $0.formatted }.joined(separator: ", ")
        : "\(toAddrs.map { $0.formatted }.joined(separator: ", ")) Re: \(msg.subject)"
    try? ActivityLog.write(tool: "mail", cmd: "send", desc: logDesc, container: nil)
    print(summary)
}

func runSearch(query: String, token: String, session: JMAPSession) async throws {
    let responses = try await jmapPost(token: token, apiUrl: session.apiUrl, methodCalls: [
        ["Email/query", [
            "accountId": session.accountId,
            "filter": ["text": query],
            "sort": [["property": "receivedAt", "isAscending": false]],
            "limit": 20,
        ] as [String: Any], "a"],
        ["Email/get", [
            "accountId": session.accountId,
            "#ids": ["resultOf": "a", "name": "Email/query", "path": "/ids"],
            "properties": ["subject", "from", "receivedAt"],
        ] as [String: Any], "b"],
    ])

    let emailResult = try methodResult(name: "Email/get", from: responses)
    let emails      = emailResult["list"] as? [[String: Any]] ?? []

    if emails.isEmpty { print("No messages matching '\(query)'."); return }

    for (i, email) in emails.enumerated() {
        let subject  = email["subject"]    as? String ?? "(no subject)"
        let from     = (email["from"] as? [[String: Any]])?.first.map { formatAddr($0) } ?? ""
        let received = email["receivedAt"] as? String ?? ""
        let idx      = ANSI.dim(String(i + 1).leftPad(3))
        let dateStr  = ANSI.dim(formatEmailDate(received).leftPad(8))
        let fromStr  = ANSI.dim(String(from.prefix(24)).padding(toLength: 24, withPad: " ", startingAt: 0))
        print("  \(idx)  \(dateStr)  \(fromStr)  \(ANSI.bold(subject))")
    }
}

// MARK: - String padding helper

extension String {
    func leftPad(_ length: Int) -> String {
        if count >= length { return self }
        return String(repeating: " ", count: length - count) + self
    }
}

// MARK: - Dispatch

let dispatch = parseArgs(args)
if case .version = dispatch { print(versionString); exit(0) }
guard case .command(let cmd, let args) = dispatch else { usage() }

let semaphore = DispatchSemaphore(value: 0)

Task {
    do {
        switch cmd {

        case "what":
            let rangeStr = args.count > 1 ? Array(args.dropFirst()).joined(separator: " ") : "today"
            guard let range = parseRange(rangeStr) else { fail("Unrecognised range: \(rangeStr)") }
            let isToday = rangeStr == "today"
            let entries: [ActivityLogEntry]
            var dateUsed = Date()
            if isToday {
                let result = ActivityLogReader.entriesForDisplay(in: range.start...range.end)
                entries  = result.entries
                dateUsed = result.dateUsed
            } else {
                entries = ActivityLogReader.entries(in: range.start...range.end, tool: "mail")
            }
            print(ActivityLogFormatter.perToolWhat(entries: entries, range: range, rangeStr: rangeStr,
                                                   tool: "mail", dateUsed: dateUsed))

        case "open":
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["https://app.fastmail.com"]
            try p.run()

        case "setup":
            let tokenArg = args.count > 1 ? args[1] : nil
            try await runSetup(tokenArg: tokenArg)

        case "send":
            guard args.count > 1 else { fail("provide a recipient") }
            let sendArgs = Array(args.dropFirst())

            let store = CNContactStore()
            let granted = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
                store.requestAccess(for: .contacts) { ok, err in
                    if let err = err { cont.resume(throwing: err) }
                    else             { cont.resume(returning: ok) }
                }
            }
            guard granted else { fail("Contacts access denied") }
            try await runSend(sendArgs: sendArgs, contactStore: store)

        case "find":
            guard args.count > 1 else { fail("provide a search query") }
            let query   = args.dropFirst().joined(separator: " ")
            let token   = try loadToken()
            let session = try await fetchSession(token: token)
            try await runSearch(query: query, token: token, session: session)

        default:
            usage()
        }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
    semaphore.signal()
}

semaphore.wait()


UpdateChecker.spawnBackgroundCheckIfNeeded()
if let hint = UpdateChecker.hint() { fputs(hint + "\n", stderr) }
