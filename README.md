# mail-cli

Fast CLI for Fastmail via JMAP. Send, find, and compose email directly from the terminal.

## Installation

```bash
git clone https://github.com/kscott/mail-cli ~/dev/mail-cli
~/dev/mail-cli/mail setup   # build, install binary, configure token
```

Get your JMAP token from Fastmail: Settings → Security → API tokens.

Requires macOS 14+.

## Commands

```
mail setup [token]                   # Store JMAP token, discover identities
mail send <to> [keywords...]         # Send an email
mail find <query>                  # Find messages for context before composing
mail open                            # Open Fastmail in browser
```

## send examples

```bash
# Basic send
mail send alice@example.com subject Hello body Hi there

# Multi-word recipient (no quoting needed)
mail send Alice Smith subject Lunch?

# Contact group → all members
mail send "Board Members" subject "Q1 Update" body See attached

# With cc, from override, attachment, draft
mail send alice cc bob from ken@optikos.net subject Contract attach ~/docs/contract.pdf body Please review
mail send alice subject Draft --draft
```

Keywords can appear in any order. `body` must be last — it captures to end of string.
`body` can be a file path — the content is read and used as the message body.

## Recipient resolution

1. Exact contact group name → all members with email
2. Fuzzy contact name or email fragment → primary email
3. Raw email address (contains @) → direct

## Build & test

```bash
./mail setup   # build release binary and install to ~/bin
./mail test    # build and run test suite (50 tests)
```

## Config

`~/.config/mail-cli/config.toml` — written by `mail setup`, stores default sender and identity IDs.
Token is stored in macOS Keychain (never on disk).

## Project structure

- `Sources/MailLib/ArgumentParser.swift` — pure send-arg parsing
- `Sources/MailLib/RecipientResolver.swift` — recipient resolution logic
- `Sources/MailCLI/main.swift` — Keychain, JMAP, CNContactStore, command dispatch
- `Tests/MailLibTests/main.swift` — custom test runner (no Xcode/XCTest required)
- `mail` — bash wrapper script, symlinked into `~/bin`

## Key decisions

- **JMAP over SMTP** — Fastmail's JMAP API supports send, search, and read from a single bearer token
- **Token in Keychain** — never stored on disk; Security framework only
- **MailLib separated from MailCLI** — argument parsing and recipient resolution are fully testable without credentials
- **Two-call send** — `Email/set` create then `EmailSubmission/set` submit; cleaner than batched result references

## Known limitations

- HTML email: sends plain text only; HTML bodies are a planned improvement
- Reply-to: not yet supported
- Threading: `mail show` finds by text search, not thread ID
