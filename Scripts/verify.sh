#!/usr/bin/env bash
set -euo pipefail

AKUO_PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

cd "$AKUO_PROJECT_ROOT"
"$AKUO_PROJECT_ROOT/Tests/PackagingTests/VerifyContractTests.sh"
"$AKUO_PROJECT_ROOT/Tests/PackagingTests/CandidateVersionContractTests.sh"
"$AKUO_PROJECT_ROOT/Tests/PackagingTests/BuildManifestContractTests.sh"
"$AKUO_PROJECT_ROOT/Tests/PackagingTests/LocalSigningContractTests.sh"
swift test
"$AKUO_PROJECT_ROOT/Scripts/build-app.sh" release
"$AKUO_PROJECT_ROOT/Scripts/verify-candidate-version.sh" dist/Akuo.app
"$AKUO_PROJECT_ROOT/Scripts/verify-build-manifest.sh" \
    dist/Akuo.app dist/Akuo.build-manifest.json
