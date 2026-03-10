// main.swift — test runner for MailLib
//
// Does not require Xcode or XCTest — runs with just the Swift CLI toolchain.
// Run via:  mail test

import Foundation
import MailLib

// MARK: - Minimal test harness

final class TestRunner: @unchecked Sendable {
    private var passed = 0
    private var failed = 0

    func expect(_ description: String, _ condition: Bool, file: String = #file, line: Int = #line) {
        if condition {
            print("  ✓ \(description)")
            passed += 1
        } else {
            print("  ✗ \(description)  [\(URL(fileURLWithPath: file).lastPathComponent):\(line)]")
            failed += 1
        }
    }

    func suite(_ name: String, _ body: () -> Void) {
        print("\n\(name)")
        body()
    }

    func summary() {
        print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}

let t = TestRunner()

// MARK: - parseSendArgs tests

t.suite("parseSendArgs — basic recipient") {
    let m = parseSendArgs(["alice@example.com"])
    t.expect("to is set",       m?.to == "alice@example.com")
    t.expect("no subject",      m?.subject == "")
    t.expect("no body",         m?.body == "")
    t.expect("not draft",       m?.isDraft == false)
    t.expect("no attachments",  m?.attachments.isEmpty == true)
}

t.suite("parseSendArgs — multi-word recipient") {
    let m = parseSendArgs(["Jane", "Doe", "subject", "Hi"])
    t.expect("to = Jane Doe",    m?.to == "Jane Doe")
    t.expect("subject = Hi",     m?.subject == "Hi")
}

t.suite("parseSendArgs — subject with multiple words") {
    let m = parseSendArgs(["alice", "subject", "Hello", "World"])
    t.expect("to = alice",               m?.to == "alice")
    t.expect("subject = Hello World",    m?.subject == "Hello World")
}

t.suite("parseSendArgs — body captures to end") {
    let m = parseSendArgs(["alice", "subject", "Hi", "body", "Hello", "there"])
    t.expect("subject = Hi",            m?.subject == "Hi")
    t.expect("body = Hello there",      m?.body == "Hello there")
}

t.suite("parseSendArgs — from keyword") {
    let m = parseSendArgs(["alice", "from", "ken@optikos.net"])
    t.expect("from is set",  m?.from == "ken@optikos.net")
}

t.suite("parseSendArgs — cc keyword") {
    let m = parseSendArgs(["alice", "cc", "bob@example.com"])
    t.expect("cc has one entry",         m?.cc.count == 1)
    t.expect("cc = bob@example.com",     m?.cc.first == "bob@example.com")
}

t.suite("parseSendArgs — multi-word cc") {
    let m = parseSendArgs(["alice", "cc", "Bob", "Jones", "subject", "Hi"])
    t.expect("cc = Bob Jones",   m?.cc.first == "Bob Jones")
    t.expect("subject = Hi",     m?.subject == "Hi")
}

t.suite("parseSendArgs — multiple cc (repeated keyword)") {
    let m = parseSendArgs(["alice", "cc", "bob", "cc", "carol"])
    t.expect("two cc entries",  m?.cc.count == 2)
    t.expect("first cc = bob",  m?.cc[0] == "bob")
    t.expect("second cc = carol", m?.cc[1] == "carol")
}

t.suite("parseSendArgs — attach") {
    let m = parseSendArgs(["alice", "attach", "/tmp/file.pdf"])
    t.expect("one attachment",          m?.attachments.count == 1)
    t.expect("path is set",             m?.attachments.first == "/tmp/file.pdf")
}

t.suite("parseSendArgs — multiple attachments") {
    let m = parseSendArgs(["alice", "attach", "/tmp/a.pdf", "attach", "/tmp/b.pdf"])
    t.expect("two attachments",         m?.attachments.count == 2)
}

t.suite("parseSendArgs — --draft flag") {
    let m = parseSendArgs(["--draft", "alice", "subject", "Hi"])
    t.expect("isDraft = true",   m?.isDraft == true)
    t.expect("to = alice",       m?.to == "alice")
    t.expect("subject = Hi",     m?.subject == "Hi")
}

t.suite("parseSendArgs — --draft at end") {
    let m = parseSendArgs(["alice", "subject", "Hi", "--draft"])
    t.expect("isDraft = true",  m?.isDraft == true)
}

t.suite("parseSendArgs — all keywords") {
    let m = parseSendArgs(["alice", "cc", "bob", "from", "ken@optikos.net",
                            "subject", "Meeting", "attach", "/tmp/doc.pdf",
                            "body", "See attached"])
    t.expect("to = alice",              m?.to == "alice")
    t.expect("cc = [bob]",              m?.cc == ["bob"])
    t.expect("from = ken@optikos.net",  m?.from == "ken@optikos.net")
    t.expect("subject = Meeting",       m?.subject == "Meeting")
    t.expect("attachment set",          m?.attachments == ["/tmp/doc.pdf"])
    t.expect("body = See attached",     m?.body == "See attached")
}

t.suite("parseSendArgs — empty args") {
    t.expect("nil for empty",   parseSendArgs([]) == nil)
}

t.suite("parseSendArgs — only keywords, no to") {
    t.expect("nil when no recipient",  parseSendArgs(["subject", "Hi"]) == nil)
}

// MARK: - resolveRecipients tests

let alice   = MailContact(name: "Alice Smith",   emails: ["alice@example.com"])
let bob     = MailContact(name: "Bob Jones",     emails: ["bob@jones.org"])
let charlie = MailContact(name: "Charlie Brown", emails: ["cbrown@peanuts.com"])
let noEmail = MailContact(name: "Dana White",    emails: [])

let allContacts = [alice, bob, charlie, noEmail]

let groups: [String: [AddressEntry]] = [
    "Board": [AddressEntry(name: "Alice Smith", email: "alice@example.com"),
              AddressEntry(name: "Bob Jones",   email: "bob@jones.org")],
]

t.suite("resolveRecipients — group name") {
    let r = resolveRecipients("Board", groups: groups, contacts: allContacts)
    t.expect("returns all group members",  r.count == 2)
    t.expect("first member is Alice",      r[0].name == "Alice Smith")
}

t.suite("resolveRecipients — group name case-insensitive") {
    let r = resolveRecipients("board", groups: groups, contacts: allContacts)
    t.expect("case-insensitive match",  r.count == 2)
}

t.suite("resolveRecipients — exact contact name") {
    let r = resolveRecipients("Alice Smith", groups: groups, contacts: allContacts)
    t.expect("finds Alice",             r.count == 1)
    t.expect("email is correct",        r.first?.email == "alice@example.com")
}

t.suite("resolveRecipients — partial contact name") {
    let r = resolveRecipients("alice", groups: groups, contacts: allContacts)
    t.expect("finds Alice by prefix",   r.count == 1)
    t.expect("name preserved",          r.first?.name == "Alice Smith")
}

t.suite("resolveRecipients — email fragment") {
    let r = resolveRecipients("jones.org", groups: groups, contacts: allContacts)
    t.expect("finds Bob by email",      r.count == 1)
    t.expect("name = Bob Jones",        r.first?.name == "Bob Jones")
}

t.suite("resolveRecipients — raw email address") {
    let r = resolveRecipients("new@person.com", groups: groups, contacts: allContacts)
    t.expect("returns raw email entry",  r.count == 1)
    t.expect("email is set",             r.first?.email == "new@person.com")
    t.expect("name is empty",            r.first?.name == "")
}

t.suite("resolveRecipients — no match") {
    let r = resolveRecipients("xyzzy", groups: groups, contacts: allContacts)
    t.expect("returns empty",  r.isEmpty)
}

t.suite("resolveRecipients — contact with no email skipped") {
    let r = resolveRecipients("Dana", groups: groups, contacts: allContacts)
    t.expect("no result for contact without email",  r.isEmpty)
}

t.suite("AddressEntry — formatted") {
    let withName = AddressEntry(name: "Alice Smith", email: "alice@example.com")
    let noName   = AddressEntry(name: "",             email: "raw@example.com")
    t.expect("Name <email> format",     withName.formatted == "Alice Smith <alice@example.com>")
    t.expect("email only when no name", noName.formatted   == "raw@example.com")
}

t.summary()
