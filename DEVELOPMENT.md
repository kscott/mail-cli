# Development conventions

Patterns and decisions established for this project. Follow these when adding or changing anything.

## Architecture: what goes where

The project has two targets — keep them strictly separated.

**`MailLib`** — pure Swift, no framework dependencies
- `ArgumentParser.swift` — parse `send` args into `ComposedMessage`
- `RecipientResolver.swift` — resolve recipient string to `[AddressEntry]` using contacts + groups
- Anything that can be expressed without network, filesystem, or framework access
- If it doesn't need JMAP, Keychain, or Contacts, it goes here

**`MailCLI/main.swift`** — frameworks and network only
- Argument dispatch and command implementations
- Keychain (Security framework): store/load JMAP token
- Config file: read/write `~/.config/mail-cli/config.toml`
- JMAP API calls via `URLSession`
- CNContactStore for recipient resolution (converts contacts to `MailContact` for MailLib)

The rule: if you find yourself wanting to test something that lives in `main.swift`, that's a sign it should be moved to `MailLib`.

## Interface design: no flags

The tool uses positional arguments and natural language keywords — not flags.

**Correct:**
```
mail send alice subject Hello body Hi there
mail send "Board Members" cc carol subject Meeting attach ~/notes.pdf body See attached
```

**Avoid:**
```
mail send --to alice --subject Hello --body "Hi there"   # don't do this
```

The one exception is `--draft` — it's a mode switch with no natural keyword equivalent.

## Argument parsing conventions

- **`to`** = all tokens before the first keyword (no quoting needed for multi-word names)
- **`body`** must be last — captures everything after it to end of string
- **`subject`** captures tokens until the next keyword
- **`cc`** and **`attach`** are repeatable — each occurrence adds one entry
- **`from`** = single token (email address or identity alias)
- **`body`** expansion: if value is an existing file path, caller reads and substitutes content

## JMAP conventions

- Two-call send: `Email/set` (create) → `EmailSubmission/set` (submit); cleaner error handling than batched result references
- Always fetch the Drafts mailbox ID dynamically — never hardcode
- Use `onSuccessUpdateEmail` to clear `$draft` keyword on successful submission
- Session fetched fresh on each command (fast; session endpoint is cached by Fastmail CDN)
- `uploadUrl` template: replace `{accountId}` with session accountId before uploading

## Recipient resolution order

1. Exact group name (case-insensitive) → all members
2. Fuzzy name match: exact > prefix > contains
3. Email fragment match (contacts)
4. Raw email address (contains @)
5. No match → empty (caller decides how to handle)

## Testing

- All test-worthy logic lives in `MailLib` so it can be tested without credentials or network
- Tests live in `Tests/MailLibTests/main.swift` — custom runner, no XCTest or Xcode required
- Run with `./mail test`
- New parsing behaviour → new test suite. Cover: typical inputs, edge cases, nil/empty inputs
- Test descriptions should read as plain English sentences

## Output conventions

| Command | Output |
|---------|--------|
| `setup` | Summary of identities found, default sender |
| `send` | `Sent to Name <email>; cc Name <email> — Subject` |
| `send --draft` | `Saved draft to Name <email> — Subject` |
| `list` | Index, date, from (24 chars), subject — one per line |
| `search` | Same as list |
| `show` | From/To/Cc/Date/Subject header block + blank line + body |

Errors go to stderr via `fail()`, which exits non-zero. No silent failures.

## Adding a new command

1. Add the case to the `switch cmd` block in `main.swift`
2. Add it to `usage()`
3. Add it to the command table in `README.md` and `CLAUDE.md`
4. If the command introduces new parsing logic, add it to `MailLib` with tests
