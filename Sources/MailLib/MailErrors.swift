// MailErrors.swift
//
// Domain error types for mail-cli.

import Foundation

public enum MailError: Error, LocalizedError {
    case noToken
    case noConfig
    case noMatchingIdentity(String)
    case sendFailed(String)
    case notFound(String)
    case jmapError(String)

    public var errorDescription: String? {
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
