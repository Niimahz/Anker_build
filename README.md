<div align="center">

# ANKER
### PC Game Preparation for Madeira · Browser · Downloads · Archive Manager for iOS

**Prepare already-installed PC game folders for use with Madeira on iOS.**

[Features](#features) · [Installation](#installation) · [Privacy](PRIVACY.md) · [Terms](TERMS.md) · [License](LICENSE)

</div>

---

## Overview

Anker is an independent iOS utility designed to prepare **already-installed PC games** for manual import into **Madeira** on iOS. It helps transfer, extract, inspect, and organize existing Windows game folders into a format and folder structure suitable for importing into Madeira. Anker also includes a general-purpose WebKit browser and download manager.

**Important:** Anker prepares game files; it does not convert Windows executables into native iOS apps, run PC games itself, or guarantee that a game will work in Madeira. Actual compatibility depends on Madeira and the game.

**Anker does not host, supply, recommend, or distribute third-party games or copyrighted downloads.** Users choose their own websites and are responsible for the content they access.

## Features

- Prepare and organize existing installed PC game folders for manual use in Madeira.
- Inspect Windows executables and export the prepared folder to another app.

| Feature | Description |
| --- | --- |
| 🌐 Web browser | Navigate to user-entered HTTP/HTTPS websites using WebKit |
| ⬇️ Downloads | Direct downloads and a managed download queue |
| ⏯️ Controls | Progress information and pause/resume where supported |
| 📦 Archives | ZIP, RAR, 7z and selected TAR/GZIP formats |
| 🗂️ Local library | Inspect, share, and delete extracted folders |
| 🔎 File inspection | Identify Windows executables and inspect BAT/CMD scripts without running them |
| 🛡️ Ad blocking | Optional built-in content filtering |

## Installation

This repository contains the iOS source and a GitHub Actions workflow for building an **unsigned IPA**.

1. Open [GitHub Actions](https://github.com/Niimahz/Anker_build/actions).
2. Select the IPA build workflow and run it (or open a successful run).
3. Download the IPA artifact, if the build succeeds.
4. Sign and install the IPA using an installation method available to you.

**Important:** An unsigned IPA is not an App Store release. Build success, App Store approval, and on-device behavior are separate checks.

## How to use

1. Open **Browse**, enter a website address, and navigate normally.
2. Manage download activity in **Files / Downloads**.
3. Import an archive from Files or use a completed download.
4. Extract to **My Games** (the existing library name) and share or delete the extracted folder.

The app does **not** execute Windows software. Extraction support depends on archive type, encryption, available storage, and library capabilities. Browser pause/resume and percentage reporting depend on WebKit and the remote server.

## Privacy and legal

- [Privacy Policy](PRIVACY.md)
- [Terms of Use](TERMS.md)
- [Copyright and Licensing](LICENSE)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

**Project owner / rights contact:** [Niimahz](https://github.com/Niimahz). This GitHub username is used as the project attribution; a verified legal name and business contact should be added before commercial distribution.

## Development

- SwiftUI and WKWebView
- XcodeGen configuration: `project.yml`
- iOS deployment target: 16.0
- Dependencies: ZIPFoundation, libarchive-swift, zstd.swift

### Release checklist

- [ ] Confirm legal publisher name and support email
- [ ] Verify licenses and bundle all required third-party notices
- [ ] Test signed builds on supported iPhones
- [ ] Verify privacy claims against actual app behavior and dependencies
- [ ] Add screenshots, support contact, and versioned release notes
- [ ] Review App Store policies and applicable copyright laws

---

<sub>© 2026 Niimahz. Original Anker source and branding are subject to the repository license. Third-party software retains its own licenses.</sub>
