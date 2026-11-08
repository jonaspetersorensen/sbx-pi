#!/usr/bin/env bash
# Bump every pinned version to the latest release and pin the result.
#
# Updates the ARG defaults in Dockerfile and DEFAULT_PI_VERSION in build.sh:
#   NODEJS_MAJOR_VERSION  latest LTS Node.js major that NodeSource publishes
#   PI_VERSION            npm @earendil-works/pi-coding-agent (also build.sh)
#   GITHUB_GH_VERSION     latest GitHub CLI release
#   OPENSPEC_VERSION      npm @fission-ai/openspec
# Sourced scripts leak `set -e` and `exit` into the caller's shell and close the terminal or
# tmux pane on any failure. When sourced, run in a child shell instead.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  bash "${BASH_SOURCE[0]}" "$@"
  return $?
fi

set -euo pipefail

SCRIPT_DIR="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
ROOT="$(dirname -- "$SCRIPT_DIR")"
DOCKERFILE="${ROOT}/Dockerfile"
BUILD_SH="${ROOT}/build.sh"
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $0 [--dry-run] [-h|--help]

Look up the latest version of every pinned component and write it to
Dockerfile and build.sh. Existing pins are replaced with exact versions.

Options:
  --dry-run   Print the planned changes without editing files
  -h, --help  Show this help

After a bump, run scripts/openspec/verify.sh. If the build fails with
"anchor for '...' matched 0 times", update the anchors in
scripts/openspec/patch_schema.mjs.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run) DRY_RUN=true; shift ;;
  -h | --help) usage; exit 0 ;;
  *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

npm_latest() {
  curl -fsSL "https://registry.npmjs.org/$1/latest" | jq -er '.version'
}

# Resolve the redirect instead of the API to avoid its anonymous rate limit.
gh_latest() {
  local url
  url=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest)
  [[ "$url" =~ /tag/v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || { echo "Unexpected gh release URL: $url" >&2; return 1; }
  echo "${BASH_REMATCH[1]}"
}

# Highest LTS Node.js major whose NodeSource repository exists, since the image installs from it.
node_latest_major() {
  local major
  major=$(curl -fsSL https://nodejs.org/dist/index.json | jq -er '[.[] | select(.lts != false) | .version | ltrimstr("v") | split(".")[0] | tonumber] | max')
  while [[ $major -gt 0 ]]; do
    if curl -fsSI "https://deb.nodesource.com/node_${major}.x/dists/nodistro/Release" >/dev/null 2>&1; then
      echo "$major"
      return 0
    fi
    major=$((major - 1))
  done
  return 1
}

current() {
  sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$2" | head -n1
}

current_arg() {
  sed -n "s/^ARG $1=\(.*\)\$/\1/p" "$DOCKERFILE" | head -n1
}

echo "Looking up latest versions..."
new_node=$(node_latest_major)
new_pi=$(npm_latest "@earendil-works/pi-coding-agent")
new_gh=$(gh_latest)
new_openspec=$(npm_latest "@fission-ai/openspec")

for v in "$new_node" "$new_pi" "$new_gh" "$new_openspec"; do
  [[ "$v" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "Refusing odd version: $v" >&2; exit 1; }
done

changed=false
report() {
  local name="$1" old="$2" new="$3"
  if [[ "$old" == "$new" ]]; then
    printf '  %-22s %s (unchanged)\n' "$name" "$old"
  else
    printf '  %-22s %s -> %s\n' "$name" "${old:-unset}" "$new"
    changed=true
  fi
}

old_node=$(current_arg NODEJS_MAJOR_VERSION)
old_pi=$(current_arg PI_VERSION)
old_gh=$(current_arg GITHUB_GH_VERSION)
old_openspec=$(current_arg OPENSPEC_VERSION)
old_build_pi=$(current DEFAULT_PI_VERSION "$BUILD_SH")

echo
report NODEJS_MAJOR_VERSION "$old_node" "$new_node"
report PI_VERSION "$old_pi" "$new_pi"
report "build.sh PI default" "$old_build_pi" "$new_pi"
report GITHUB_GH_VERSION "$old_gh" "$new_gh"
report OPENSPEC_VERSION "$old_openspec" "$new_openspec"

if [[ "$changed" == false ]]; then
  echo
  echo "Everything is already at the latest version."
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  echo
  echo "Dry run: no files changed."
  exit 0
fi

sed -i \
  -e "s/^ARG NODEJS_MAJOR_VERSION=.*/ARG NODEJS_MAJOR_VERSION=${new_node}/" \
  -e "s/^ARG PI_VERSION=.*/ARG PI_VERSION=${new_pi}/" \
  -e "s/^ARG GITHUB_GH_VERSION=.*/ARG GITHUB_GH_VERSION=${new_gh}/" \
  -e "s/^ARG OPENSPEC_VERSION=.*/ARG OPENSPEC_VERSION=${new_openspec}/" \
  "$DOCKERFILE"
sed -i "s/^DEFAULT_PI_VERSION=.*/DEFAULT_PI_VERSION=\"${new_pi}\"/" "$BUILD_SH"

echo
echo "Pinned. Review with: git diff"
echo "Next: scripts/openspec/verify.sh, then rebuild with: source build.sh"
