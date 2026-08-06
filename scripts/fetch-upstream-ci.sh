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
# Fetches test/, hack/, scripts/, ptp-tools/, api/ from upstream main,
# creates a _base/ directory for test module resolution, and adjusts
# Go module paths so the test suite compiles against the upstream API
# without modifying the local operator code.
#
# Examples:
#   ./scripts/fetch-upstream-ci.sh https://github.com/k8snetworkplumbingwg/ptp-operator.git
#   ./scripts/fetch-upstream-ci.sh git@github.com:k8snetworkplumbingwg/ptp-operator.git
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
# Full pkg/ is required so monorepo Dockerfiles can COPY pkg/linuxptp-daemon
# and pkg/cloud-event-proxy when building images locally / via netdevsim CI helpers.
git sparse-checkout set ptp-tools scripts hack test api pkg
git checkout 2>/dev/null
cd - >/dev/null

echo ""
echo ">>> Copying CI artifacts..."

mkdir -p scripts
cp -rf "$BASE_DIR/scripts/"* scripts/
echo "  scripts/  (replaced from upstream)"

mkdir -p hack
cp -rf "$BASE_DIR/hack/"* hack/
echo "  hack/     (replaced from upstream)"

rm -rf ptp-tools
cp -r "$BASE_DIR/ptp-tools" ptp-tools
echo "  ptp-tools/ (replaced from upstream)"

rm -rf test
cp -r "$BASE_DIR/test" test
echo "  test/     (replaced from upstream)"

echo ""
echo ">>> Creating _base/ for test module resolution..."

# _base/ holds the upstream go.mod and api/ so the test module can
# resolve operator API types without modifying the local checkout's
# api/ (which the operator image build depends on).
rm -rf _base
mkdir -p _base
cp "$BASE_DIR/go.mod" "$BASE_DIR/go.sum" _base/
cp -r "$BASE_DIR/api" _base/api
cp -r "$BASE_DIR/pkg" _base/pkg
echo "  _base/go.mod  (upstream module definition)"
echo "  _base/api/    (upstream API types)"
echo "  _base/pkg/    (upstream client packages)"

# Point test/go.mod replace to _base/ instead of .. (the local checkout root)
perl -i -pe 's|=> \.\.$|=> ../_base|' test/go.mod
echo "  test/go.mod   (replace => ../_base)"

if [ "$TARGET_MODULE" != "$SOURCE_MODULE" ]; then
    echo ""
    echo ">>> Adjusting module paths ($SOURCE_MODULE -> $TARGET_MODULE)..."

    # test/go.mod: replace module references
    perl -i -pe "s|\Q$SOURCE_MODULE\E|$TARGET_MODULE|g" test/go.mod

    # _base/go.mod: update module name so Go recognizes it as the target module
    perl -i -pe "s|\Q$SOURCE_MODULE\E|$TARGET_MODULE|g" _base/go.mod

    # go.sum will be wrong after module path change; go mod tidy regenerates it
    rm -f test/go.sum _base/go.sum

    # Go source files in test/ and _base/api/
    find test -name "*.go" -exec perl -i -pe "s|\Q$SOURCE_MODULE\E|$TARGET_MODULE|g" {} \;
    find _base/api -name "*.go" -exec perl -i -pe "s|\Q$SOURCE_MODULE\E|$TARGET_MODULE|g" {} \;
    find _base/pkg -name "*.go" -exec perl -i -pe "s|\Q$SOURCE_MODULE\E|$TARGET_MODULE|g" {} \;

    echo "  Updated test/, _base/go.mod, _base/api/, _base/pkg/"
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

