// RecipientResolverSpec.swift
//
// Tests for MailLib RecipientResolver — recipient resolution and address formatting.

import Quick
import Nimble
import Foundation
import MailLib

final class RecipientResolverSpec: QuickSpec {
    override class func spec() {
        let alice   = MailContact(name: "Alice Smith",   emails: ["alice@example.com", "alice@work.com"])
        let bob     = MailContact(name: "Bob Jones",     emails: ["bob@jones.org"])
        let charlie = MailContact(name: "Charlie Brown", emails: ["cbrown@peanuts.com"])
        let noEmail = MailContact(name: "Dana White",    emails: [])

        let contacts = [alice, bob, charlie, noEmail]

        let groups: [String: [AddressEntry]] = [
            "Board": [
                AddressEntry(name: "Alice Smith", email: "alice@example.com"),
                AddressEntry(name: "Bob Jones",   email: "bob@jones.org"),
            ],
        ]

        describe("resolveRecipients") {
            context("group name") {
                it("returns all members of a matching group") {
                    expect(resolveRecipients("Board", groups: groups, contacts: contacts).count) == 2
                }
                it("matches group name case-insensitively") {
                    expect(resolveRecipients("board", groups: groups, contacts: contacts).count) == 2
                }
                it("returns members in order") {
                    expect(resolveRecipients("Board", groups: groups, contacts: contacts).first?.name) == "Alice Smith"
                }
            }

            context("contact name") {
                it("finds a contact by exact name") {
                    expect(resolveRecipients("Alice Smith", groups: groups, contacts: contacts).count) == 1
                }
                it("uses the primary email for a named contact") {
                    expect(resolveRecipients("Alice Smith", groups: groups, contacts: contacts).first?.email) == "alice@example.com"
                }
                it("finds a contact by partial name") {
                    expect(resolveRecipients("alice", groups: groups, contacts: contacts).first?.name) == "Alice Smith"
                }
            }

            context("email fragment") {
                it("finds a contact by email domain") {
                    expect(resolveRecipients("jones.org", groups: groups, contacts: contacts).first?.name) == "Bob Jones"
                }
            }

            context("raw email address") {
                it("returns the address directly when it contains @") {
                    let r = resolveRecipients("new@person.com", groups: groups, contacts: contacts)
                    expect(r.first?.email) == "new@person.com"
                }
                it("leaves name empty for a raw address") {
                    expect(resolveRecipients("new@person.com", groups: groups, contacts: contacts).first?.name) == ""
                }
            }

            context("non-primary email") {
                it("preserves the exact address when a non-primary email is specified") {
                    let r = resolveRecipients("alice@work.com", groups: groups, contacts: contacts)
                    expect(r.first?.email) == "alice@work.com"
                }
                it("resolves the contact name from the non-primary email") {
                    let r = resolveRecipients("alice@work.com", groups: groups, contacts: contacts)
                    expect(r.first?.name) == "Alice Smith"
                }
            }

            context("no match") {
                it("returns empty for an unknown query") {
                    expect(resolveRecipients("xyzzy", groups: groups, contacts: contacts)).to(beEmpty())
                }
                it("returns empty for a contact with no email") {
                    expect(resolveRecipients("Dana", groups: groups, contacts: contacts)).to(beEmpty())
                }
            }
        }

        describe("buildRecipients") {
            context("to field") {
                it("preserves a non-primary email in the to field") {
                    let (to, _) = buildRecipients(to: "alice@work.com", cc: [], groups: groups, contacts: contacts)
                    expect(to.first?.email) == "alice@work.com"
                }
                it("resolves the contact name for the to field") {
                    let (to, _) = buildRecipients(to: "alice@work.com", cc: [], groups: groups, contacts: contacts)
                    expect(to.first?.name) == "Alice Smith"
                }
            }

            context("cc field") {
                it("preserves a non-primary email in cc") {
                    let (_, cc) = buildRecipients(to: "bob", cc: ["alice@work.com"], groups: groups, contacts: contacts)
                    expect(cc.first?.email) == "alice@work.com"
                }
                it("resolves multiple cc entries") {
                    let (_, cc) = buildRecipients(to: "bob", cc: ["alice@work.com", "cbrown@peanuts.com"],
                                                  groups: groups, contacts: contacts)
                    expect(cc.count) == 2
                }
            }

            context("resolution consistency") {
                it("cc resolves identically to a direct resolveRecipients call") {
                    let direct = resolveRecipients("alice@work.com", groups: groups, contacts: contacts)
                    let (_, cc) = buildRecipients(to: "bob", cc: ["alice@work.com"], groups: groups, contacts: contacts)
                    expect(cc) == direct
                }
            }
        }

        describe("AddressEntry") {
            context("formatted") {
                it("formats as 'Name <email>' when name is present") {
                    let entry = AddressEntry(name: "Alice Smith", email: "alice@example.com")
                    expect(entry.formatted) == "Alice Smith <alice@example.com>"
                }
                it("formats as email only when name is empty") {
                    let entry = AddressEntry(name: "", email: "raw@example.com")
                    expect(entry.formatted) == "raw@example.com"
                }
            }
        }
    }
}
