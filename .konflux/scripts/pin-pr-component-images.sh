#!/usr/bin/env bash
# Rewrite .konflux/overlay/pin_images.in.yaml targets to digests of same-revision
# PR component tags (on-pr-<sha>). Optional: the default bundle PipelineRun
# leaves --tag empty so committed pins stay in the CSV.
#
# Only rewrites targets under the Konflux tenant quay prefix.
#
# Usage:
#   pin-pr-component-images.sh --tag on-pr-<revision> [--pin-file PATH]
#   pin-pr-component-images.sh --tag on-pr-latest --dry-run
#
# When --tag is empty, exits 0 without modifying the pin file.

set -euo pipefail

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
PIN_FILE=".konflux/overlay/pin_images.in.yaml"
TAG=""
DRY_RUN=false
MAX_ATTEMPTS=90
SLEEP_SECONDS=20
TENANT_PREFIX="quay.io/redhat-user-workloads/experimental-ptp-tenant/"
CRANE_BIN=""
USE_SKOPEO=false

# Logs must go to stderr: wait_digest is captured via $(), and stdout pollution
# would corrupt pin digests (breaking the bundle CSV YAML).
log() { echo "[$SCRIPT_NAME] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME --tag TAG [options]

Options:
  --tag TAG             Image tag to resolve (e.g. on-pr-<git-sha>). Empty = no-op.
  --pin-file PATH       Pin file to rewrite (default: $PIN_FILE)
  --max-attempts N      Crane/skopeo poll attempts (default: $MAX_ATTEMPTS)
  --sleep-seconds N     Sleep between attempts (default: $SLEEP_SECONDS)
  --dry-run             Print rewrites; do not modify the pin file
  -h, --help            Show this help
EOF
}

pin_yaml_list_field() {
  local field="$1"
  python3 - "$PIN_FILE" "$field" <<'PY'
import re, sys
path, field = sys.argv[1], sys.argv[2]
with open(path) as f:
    text = f.read()
for m in re.finditer(rf'^  {field}: (\S+)', text):
    print(m.group(1))
PY
}

pin_yaml_set_target() {
  local key="$1" new_target="$2"
  python3 - "$PIN_FILE" "$key" "$new_target" <<'PY'
import re, sys
path, key, new_target = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    text = f.read()
pat = r'(- key: ' + re.escape(key) + r'\n(?:  [^\n]+\n)*?  target: )\S+'
new_text, n = re.subn(pat, r'\1' + new_target, text, count=1)
if n != 1:
    raise SystemExit(f'failed to update target for key {key}')
with open(path, 'w') as f:
    f.write(new_text)
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="${2:-}"; shift 2 ;;
    --pin-file) PIN_FILE="${2:-}"; shift 2 ;;
    --max-attempts) MAX_ATTEMPTS="${2:-}"; shift 2 ;;
    --sleep-seconds) SLEEP_SECONDS="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [[ -z "${TAG}" ]]; then
  log "No --tag set; leaving ${PIN_FILE} unchanged"
  exit 0
fi

[[ -f "${PIN_FILE}" ]] || die "pin file not found: ${PIN_FILE}"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

ensure_crane() {
  if command -v crane >/dev/null 2>&1; then
    CRANE_BIN=$(command -v crane)
    return 0
  fi
  if command -v skopeo >/dev/null 2>&1; then
    USE_SKOPEO=true
    log "crane not found; using preinstalled skopeo"
    return 0
  fi
  die "need crane or skopeo to resolve image digests"
}

resolve_digest() {
  local pullspec="$1"
  if [[ -n "${CRANE_BIN}" ]]; then
    "${CRANE_BIN}" digest "${pullspec}"
    return
  fi
  # Local/dev fallback (macOS often needs OS/arch overrides).
  skopeo inspect --override-os linux --override-arch amd64 \
    --format '{{.Digest}}' "docker://${pullspec}"
}

wait_digest() {
  local pullspec="$1"
  local i=0
  local digest=""
  while [[ "${i}" -lt "${MAX_ATTEMPTS}" ]]; do
    if digest="$(resolve_digest "${pullspec}" 2>/dev/null)" && [[ -n "${digest}" ]]; then
      echo "${digest}"
      return 0
    fi
    i=$((i + 1))
    log "Waiting for ${pullspec} (${i}/${MAX_ATTEMPTS})..."
    sleep "${SLEEP_SECONDS}"
  done
  return 1
}

# Prefer an installed crane, then an installed skopeo. Never download tools
# at runtime: this task runs hermetically and has no network access to GitHub.
ensure_crane

log "Rewriting tenant pins in ${PIN_FILE} to tag ${TAG}"

KEYS=()
TARGETS=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && KEYS+=("${line}")
done < <(pin_yaml_list_field key)
while IFS= read -r line; do
  [[ -n "${line}" ]] && TARGETS+=("${line}")
done < <(pin_yaml_list_field target)

rewrites=0
for i in "${!KEYS[@]}"; do
  key="${KEYS[$i]}"
  target="${TARGETS[$i]}"
  [[ -n "${key}" && -n "${target}" ]] || continue

  case "${target}" in
    "${TENANT_PREFIX}"*) ;;
    *)
      log "Skipping non-tenant pin ${key}: ${target}"
      continue
      ;;
  esac

  repo="${target%@*}"
  tagged="${repo}:${TAG}"
  log "Resolving ${key}: ${tagged}"

  if ! digest="$(wait_digest "${tagged}")"; then
    die "timed out waiting for ${tagged}"
  fi
  # Defense in depth: only the digest line may appear on stdout.
  digest="$(printf '%s\n' "${digest}" | tail -n1 | tr -d '[:space:]')"
  [[ "${digest}" =~ ^sha256:[0-9a-f]+$ ]] || die "invalid digest for ${tagged}: ${digest}"

  new_target="${repo}@${digest}"
  if [[ "${target}" == "${new_target}" ]]; then
    log "Unchanged ${key}: ${new_target}"
    continue
  fi

  log "Pin ${key}: ${target} -> ${new_target}"
  if [[ "${DRY_RUN}" == true ]]; then
    rewrites=$((rewrites + 1))
    continue
  fi

  pin_yaml_set_target "${key}" "${new_target}"
  rewrites=$((rewrites + 1))
done

if [[ "${DRY_RUN}" == true ]]; then
  log "Dry-run complete (${rewrites} rewrite(s) planned)"
else
  log "Updated ${PIN_FILE} (${rewrites} rewrite(s))"
  cat "${PIN_FILE}"
fi
