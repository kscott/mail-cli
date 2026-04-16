> **This repository has been archived.** This tool has been merged into [kscott/get-clear](https://github.com/kscott/get-clear). Issues, history, and active development have moved there.

---

# mail-cli

Send email from the terminal via Fastmail's JMAP API. Fire and forget.

Part of the [Get Clear](https://github.com/kscott/get-clear) suite.

## Setup

### Requirements

- macOS 14 (Sonoma) or later
- A Fastmail account with a JMAP API token
- Apple Silicon Mac (arm64) for the pre-built binary; Intel Macs must build from source

Get your JMAP token from Fastmail: Settings → Security → API tokens.

### Install

Install the full Get Clear suite via the PKG installer — download from the [latest release](https://github.com/kscott/get-clear/releases/latest) and run it.

This installs all five tools to `/usr/local/bin`. Make sure that's in your `$PATH`:

```bash
export PATH="/usr/local/bin:$PATH"   # add to ~/.zshrc
```

Then configure your token:

```bash
mail setup
```

### Build from source

```bash
xcode-select --install   # if not already installed
git clone https://github.com/kscott/mail-cli.git ~/dev/mail-cli
cd ~/dev/mail-cli
swift build -c release
cp .build/release/mail-bin /usr/local/bin/mail
mail setup
```

## Command reference

```
mail setup [token]                   # Store JMAP token, discover identities
mail send <to> [keywords...]         # Send an email
mail find <query>                    # Find messages for context before composing
mail open                            # Open Fastmail in browser
```

### send examples

```bash
# Basic send
mail send alice@example.com subject Hello body Hi there

# Multi-word recipient (no quoting needed)
mail send Alice Smith subject Lunch?

# Contact group → all members
mail send "Board Members" subject "Q1 Update" body See attached

# With cc, from override, attachment, draft mode
mail send alice cc bob from ken@optikos.net subject Contract attach ~/docs/contract.pdf body Please review
mail send alice subject Draft --draft
```

Keywords can appear in any order except `body` — it captures everything to end of string and must come last.

### Recipient resolution

1. Exact contact group name → all members with email
2. Fuzzy contact name or email fragment → primary email
3. Raw email address (contains @) → used directly

## Config

`~/.config/mail-cli/config.toml` — written by `mail setup`, stores default sender and identity IDs. Token is stored in macOS Keychain (never on disk).

## Known limitations

- Fastmail only — JMAP is not universally supported; Gmail users see #14
- Plain text only — HTML bodies are a planned improvement
- Reply-to not yet supported

## Project structure

```
mail-cli/
├── Package.swift
├── Sources/
│   ├── MailLib/                        # Pure Swift — no framework deps, fully testable
│   │   ├── ArgumentParser.swift        # Parses send args into ComposedMessage
│   │   └── RecipientResolver.swift     # Resolves recipient strings to AddressEntry values
│   └── MailCLI/
│       └── main.swift                  # CLI entry point (Keychain, JMAP, Contacts)
└── Tests/
    └── MailLibTests/                   # Quick + Nimble test suite
        ├── ArgumentParserSpec.swift
        └── RecipientResolverSpec.swift
```

## Tests

```bash
swift test
```
