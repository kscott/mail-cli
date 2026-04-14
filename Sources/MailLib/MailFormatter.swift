// MailFormatter.swift
//
// Format email data for display output.

import Foundation

private let isoFractionalFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let isoBasicFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private func parseISO8601(_ iso: String) -> Date? {
    isoFractionalFormatter.date(from: iso) ?? isoBasicFormatter.date(from: iso)
}

public func formatDate(_ iso: String) -> String {
    guard let date = parseISO8601(iso) else { return iso }

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

public func formatDateLong(_ iso: String) -> String {
    guard let date = parseISO8601(iso) else { return iso }
    let df = DateFormatter(); df.dateStyle = .full; df.timeStyle = .short
    return df.string(from: date)
}

public func formatAddress(_ addr: [String: Any]) -> String {
    let name  = addr["name"]  as? String ?? ""
    let email = addr["email"] as? String ?? ""
    return name.isEmpty ? email : "\(name) <\(email)>"
}

public func formatAddresses(_ addrs: [[String: Any]]) -> String {
    addrs.map(formatAddress).joined(separator: ", ")
}

public extension String {
    func leftPad(_ length: Int) -> String {
        if count >= length { return self }
        return String(repeating: " ", count: length - count) + self
    }
}
