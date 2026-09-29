# Contributing

Thanks for your interest in ClassBuddy! Issues and pull requests are welcome.

## Ground rules

- **Privacy first:** student data never leaves the device. No analytics, no cloud sync, no third-party SDKs.
- **Native only:** SwiftUI + Apple frameworks, no external dependencies.
- **German UI:** the app is written for German teachers; UI strings are German, code comments too.
- **Never commit real student data** – not in code, tests, screenshots or issues.

## Development

- Xcode 26 or newer, iPadOS 26 deployment target
- Open `ClassBuddy.xcodeproj`, select your team under *Signing & Capabilities*, run on an iPad
- Icons: drop Iconoir-style SVGs into `Icons/` and run `scripts/sync-icons.sh`
  (imports them into the asset catalog as template images, use them via `Image(.name)`)

## Pull requests

- One topic per PR, describe *why* in the description
- Keep the privacy mode working for new views (`.sensitive()`, `.sensitiveBlur()`)
- If you change the data model, update the Excel export/import (`Features/Backup/Backup.swift`)
