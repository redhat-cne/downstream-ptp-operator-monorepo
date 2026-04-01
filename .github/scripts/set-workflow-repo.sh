#!/bin/bash
# Script to set or reset the repository reference in workflow files
# 
# Usage:
#   ./set-workflow-repo.sh                    # Reset to default (k8snetworkplumbingwg/ptp-operator)
#   ./set-workflow-repo.sh owner/repo         # Set to custom repository
#   ./set-workflow-repo.sh --current          # Show current repository reference

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="$SCRIPT_DIR/../workflows"
DEFAULT_REPO="redhat-cne/upstream-ptp-operator-monorepo"

get_current_repo() {
    grep -h "uses:.*/_reusable-" "$WORKFLOWS_DIR"/*.y*ml 2>/dev/null | \
        head -1 | \
        sed 's/.*uses: \([^/]*\/[^/]*\)\/.*/\1/' || echo "unknown"
}

show_current() {
    local current=$(get_current_repo)
    echo "Current repository reference: $current"
    [ "$current" = "$DEFAULT_REPO" ] && echo "Status: Using default" || echo "Status: Custom (default: $DEFAULT_REPO)"
}

set_repo() {
    local new_repo="$1"
    local current=$(get_current_repo)
    
    [ "$current" = "$new_repo" ] && echo "Already set to: $new_repo" && return 0
    
    echo "Updating: $current -> $new_repo"
    
    local count=0
    for f in "$WORKFLOWS_DIR"/*.y*ml; do
        [[ "$(basename "$f")" == _reusable-* ]] && continue
        if grep -q "uses:.*/_reusable-" "$f"; then
            perl -i -pe "s|uses: [^/]+/[^/]+/\.github/workflows/(_reusable-)|uses: $new_repo/.github/workflows/\$1|g" "$f"
            ((count++))
        fi
    done
    
    echo "Updated $count files"
    show_current
}

case "${1:-}" in
    --current|-c) show_current ;;
    --help|-h) echo "Usage: $0 [owner/repo | --current]" ;;
    "") set_repo "$DEFAULT_REPO" ;;
    *) [[ "$1" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]] && set_repo "$1" || echo "Error: Invalid format (expected: owner/repo)" ;;
esac
