# Security Policy

ClassBuddy stores sensitive data about students on the device. Security issues are taken seriously.

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

**Please do not open a public issue.**

Report vulnerabilities privately via [GitHub Security Advisories](https://github.com/undeaDD/ClassBuddy/security/advisories/new).
You'll get a response as soon as possible; please allow time for a fix before any disclosure.

Helpful details:

- affected version and iPadOS version
- steps to reproduce / proof of concept
- impact (e.g. data visible despite app lock or privacy mode)

## Scope

In scope: bypassing the app lock (Face ID), data shown despite privacy mode, data leaving the device,
unsafe handling of imported files (Excel import, documents, images).

The app intentionally makes only these network requests: public holiday data (openholidaysapi.org, on demand),
weather for the school's town (open-meteo.com, only while the weather card is visible) and website favicons for
dashboard link cards. No student data is ever sent.