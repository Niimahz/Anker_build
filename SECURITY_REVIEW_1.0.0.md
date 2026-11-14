# Anker v1.0.0 — Security and binary-license review (2026-11-14)

**Decision: NOT CLEARED FOR PUBLIC BINARY RELEASE.** This is a source-level review, not a penetration test or binary supply-chain attestation. The existing draft IPA predates any fixes in this report.

## Source-level findings

1. **HIGH — Untrusted archive extraction without explicit extraction quotas.** In `Sources/MainView.swift`, `prepare(_ url:)` invokes `FileManager.unzipItem`, `ZstandardZIP.extract`, or `ArchiveReader.extract` on user-supplied archives. The caller imposes no maximum extracted bytes, entry count, expansion ratio, time budget, or free-disk-space preflight. ZIP bombs and disk exhaustion are plausible. Progress reporting observes output size but does not enforce a limit. **Open**.
2. **HIGH — Extraction path/symlink containment not demonstrated.** The caller does not independently validate each archive entry path or reject links resolving outside the destination. Underlying library behavior may mitigate some formats, but that has not been established for all ZIP, ZIP+Zstd, RAR and 7z paths. **Open; requires format-specific adversarial tests and containment checks.**
3. **MEDIUM — Downloaded content is untrusted.** Direct download input accepts HTTP and HTTPS (`Sources/MainView.swift`, `download(_ string:)`). HTTP permits in-transit tampering. No downloaded-file checksum verification is required. Consider HTTPS-by-default and explicit warning for HTTP. **Open**.
4. **MEDIUM — Filesystem copy and deletion require adversarial checks.** `importItem` copies selected URLs into Downloads; `deleteExtractedArchive` checks the standardized parent and displays confirmation. Validate symlink behavior, nested folders, and races on a real device. **Partially mitigated; not cleared**.
5. **MEDIUM — Privacy/network behavior not independently captured.** Source inspection alone does not prove the absence of third-party traffic from WebKit or bundled libraries. **Open**.
6. **POSITIVE — Basic controls.** Direct-download URL schemes are restricted to HTTP(S); unsupported archive extensions are rejected; extraction failures remove the output folder; destructive original-archive deletion is user-confirmed.

## Binary license and supply-chain findings

- **ZIPFoundation**: upstream MIT notice is preserved in `LICENSES/VERIFIED_UPSTREAM_REFERENCE.md`. Exact resolved revision not independently checked against final IPA.
- **libarchive-swift**: wrapper BSD-2-Clause notice is preserved. Its upstream `Package.swift` uses a downloaded `CArchive.xcframework.zip`; contents, component versions, provenance and required notices are **unverified**.
- **libarchive**: upstream `COPYING` describes BSD-style core licensing with per-file exceptions (including UC Regents notices). A generic BSD notice is insufficient to certify an unknown compiled binary.
- **zstd.swift**: wrapper `LICENSE.md` is CC0 1.0 and copied to `LICENSES/ZSTD_SWIFT_CC0_1.0.txt`; its `Package.swift` includes a prebuilt `libzstd.xcframework`. Native libzstd binary identity and corresponding BSD notice remain **unverified**.
- **Reproducibility**: `project.yml` selects `zstd.swift` by mutable `master` branch. Resolve an immutable reviewed commit before public distribution.
- **Final IPA**: no independent inspection of packaged framework binaries, embedded license assets, signature, entitlements or checksum against source has been completed.

## Release gate

Do not publish the current draft as a security-reviewed production release. Required next work: enforce extraction quotas and path containment across all extractors, run malicious-archive tests, pin and audit dependency revisions, inventory XCFramework binaries and full license texts, verify actual release IPA, perform network/privacy review and rebuild. User-reported successful normal-use tests do not close these security findings.

## Remediation progress (commit c974443f; not yet CI-verified)

Added ZIPFoundation central-directory preflight for path traversal, symlinks/special entries, 50,000-entry and 4-GiB declared-size limits; added post-extraction symlink and 4-GiB/50,000-entry verification. **Limitations:** these checks do not enforce an extraction-time byte budget, cannot establish containment of the native RAR/7z extractor, and do not protect against archive entries with misleading size metadata. A clean rebuild, negative tests and review are required before declaring the fixes effective. Existing draft IPA does not contain these changes. Public release gate remains CLOSED.
