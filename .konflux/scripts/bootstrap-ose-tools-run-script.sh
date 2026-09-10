#!/usr/bin/env bash
# Bootstrap tools missing from ose-tools-rhel9 when run-script-oci-ta runs
# without the yq/skopeo sidecars. Used by FBC run-opm-pre-actions.
#
# Push builds keep run-opm-pre-actions hermetic=true, so yq cannot be curled from
# GitHub. Prefer vendored binaries from .konflux/tools/ (from quay.io/konflux-ci/yq).
set -euo pipefail

YQ_IMAGE="${YQ_IMAGE:-quay.io/konflux-ci/yq:latest}"
YQ_VERSION="${YQ_VERSION:-4.44.3}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDORED_TOOLS_DIR="${SCRIPT_DIR}/../tools"

normalize_arch() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    ppc64le) echo ppc64le ;;
    s390x) echo s390x ;;
    *)
      echo "ERROR: unsupported arch for yq bootstrap: $(uname -m)" >&2
      return 1
      ;;
  esac
}

bootstrap_skopeo() {
  if command -v skopeo >/dev/null 2>&1; then
    return 0
  fi
  microdnf install -y skopeo
}

bootstrap_yq_from_vendored() {
  local yq_arch dest=/usr/local/bin/yq vendored
  yq_arch="$(normalize_arch)"
  vendored="${VENDORED_TOOLS_DIR}/yq-linux-${yq_arch}"
  if [[ ! -f "${vendored}" ]]; then
    return 1
  fi
  install -m 0755 "${vendored}" "${dest}"
}

bootstrap_yq_from_registry() {
  bootstrap_skopeo
  local yq_arch tmpdir work dest=/usr/local/bin/yq archive layer
  yq_arch="$(normalize_arch)"
  tmpdir="$(mktemp -d)"
  work="$(mktemp -d)"
  archive="${tmpdir}/yq.tar"
  mkdir -p "${work}/root"
  skopeo copy --override-os linux --override-arch "${yq_arch}" \
    "docker://${YQ_IMAGE}" "docker-archive:${archive}"
  tar -xf "${archive}" -C "${work}"
  for layer in "${work}"/*/layer.tar; do
    if tar -tf "${layer}" | grep -q '^usr/bin/yq$'; then
      tar -xf "${layer}" -C "${work}/root" usr/bin/yq
      install -m 0755 "${work}/root/usr/bin/yq" "${dest}"
      return 0
    fi
  done
  echo "ERROR: usr/bin/yq not found in ${YQ_IMAGE}" >&2
  return 1
}

bootstrap_yq_from_github() {
  local yq_arch dest=/usr/local/bin/yq
  yq_arch="$(normalize_arch)"
  curl -fsSL -o "${dest}" \
    "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${yq_arch}"
  chmod +x "${dest}"
}

bootstrap_yq() {
  if command -v yq >/dev/null 2>&1; then
    return 0
  fi
  if bootstrap_yq_from_vendored; then
    return 0
  fi
  if bootstrap_yq_from_registry; then
    return 0
  fi
  bootstrap_yq_from_github
}

case "${1:-all}" in
  skopeo) bootstrap_skopeo ;;
  yq) bootstrap_yq ;;
  all)
    bootstrap_skopeo
    bootstrap_yq
    ;;
  *)
    echo "usage: $0 [skopeo|yq|all]" >&2
    exit 1
    ;;
esac
