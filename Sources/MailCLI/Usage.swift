// Usage.swift
//
// Print usage and exit.

import Foundation
import MailLib

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
