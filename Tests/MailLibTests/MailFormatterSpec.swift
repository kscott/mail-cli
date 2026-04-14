// MailFormatterSpec.swift
//
// Tests for MailLib MailFormatter — email date and address formatting.

import Quick
import Nimble
import Foundation
import MailLib

final class MailFormatterSpec: QuickSpec {
    override class func spec() {
        describe("formatAddress") {
            it("formats name and email together") {
                let addr: [String: Any] = ["name": "Ken Scott", "email": "ken@optikos.net"]
                expect(formatAddress(addr)) == "Ken Scott <ken@optikos.net>"
            }

            it("returns just the email when name is empty") {
                let addr: [String: Any] = ["name": "", "email": "ken@optikos.net"]
                expect(formatAddress(addr)) == "ken@optikos.net"
            }

            it("returns just the email when name is missing") {
                let addr: [String: Any] = ["email": "ken@optikos.net"]
                expect(formatAddress(addr)) == "ken@optikos.net"
            }
        }

        describe("formatAddresses") {
            it("joins multiple addresses with commas") {
                let addrs: [[String: Any]] = [
                    ["name": "Alice", "email": "alice@example.com"],
                    ["name": "Bob",   "email": "bob@example.com"],
                ]
                expect(formatAddresses(addrs)) == "Alice <alice@example.com>, Bob <bob@example.com>"
            }

            it("returns empty string for empty list") {
                expect(formatAddresses([])) == ""
            }
        }

        describe("leftPad") {
            it("pads a short string to the specified width") {
                expect("5".leftPad(3)) == "  5"
            }

            it("does not truncate a string that is already at width") {
                expect("123".leftPad(3)) == "123"
            }

            it("does not truncate a string that exceeds width") {
                expect("12345".leftPad(3)) == "12345"
            }
        }

        describe("formatDate") {
            context("a date with fractional seconds") {
                it("does not return the raw ISO string for a valid date") {
                    // We cannot assert the exact formatted value without freezing the clock,
                    // but we can confirm the formatter does not fall back to the raw input.
                    let iso = "2026-04-13T14:30:00.000Z"
                    expect(formatDate(iso)) != iso
                }
            }

            context("an unparseable string") {
                it("returns the raw string unchanged") {
                    expect(formatDate("not-a-date")) == "not-a-date"
                }
            }
        }

        describe("formatDateLong") {
            context("an unparseable string") {
                it("returns the raw string unchanged") {
                    expect(formatDateLong("not-a-date")) == "not-a-date"
                }
            }
        }
    }
}
