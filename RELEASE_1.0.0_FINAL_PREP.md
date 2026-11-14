# Anker 1.0.0 — Final release preparation

**Build candidate:** GitHub Actions [run 43627856525](https://github.com/Niimahz/Anker_build/actions/runs/43627856525), commit `94b8538`. This is a **successfully compiled unsigned IPA**, not a signed or fully approved public release. Later documentation-only commits do not change that binary.

## Release description

Anker is a free, MIT-licensed iOS file preparation utility for browsing, downloading, extracting and organizing locally supplied PC game files. It provides an embedded WebKit browser, concurrent download management, ZIP/RAR/7z extraction, game-folder inspection, optional local cover artwork, and export to other apps. It does not execute Windows games, distribute games or guarantee Madeira compatibility.

### Highlights
- Refined Browse, Files and Games interface with consistent indigo styling.
- Download Center with direct URL entry, concurrent downloads and available progress controls.
- Local archive import and extraction, game folder inspection and sharing.
- Optional Buy Me a Coffee link in Files only: https://buymeacoffee.com/Niimahz
- Open-source original Anker code under MIT; third-party components have separate terms.

## Public binary release gate — do not mark complete without evidence

- [x] Latest UI candidate compiled and unsigned IPA uploaded in run 43627856525.
- [x] Original source license is MIT.
- [x] Reference copies of ZIPFoundation and libarchive-swift upstream license texts added under `LICENSES/`.
- [ ] Resolve and record **exact** dependency versions/commits, including zstd.swift and bundled native libraries; pin mutable branches.
- [ ] Verify and distribute **all** applicable third-party license/copyright texts, including libarchive's bundled C notices and zstd transitive code.
- [ ] Complete on-device regression testing for browser, concurrent download, large ZIP/RAR5/7z extraction, disk-space failures, import/export, backups and destructive actions.
- [ ] Complete security and privacy review of downloads, untrusted archives, URLs and network traffic.
- [ ] Confirm legal publisher identity and public support/privacy email.
- [ ] Select a distribution channel and prepare a correctly signed release binary. GitHub Actions currently produces **unsigned** IPA.
- [ ] Publish versioned release notes and checksum of the **final** signed or intentionally unsigned artifact; verify the downloaded artifact.

## Distribution note

Do not rename the existing CI artifact to an approved final release or promise App Store compatibility. For private testing, the existing unsigned IPA can be installed using a suitable authorized signing/container method. Public binary distribution should wait for the unchecked items above.

## Suggested GitHub release title (after gates pass)

`Anker v1.0.0 — Initial Public Release`

## Suggested release notes

Anker 1.0.0 introduces an iOS browser, multi-download file manager, on-device archive extraction and a prepared game library with local artwork and export. Anker is free and open source. Support is optional via Buy Me a Coffee in Files. Windows game execution is handled by third-party tools, not Anker. Users must supply files they are authorized to use.
