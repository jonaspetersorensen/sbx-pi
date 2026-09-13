#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Enable pi to authenticate to copilot via sbx kit ==="
echo ""

echo "Can we use gh?"
if gh auth token 2>/dev/null | cut -c1-12 | grep -q '^gho_'; then
  echo "Yes: gh's OAuth token is a viable fallback for Copilot CLI."
else
  echo "No: gh's token is not a gho_ OAuth token."
  echo "You will have to manually set the secret in sbx when you have a tool that can provide the token."
  echo "Example:"
  echo "sbx secret set copilot --command 'gh auth token'"
  exit 0
fi

sbx secret set copilot --command 'gh auth token'

echo ""
echo "Validating Docker Sandbox kit..."
sbx kit validate "${SCRIPT_DIR}/kit"
echo ""

echo "Configuration completed."
echo "From now on run the sandbox via the kit:"
echo "   sbx run ${SCRIPT_DIR}/kit"
echo "to enable copilot authentication."
