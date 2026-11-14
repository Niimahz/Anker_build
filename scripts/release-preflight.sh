#!/usr/bin/env bash
# Release readiness preflight. Non-zero exit means the binary is NOT approved for public distribution.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
check() { if [[ -f "$1" ]]; then echo "PASS: $1"; else echo "FAIL: missing $1"; fail=1; fi; }
check LICENSE
check PRIVACY.md
check TERMS.md
check THIRD_PARTY_NOTICES.md
check LICENSES/VERIFIED_UPSTREAM_REFERENCE.md
check LICENSES/ZSTD_SWIFT_CC0_1.0.txt
check RELEASE_1.0.0_FINAL_PREP.md
if grep -Eq '^[[:space:]]+branch:[[:space:]]+master' project.yml; then
  echo "BLOCKED: dependency follows mutable master branch (zstd.swift)."
  fail=1
fi
if [[ -z "${ANKER_RELEASE_SUPPORT_EMAIL:-}" ]]; then
  echo "BLOCKED: no confirmed public support/privacy email supplied (ANKER_RELEASE_SUPPORT_EMAIL)."
  fail=1
fi
if [[ "${ANKER_DEVICE_REGRESSION_PASSED:-}" != "yes" ]]; then
  echo "BLOCKED: real-device regression not attested (ANKER_DEVICE_REGRESSION_PASSED=yes)."
  fail=1
fi
if [[ "${ANKER_NATIVE_LICENSE_AUDIT_PASSED:-}" != "yes" ]]; then
  echo "BLOCKED: native XCFramework and transitive license audit not attested."
  fail=1
fi
if [[ "${ANKER_SECURITY_REVIEW_PASSED:-}" != "yes" ]]; then
  echo "BLOCKED: archive, URL and file-path security review not attested."
  fail=1
fi
if [[ "${ANKER_PRIVACY_REVIEW_PASSED:-}" != "yes" ]]; then
  echo "BLOCKED: final network/privacy review not attested."
  fail=1
fi
if [[ "${ANKER_RELEASE_BINARY_VERIFIED:-}" != "yes" ]]; then
  echo "BLOCKED: final IPA signing, integrity and version verification not attested."
  fail=1
fi
if (( fail != 0 )); then
  echo "Release preflight FAILED. Do not publish as approved production binary."
  exit 1
fi
echo "All declared preflight checks passed; review evidence before publication."
