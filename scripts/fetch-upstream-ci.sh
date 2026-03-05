#!/bin/bash
#
# Fetch CI test artifacts from the upstream monorepo main branch and
# overlay them onto the current downstream monorepo checkout for
# local testing.
#
# Usage:
#   ./scripts/fetch-upstream-ci.sh <upstream-repo-url>
#
# Run from the root of a downstream monorepo checkout (any branch).
# Fetches test/, hack/, scripts/, ptp-tools/ from upstream main and
# adjusts Go module paths so the test suite compiles against the
# local checkout.
#
# Examples:
#   ./scripts/fetch-upstream-ci.sh https://github.com/edcdavid-org/ptp-operator-upstream-monorepo.git
#   ./scripts/fetch-upstream-ci.sh git@github.com:edcdavid-org/ptp-operator-upstream-monorepo.git
#
# Environment variables:
#   MAIN_BRANCH  - upstream branch to fetch from (default: main)
#
set -euo pipefail

UPSTREAM_URL="${1:?Usage: $0 <upstream-repo-url>}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"
SOURCE_MODULE="github.com/k8snetworkplumbingwg/ptp-operator"

if [ ! -f go.mod ]; then
    echo "Error: go.mod not found. Run this script from the root of a ptp-operator checkout."
    exit 1
fi

TARGET_MODULE=$(grep "^module " go.mod | awk '{print $2}')

BASE_DIR=$(mktemp -d)
trap "rm -rf '$BASE_DIR'" EXIT

echo "============================================"
echo "  Fetch upstream CI artifacts"
echo "============================================"
echo "  Upstream:  $UPSTREAM_URL"
echo "  Branch:    $MAIN_BRANCH"
echo "  Target:    $(pwd)"
echo "  Module:    $TARGET_MODULE"
echo "============================================"

echo ""
echo ">>> Sparse-checkout upstream ($MAIN_BRANCH)..."
git clone --branch "$MAIN_BRANCH" --single-branch --depth 1 --no-checkout \
    "$UPSTREAM_URL" "$BASE_DIR" 2>&1 | tail -1
cd "$BASE_DIR"
git sparse-checkout init --cone
git sparse-checkout set ptp-tools scripts hack test
git checkout 2>/dev/null
cd - >/dev/null

echo ""
echo ">>> Copying artifacts..."

mkdir -p scripts
cp -rn "$BASE_DIR/scripts/"* scripts/ 2>/dev/null || true
echo "  scripts/  (merged, existing files preserved)"

mkdir -p hack
cp -f "$BASE_DIR/hack/"* hack/ 2>/dev/null || true
echo "  hack/     (overwritten)"

if [ ! -d ptp-tools ]; then
    cp -r "$BASE_DIR/ptp-tools" ptp-tools
    echo "  ptp-tools/ (created)"
else
    echo "  ptp-tools/ (already exists, skipped)"
fi

rm -rf test
cp -r "$BASE_DIR/test" test
echo "  test/     (replaced from upstream)"

if [ "$TARGET_MODULE" != "$SOURCE_MODULE" ]; then
    echo ""
    echo ">>> Adjusting module paths ($SOURCE_MODULE -> $TARGET_MODULE)..."

    # test/go.mod: replace module references
    perl -i -pe "s|\Q$SOURCE_MODULE\E|$TARGET_MODULE|g" test/go.mod

    # go.sum will be wrong after module path change; go mod tidy regenerates it
    rm -f test/go.sum

    # Go source files in test/
    find test -name "*.go" -exec perl -i -pe "s|\Q$SOURCE_MODULE\E|$TARGET_MODULE|g" {} \;

    echo "  Updated test/go.mod and $(find test -name '*.go' | wc -l | tr -d ' ') Go files"
else
    echo ""
    echo ">>> Module paths match, no adjustments needed."
fi

echo ""
echo "============================================"
echo "  Done. You can now run tests locally with:"
echo "    cd test && go mod tidy && cd .."
echo "    ginkgo -v test/conformance/serial"
echo "============================================"
