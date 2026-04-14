// OpenCommand.swift
//
// Opens Fastmail in the default browser.

import Foundation

func handleOpen() throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["https://app.fastmail.com"]
    try p.run()
}
