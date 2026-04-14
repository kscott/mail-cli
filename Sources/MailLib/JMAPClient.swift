// JMAPClient.swift
//
// Handle JMAP HTTP requests and responses.

import Foundation

// MARK: - Value types

public struct JMAPSession {
    public let apiUrl:    String
    public let uploadUrl: String
    public let accountId: String
}

public struct JMAPBlob {
    public let blobId: String
    public let type:   String
    public let name:   String
    public let size:   Int
}

// MARK: - URLSession delegate

/// Preserves the Authorization header across HTTP redirects.
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

// MARK: - MIME type helper

private func mimeType(for path: String) -> String {
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

// MARK: - JMAPClient

/// A JMAP client bound to a single authenticated session.
public struct JMAPClient {
    public let token:   String
    public let session: JMAPSession

    /// Authenticate with Fastmail and return a ready-to-use client.
    public static func connect(token: String) async throws -> JMAPClient {
        var req = URLRequest(url: URL(string: "https://api.fastmail.com/.well-known/jmap")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let delegate    = AuthRedirectDelegate(token: token)
        let urlSession  = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (data, _)   = try await urlSession.data(for: req)
        guard let json         = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apiUrl       = json["apiUrl"]        as? String,
              let uploadUrl    = json["uploadUrl"]     as? String,
              let primaryAccts = json["primaryAccounts"] as? [String: String],
              let accountId    = primaryAccts["urn:ietf:params:jmap:mail"] else {
            throw MailError.jmapError("Invalid JMAP session response")
        }
        let s = JMAPSession(apiUrl: apiUrl, uploadUrl: uploadUrl, accountId: accountId)
        return JMAPClient(token: token, session: s)
    }

    /// Send a JMAP method call batch and return the raw response array.
    public func post(
        using caps: [String] = ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
        methodCalls: [[Any]]
    ) async throws -> [[Any]] {
        let body: [String: Any] = ["using": caps, "methodCalls": methodCalls]
        var req = URLRequest(url: URL(string: session.apiUrl)!)
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

    /// Extract a named method result from a response batch, or throw on error.
    public func methodResult(_ name: String, from responses: [[Any]]) throws -> [String: Any] {
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

    /// Upload a file attachment and return its blob descriptor.
    public func uploadAttachment(path: String) async throws -> JMAPBlob {
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

        let delegate      = AuthRedirectDelegate(token: token)
        let uploadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (respData, _) = try await uploadSession.data(for: req)
        guard let json   = try JSONSerialization.jsonObject(with: respData) as? [String: Any],
              let blobId = json["blobId"] as? String else {
            throw MailError.jmapError("Upload failed for \(path)")
        }
        return JMAPBlob(blobId: blobId, type: mime, name: url.lastPathComponent, size: data.count)
    }

    /// Resolve a mailbox ID by its JMAP role (e.g. "drafts", "sent").
    public func findMailboxId(role: String) async throws -> String? {
        let responses = try await post(methodCalls: [
            ["Mailbox/get", ["accountId": session.accountId, "ids": NSNull()] as [String: Any], "a"]
        ])
        let result    = try methodResult("Mailbox/get", from: responses)
        let mailboxes = result["list"] as? [[String: Any]] ?? []
        return mailboxes.first(where: {
            ($0["role"] as? String)?.lowercased() == role.lowercased()
        })?["id"] as? String
    }
}
