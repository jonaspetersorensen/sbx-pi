#!/usr/bin/env bash
set -eo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
DEFAULT_PI_VERSION="0.82.1"
IMAGE_TAG="sbx-pi:${DEFAULT_PI_VERSION}"
OUTPUT_TAR="out/sbx-pi-v${DEFAULT_PI_VERSION}.tar"
GIT_USER_NAME=""
GIT_USER_EMAIL=""

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Build and load an sbx-pi template image.

Options:
  --version VER              Pi version (skips version selector)
  --git-user-name NAME       Git user.name (skips git config dialog)
  --git-user-email EMAIL     Git user.email (skips git config dialog)
  -h, --help                 Show this help

Environment:
  PI_VERSION                 Override default Pi version
EOF
  return 0
}

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
  --version)
    PI_VERSION="$2"
    shift 2
    ;;
  --git-user-name)
    GIT_USER_NAME="$2"
    shift 2
    ;;
  --git-user-email)
    GIT_USER_EMAIL="$2"
    shift 2
    ;;
  -h | --help) usage ;;
  *)
    echo "Unknown option: $1"
    return 1
    ;;
  esac
done

# If --version given, skip version selector
SKIP_VERSION_SELECTOR=false
if [[ -n "${PI_VERSION:-}" ]]; then
  SKIP_VERSION_SELECTOR=true
fi

# ── Fetch latest releases ────────────────────────────────────────────────────
fetch_releases() {
  local json
  json=$(curl -s https://api.github.com/repos/earendil-works/pi/releases 2>/dev/null) || {
    echo "Warning: Could not fetch releases from GitHub API."
    echo "Using default version: ${DEFAULT_PI_VERSION}"
    return 1
  }

  if [[ -z "$json" ]]; then
    echo "Warning: GitHub API returned empty response."
    echo "Using default version: ${DEFAULT_PI_VERSION}"
    return 1
  fi

  echo "$json" | jq -r '.[0:5] | .[] | "\(.tag_name)|\(.published_at)|\(.body // "No description" | gsub("\\n";" ")[:120])"'
}

# ── Helper: yes/no prompt ────────────────────────────────────────────────────
prompt_yes_no() {
  local prompt="$1"
  local default="${2:-Y}"
  local answer

  if [[ "$default" == "Y" ]]; then
    prompt+=" [Y/n] "
  else
    prompt+=" [y/N] "
  fi

  while true; do
    read -rp "$prompt" answer
    case "$answer" in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    "") [[ "$default" == "Y" ]] && return 0 || return 1 ;;
    esac
  done
}

# ── Version selector ─────────────────────────────────────────────────────────
if [[ "$SKIP_VERSION_SELECTOR" == false ]]; then
  echo "Fetching latest Pi releases..."
  releases=$(fetch_releases) || {
    PI_VERSION="$DEFAULT_PI_VERSION"
  }

  if [[ -n "${releases:-}" ]]; then
    # Parse into arrays
    mapfile -t lines <<<"$releases"
    count=${#lines[@]}

    echo ""
    echo "=== Select Pi version ==="
    for i in $(seq 0 $((count - 1))); do
      IFS='|' read -r tag date body <<<"${lines[$i]}"
      # Strip 'v' prefix
      version="${tag#v}"
      # Format date
      formatted_date=$(echo "$date" | cut -d'T' -f1)
      # Truncate body for display
      display_body="${body:0:80}"
      [[ ${#body} -gt 80 ]] && display_body+="..."
      printf "  %d) %s  (%s)\n     %s\n" "$((i + 1))" "$version" "$formatted_date" "$display_body"
    done
    echo ""
    echo "  0) Enter custom version"
    echo ""

    # Default to first item (latest)
    default_selection=1

    while true; do
      read -rp "  Select [${default_selection}-${count}, 0]: " selection
      selection="${selection:-$default_selection}"

      if [[ "$selection" == "0" ]]; then
        read -rp "  Enter version: " PI_VERSION
        if [[ -n "$PI_VERSION" ]]; then
          break
        fi
      elif [[ "$selection" =~ ^[0-9]+$ ]] && ((selection >= 1 && selection <= count)); then
        IFS='|' read -r tag _ _ <<<"${lines[$((selection - 1))]}"
        PI_VERSION="${tag#v}"
        break
      else
        echo "  Invalid selection. Please enter a number 0-${count}."
      fi
    done
  else
    PI_VERSION="$DEFAULT_PI_VERSION"
  fi
fi

# ── Git config dialog ────────────────────────────────────────────────────────
SKIP_GIT_DIALOG=false
if [[ -n "$GIT_USER_NAME" && -n "$GIT_USER_EMAIL" ]]; then
  SKIP_GIT_DIALOG=true
fi

if [[ "$SKIP_GIT_DIALOG" == false ]]; then
  if prompt_yes_no "Bake in git config (user.name, user.email) into the template?" N; then
    # Try to read from host
    GIT_USER_NAME="${GIT_USER_NAME:-$(git config --global user.name 2>/dev/null || echo "")}"
    GIT_USER_EMAIL="${GIT_USER_EMAIL:-$(git config --global user.email 2>/dev/null || echo "")}"

    # Prompt for missing values
    if [[ -z "$GIT_USER_NAME" ]]; then
      read -rp "  user.name: " GIT_USER_NAME
    fi
    if [[ -z "$GIT_USER_EMAIL" ]]; then
      read -rp "  user.email: " GIT_USER_EMAIL
    fi

    # Confirm before proceeding
    echo ""
    echo "  user.name : $GIT_USER_NAME"
    echo "  user.email: $GIT_USER_EMAIL"
    echo ""

    if ! prompt_yes_no "Use these values?"; then
      GIT_USER_NAME=""
      GIT_USER_EMAIL=""
    fi
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
IMAGE_TAG="sbx-pi:${PI_VERSION}"
echo ""
echo "=== Summary ==="
echo "  PI version : ${PI_VERSION}"
if [[ -n "$GIT_USER_NAME" && -n "$GIT_USER_EMAIL" ]]; then
  echo "  git user.name : ${GIT_USER_NAME}"
  echo "  git user.email: ${GIT_USER_EMAIL}"
fi
echo ""

if ! prompt_yes_no "Proceed with build?" Y; then
  echo "Aborted."
  return 0
fi

# ── Step 1: Build ─────────────────────────────────────────────────────────────
echo ""
echo "=== Step 1: Build image ${IMAGE_TAG} ==="
BUILD_ARGS=("--build-arg" "PI_VERSION=${PI_VERSION}")
if [[ -n "$GIT_USER_NAME" ]]; then
  BUILD_ARGS+=("--build-arg" "GIT_USER_NAME=${GIT_USER_NAME}")
fi
if [[ -n "$GIT_USER_EMAIL" ]]; then
  BUILD_ARGS+=("--build-arg" "GIT_USER_EMAIL=${GIT_USER_EMAIL}")
fi

docker build "${BUILD_ARGS[@]}" -t "${IMAGE_TAG}" .
echo ""

# ── Step 2: Save + Load ───────────────────────────────────────────────────────
OUTPUT_TAR="out/sbx-pi-v${PI_VERSION}.tar"
echo "=== Step 2: Save image to ${OUTPUT_TAR} ==="
mkdir -p out
docker image save "${IMAGE_TAG}" -o "${OUTPUT_TAR}"
echo ""

echo "=== Step 2: Load template into sandbox runtime ==="
sbx template load "${OUTPUT_TAR}"
echo ""

echo "=== Done ==="
echo "To run a sandbox: sbx run --name pi-sandbox --template ${IMAGE_TAG} shell"
