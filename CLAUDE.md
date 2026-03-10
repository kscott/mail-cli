# mail-cli

Swift CLI for Fastmail via JMAP.

## Build & run

```bash
./mail setup   # build release binary, install to ~/bin, configure token
./mail test    # build and run test suite
```

## Project structure

- `Sources/MailLib/ArgumentParser.swift` — pure send-arg parsing → `ComposedMessage`
- `Sources/MailLib/RecipientResolver.swift` — recipient resolution: group → contacts → raw email
- `Sources/MailCLI/main.swift` — CLI entry point: Keychain, JMAP, CNContactStore, command dispatch
- `Tests/MailLibTests/main.swift` — custom test runner (no Xcode/XCTest required)
- `mail` — bash wrapper script, symlinked into `~/bin`

Config: `~/.config/mail-cli/config.toml`
Token:  macOS Keychain (service `mail-cli`, account `kscott@imap.cc`)

See [DEVELOPMENT.md](DEVELOPMENT.md) for coding conventions and patterns.

## Commands

```
mail setup [token]   # Store JMAP token, discover identities (safe to re-run)
mail send <to> [cc <cc>] [from <from>] [subject <subject>] [attach <file>] [body <text>] [--draft]
mail search <query>  # Search for context before composing
mail open            # Open Fastmail in browser
```

## send argument parsing

Keywords in any order; `body` must be last — it captures to end of string.
`<to>` = all tokens before the first keyword (no quoting needed for multi-word names).

```bash
mail send "Board Members" subject "Agenda" body See attached
mail send alice cc bob from ken@optikos.net subject Hi body Hello
mail send jane attach ~/Documents/contract.pdf body Please review --draft
```

`body` can be a file path — the content is read and used as the body text.

`cc` and `attach` are repeatable for multiple values.

## Recipient resolution

1. Exact contact group name → all members with email
2. Fuzzy contact name or email fragment → primary email
3. Raw email address (contains @) → direct

## Key decisions

- **JMAP over SMTP** — Fastmail's JMAP API supports full send, search, and list from a single token
- **Token in Keychain** — never stored on disk; `mail setup` stores it in macOS Keychain
- **MailLib separated from MailCLI** — argument parsing and recipient resolution are testable without credentials
- **Custom test runner** — works with CLT only, no full Xcode needed
- **Two-call JMAP send** — create email + submit as separate calls for clarity and error handling

## Config format (`~/.config/mail-cli/config.toml`)

```toml
default_from = "ken@optikos.net"

[identities]
# id = "email|display name"
abc123 = "ken@optikos.net|Ken Scott"
def456 = "kscott@imap.cc|Ken Scott"
```

Identity IDs come from Fastmail's `Identity/get` response and are required for `EmailSubmission/set`.
Run `mail setup` to refresh after adding new send-as addresses in Fastmail.

## Adding a new command

1. Add the case to the `switch cmd` block in `main.swift`
2. Add it to `usage()`
3. Add it to the command table in `README.md` and `CLAUDE.md`
4. If the command introduces new parsing logic, add it to `MailLib` with tests
