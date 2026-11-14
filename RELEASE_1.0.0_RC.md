# Anker 1.0.0 — release candidate

**Status: RELEASE CANDIDATE / NOT APPROVED FOR PUBLIC DISTRIBUTION**

Version: 1.0.0 (build 1). iOS 16+. Bundle ID: `com.ankergamebridge.app`.

## What's included

- iOS WebKit browser, managed downloads and archive extraction.
- Windows executable architecture and BAT/CMD inspection (scripts are not executed).
- Steam Windows requirements lookup and conservative cross-check with local game files.
- Optional Madeira library settings preview and backup-before-write workflow.
- Madeira run-log diagnostics (keyword heuristics, not a benchmark).
- Per-game, per-scene FPS history and profile ranking from manually entered measurements. At least two successful comparable runs are required for ranking. Best-profile values are proposed for user review, not applied silently.

## Important limitations

Anker does not execute Windows games. Steam requirements do not establish Madeira compatibility. FPS is not collected automatically. Madeira JSON schema and every field type must be tested against a real installed Madeira version before trusting write operations. No game compatibility or performance guarantee is made.

## Private beta smoke test (must pass on an actual iPhone)

- [ ] Install a signed IPA with SideStore/other authorized signing method; verify cold start and re-launch.
- [ ] Test browsing, redirects, download queue, pause/resume, background download and cancellation.
- [ ] Extract representative ZIP, RAR5, 7z, multipart and damaged archives; check disk-space errors and path traversal protections.
- [ ] Import a game folder; inspect EXE architecture and BAT/CMD without executing commands.
- [ ] Check Steam matching with multiple editions and unavailable/offline responses.
- [ ] Import a **copy** of a real Madeira library; confirm unique matching, backup creation and that only explicitly selected keys change. Compare controller and logging values before/after.
- [ ] Verify Madeira still opens and loads the game after changing a copy of its library.
- [ ] Import actual Madeira logs; test success, error, UTF-8/UTF-16 and oversized logs.
- [ ] Record 2+ comparable successful runs for two profiles; confirm ranking and crash ordering; confirm manual apply and backup.
- [ ] Verify VoiceOver, Dynamic Type, landscape/portrait behavior, storage cleanup and low-disk-space handling.
- [ ] Validate privacy disclosures against actual traffic, dependencies and website interactions.

## Public distribution blockers

- [ ] Confirm legal publisher identity, support email, public privacy contact and support URL.
- [ ] Bundle exact license/copyright notices for resolved versions of ZIPFoundation, libarchive, zstd.swift and transitive dependencies.
- [ ] Complete security review of archive extraction, file paths, downloaded content and user-provided URLs.
- [ ] Confirm Madeira library schema/field values against the targeted Madeira release and test restoration from backups.
- [ ] Pin dependencies to reviewed immutable versions; `zstd.swift` currently follows `master`.
- [ ] Verify reproducible release build, archive/IPA integrity, correct version/build and signing entitlements.
- [ ] Prepare store screenshots, descriptions, age rating, export compliance, privacy disclosures and platform review if submitting to App Store.
- [ ] Obtain distribution signing credentials and choose a release channel (TestFlight/App Store vs independently signed IPA).
- [ ] Run full device regression tests and resolve Swift concurrency warnings before Swift 6 migration.

## Installation

The existing GitHub Actions workflow creates an **unsigned IPA** when successful. Download it from the successful workflow run's Artifacts, then sign it with a method you are authorized to use. Do not treat an unsigned IPA as an App Store-ready binary.

## Release decision

**No public release until the blockers are completed.** A successful CI compile confirms compilation only, not functional, security, licensing or App Store readiness.
