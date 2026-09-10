#!/usr/bin/env bash
# Bootstrap tools missing from ose-tools-rhel9 when run-script-oci-ta runs
# non-hermetically (no yq sidecar). Used by FBC run-opm-pre-actions on PR builds.
set -euo pipefail

YQ_VERSION="${YQ_VERSION:-4.44.3}"

bootstrap_skopeo() {
  if command -v skopeo >/dev/null 2>&1; then
    return 0
  fi
  microdnf install -y skopeo
}

bootstrap_yq() {
  if command -v yq >/dev/null 2>&1; then
    return 0
  fi
  local arch yq_arch dest=/usr/local/bin/yq
  arch="$(uname -m)"
  case "${arch}" in
    x86_64) yq_arch=amd64 ;;
    aarch64) yq_arch=arm64 ;;
    *)
      echo "ERROR: unsupported arch for yq bootstrap: ${arch}" >&2
      return 1
      ;;
  esac
  curl -fsSL -o "${dest}" \
    "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${yq_arch}"
  chmod +x "${dest}"
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
