# Anker v1.0.0-beta.1 — Public Beta (Release Candidate)

**FREE · OPEN SOURCE · UNSIGNED IPA · EXPERIMENTAL**

Anker is an iOS WebKit browser and file preparation utility with downloads, archive extraction and game-folder organization. It does not execute Windows games or provide game content. Original source is MIT-licensed; third-party dependencies have their own terms.

## Known limitations and security warning

This beta has **known, unresolved security review findings**: archive extraction does not enforce a verified maximum expansion size, entry count or disk-space budget, and path/symlink containment has not been independently demonstrated across every supported archive format. A malicious archive may exhaust device storage or cause unintended filesystem effects. Do **not** extract untrusted archives, use the app with sensitive files, or rely on it for security-critical work. Back up important data. The project has not undergone a full penetration test or independent binary supply-chain review.

## Binary license status

The project includes upstream notices for ZIPFoundation, libarchive-swift, libarchive and zstd.swift. **The exact native XCFramework binaries and their complete redistribution notice obligations have not yet been verified.** Public binary redistribution is **not approved** until this audit is complete; beta labeling does not waive third-party license obligations.

## Installation

The existing `Anker-v1.0.0-unsigned.ipa` is unsigned and requires a compatible installation/signing workflow. It is not available through the App Store. `SHA256SUMS.txt` is supplied for integrity checking.

## Feedback

Report reproducible issues through GitHub Issues: https://github.com/Niimahz/Anker_build/issues. Do not post private documents, authentication tokens or sensitive URLs in public issues. For security reports, avoid publishing working exploit details publicly.

## No warranty

This experimental software is provided without warranty to the extent permitted by law, as described in the MIT license. Beta/pre-release status and this notice do **not** waive non-excludable legal rights or eliminate publisher responsibility.

**This document is a beta release-notes draft, not permission to publish an unreviewed binary.**
