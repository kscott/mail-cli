// main.swift
//
// Entry point for mail-bin executable.
// Argument parsing and dispatch only — all logic lives in MailLib or MailCLI helpers.

import Foundation
import MailLib
import GetClearKit

let versionString = "\(builtVersion) (Get Clear \(suiteVersion))"
let args          = Array(CommandLine.arguments.dropFirst())

let dispatch = parseArgs(args)
if case .version = dispatch { print(versionString); exit(0) }
guard case .command(let cmd, let args) = dispatch else { usage() }

let semaphore = DispatchSemaphore(value: 0)

Task {
    do {
        switch cmd {
        case "what":  handleWhat(args: args)
        case "open":  try handleOpen()
        case "setup": try await handleSetup(args: args)
        case "send":  try await handleSend(args: args)
        case "find":  try await handleFind(args: args)
        default:      usage()
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
