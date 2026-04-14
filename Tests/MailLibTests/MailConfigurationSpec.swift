// MailConfigurationSpec.swift
//
// Tests for MailLib MailConfiguration — config parsing and model types.

import Quick
import Nimble
import Foundation
import MailLib

final class MailConfigurationSpec: QuickSpec {
    override class func spec() {
        describe("parseConfig") {
            context("a well-formed config") {
                let toml = """
                    default_from = "ken@optikos.net"

                    [identities]
                    id1 = "ken@optikos.net|Ken Scott"
                    id2 = "k@fastmail.com|Kenneth"
                    """

                it("parses the default_from field") {
                    expect(parseConfig(toml).defaultFrom) == "ken@optikos.net"
                }

                it("parses identity email") {
                    expect(parseConfig(toml).identities.first?.email) == "ken@optikos.net"
                }

                it("parses identity name") {
                    expect(parseConfig(toml).identities.first?.name) == "Ken Scott"
                }

                it("parses identity id") {
                    expect(parseConfig(toml).identities.first?.id) == "id1"
                }

                it("parses multiple identities") {
                    expect(parseConfig(toml).identities.count) == 2
                }
            }

            context("identity with a pipe in the name") {
                let toml = """
                    default_from = "a@b.com"

                    [identities]
                    id1 = "a@b.com|First|Last"
                    """

                it("joins pipe-separated name parts") {
                    expect(parseConfig(toml).identities.first?.name) == "First|Last"
                }
            }

            context("empty config") {
                it("returns empty defaultFrom") {
                    expect(parseConfig("").defaultFrom) == ""
                }

                it("returns no identities") {
                    expect(parseConfig("").identities).to(beEmpty())
                }
            }

            context("lines with comments and blank lines") {
                let toml = """
                    # this is a comment
                    default_from = "x@y.com"

                    [identities]
                    # another comment
                    id1 = "x@y.com|X Y"
                    """

                it("ignores comment lines") {
                    expect(parseConfig(toml).defaultFrom) == "x@y.com"
                }

                it("still parses identity") {
                    expect(parseConfig(toml).identities.count) == 1
                }
            }

            context("identity line with too few parts") {
                let toml = """
                    default_from = "a@b.com"

                    [identities]
                    id1 = "a@b.com"
                    """

                it("skips malformed identity entries") {
                    expect(parseConfig(toml).identities).to(beEmpty())
                }
            }
        }

        describe("MailConfig.identity(for:)") {
            let config = parseConfig("""
                default_from = "ken@optikos.net"

                [identities]
                id1 = "ken@optikos.net|Ken Scott"
                id2 = "k@fastmail.com|Kenneth"
                """)

            it("finds identity by exact email") {
                expect(config.identity(for: "ken@optikos.net")?.id) == "id1"
            }

            it("finds identity case-insensitively") {
                expect(config.identity(for: "KEN@OPTIKOS.NET")?.id) == "id1"
            }

            it("returns nil for unknown email") {
                expect(config.identity(for: "nobody@nowhere.com")).to(beNil())
            }
        }

        describe("MailConfig.defaultIdentity") {
            it("returns the identity matching defaultFrom") {
                let config = parseConfig("""
                    default_from = "ken@optikos.net"

                    [identities]
                    id1 = "ken@optikos.net|Ken Scott"
                    """)
                expect(config.defaultIdentity?.id) == "id1"
            }

            it("returns nil when defaultFrom has no matching identity") {
                let config = parseConfig("""
                    default_from = "nobody@example.com"

                    [identities]
                    id1 = "ken@optikos.net|Ken Scott"
                    """)
                expect(config.defaultIdentity).to(beNil())
            }
        }
    }
}
