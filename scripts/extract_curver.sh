#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: $0 SOURCEDIR" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage
SOURCEDIR="$1"

if [[ ! -d "$SOURCEDIR" ]]; then
  echo "Error: directory does not exist: $SOURCEDIR" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is not installed or not in PATH" >&2
  exit 1
fi

if ! git -C "$SOURCEDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not a git repository: $SOURCEDIR" >&2
  exit 1
fi

# Get the most recent annotated tag reachable from the current commit, with long format.
# The following is done under the assumption that a full clone is done and NOT a shallow clone, so that all tags are available.
# If this is not the case, the user should run 'git fetch --tags' to ensure tags are available.
if ! GIT_VERSION_BASE="$(
  git -C "$SOURCEDIR" describe --long --abbrev=7 2>/dev/null
)"; then
  echo "Error: no annotated tag reachable in $SOURCEDIR. Run 'git fetch --tags' to ensure tags are available." >&2
  exit 1
fi

if [[ -z "$GIT_VERSION_BASE" ]]; then
  echo "Error: empty git describe output for $SOURCEDIR" >&2
  exit 1
fi

# Strip optional leading v, then extract X.Y.Z at start.
GIT_VERSION="${GIT_VERSION_BASE#v}"

if [[ "$GIT_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-|$) ]]; then
  CURVER="${BASH_REMATCH[1]}"
else
  echo "Error: CURVER derived from GIT_VERSION \"$GIT_VERSION\" is not in X.Y.Z format" >&2
  exit 1
fi

echo "$CURVER"
