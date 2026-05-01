#!/usr/bin/env bash
#
# Build a multi-version FBC catalog image locally.
# Requires: opm, docker/podman, and all bundle images already pushed to GHCR.
#
set -euo pipefail

REGISTRY="${GHCR_REGISTRY:-ghcr.io}"
ORG="${GHCR_ORG:-redhat-cne}"
BUNDLE_IMAGE="${REGISTRY}/${ORG}/ptp-operator-bundle"
CATALOG_IMAGE="${GHCR_CATALOG_IMG:-${REGISTRY}/${ORG}/ptp-operator-catalog:latest}"
CONTAINER_TOOL="${CONTAINER_TOOL:-docker}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RELEASE_BRANCHES=(
  release-4.12
  release-4.13
  release-4.14
  release-4.15
  release-4.16
  release-4.17
  release-4.18
  release-4.19
  release-4.20
  release-4.21
  release-4.22
  release-4.23
  release-5.0
  main
)

echo "==> Collecting bundle versions from release branches..."
VERSIONS=()
for branch in "${RELEASE_BRANCHES[@]}"; do
  ver=$(git -C "${REPO_ROOT}" show "${branch}:Makefile" 2>/dev/null \
        | grep -m1 '^VERSION ?=' | awk '{print $3}') || continue
  if [[ -n "${ver}" ]]; then
    VERSIONS+=("${ver}.0")
    echo "  ${branch} -> ${ver}.0"
  fi
done

if [[ ${#VERSIONS[@]} -eq 0 ]]; then
  echo "ERROR: No versions found. Make sure release branches exist." >&2
  exit 1
fi

IFS=$'\n' SORTED=($(printf '%s\n' "${VERSIONS[@]}" | sort -Vu)); unset IFS
echo "==> Versions to include: ${SORTED[*]}"

rm -rf "${REPO_ROOT}/catalog"
mkdir -p "${REPO_ROOT}/catalog"

echo "==> Initializing catalog..."
opm init ptp-operator \
  --default-channel=stable \
  --description="${REPO_ROOT}/README.md" \
  --output=yaml > "${REPO_ROOT}/catalog/index.yaml"

for ver in "${SORTED[@]}"; do
  echo "==> Rendering ${BUNDLE_IMAGE}:v${ver}..."
  opm render "${BUNDLE_IMAGE}:v${ver}" --output=yaml >> "${REPO_ROOT}/catalog/index.yaml"
done

{
  echo "---"
  echo "schema: olm.channel"
  echo "package: ptp-operator"
  echo "name: stable"
  echo "entries:"
  for ver in "${SORTED[@]}"; do
    echo "  - name: ptp-operator.v${ver}"
    echo "    skipRange: \">=4.3.0-0 <${ver}\""
  done
} >> "${REPO_ROOT}/catalog/index.yaml"

echo "==> Validating catalog..."
opm validate "${REPO_ROOT}/catalog/"

echo "==> Building catalog image: ${CATALOG_IMAGE}"
"${CONTAINER_TOOL}" build \
  -t "${CATALOG_IMAGE}" \
  -f "${REPO_ROOT}/catalog-publish.Dockerfile" \
  "${REPO_ROOT}"

echo "==> Done. Push with: ${CONTAINER_TOOL} push ${CATALOG_IMAGE}"
