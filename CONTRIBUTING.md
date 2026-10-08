# Contributing

Thanks for your interest in ClassBuddy! Issues and pull requests are welcome.

## Ground rules

- **Privacy first:** student data never leaves the device. No analytics, no cloud sync, no third-party SDKs.
- **Native only:** SwiftUI + Apple frameworks, no external dependencies.
- **German UI:** the app is written for German teachers; UI strings are German, code comments too.
- **Never commit real student data** – not in code, tests, screenshots or issues.

## Development

- Xcode 26 or newer, iOS/iPadOS 17.7 deployment target
- Newer APIs (iOS 18 / 26) only behind availability checks: use the wrappers in `Shared/OSCompatibility.swift`
  and `Shared/Glass.swift` (e.g. `.appGlassEffect`, `.appNavigationSubtitle`, `AppToolbarSpacer`), so iOS 26
  keeps the system look and older versions get a fallback
- Open `ClassBuddy.xcodeproj`, select your team under *Signing & Capabilities*, run on an iPad or iPhone
- Icons: drop Iconoir-style SVGs into `Icons/` and run `scripts/sync-icons.sh`
  (imports them into the asset catalog as template images, use them via `Image(.name)`)

## Git hooks, lint & tests

Run once after cloning:

```bash
scripts/setup-hooks.sh
```

- **pre-commit:** SwiftLint must report 0 errors (`.swiftlint.yml`) and all unit tests must pass
  (`scripts/test.sh`, runs headless on an iPad simulator; `SIMULATOR_UDID=<udid>` picks another one, e.g. an iPhone). Only runs when Swift code or the project changed.
- **commit-msg:** no `Co-authored-by` trailers, no emoji, no em dashes in commit messages.
- Requirements: `brew install swiftlint`, an iOS simulator runtime in Xcode.
- **Security scan:** `scripts/semgrep.sh` runs the same Semgrep rules as CI (`brew install semgrep`).
  Intentional exceptions need a `nosemgrep: <rule>` comment with a justification.

## Pull requests

- One topic per PR, describe *why* in the description
- Keep the privacy mode working for new views (`.sensitive()`, `.sensitiveBlur()`)
- If you change the data model, update the Excel export/import (`Features/Backup/Backup.swift`)
