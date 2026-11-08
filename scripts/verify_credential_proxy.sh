#!/usr/bin/env bash
# Verify proxy-managed credential injection from inside a sandbox.
# For every host in a kit's inject list, send a bearer value that cannot be a real key
# and report whether the egress proxy replaced it.
set -uo pipefail

usage() {
  cat <<USAGE
Usage: $0 [--spec FILE] [--url URL]...

Options:
  --spec FILE   Kit spec to read inject domains from (default: kits/all/spec.yaml next to this script)
  --url URL     Probe this URL instead of the spec hosts. Repeatable. Use it for a port or path,
                for example http://192.168.1.235:11234/v1/models
  -h, --help    Show this help

Results:
  injected     Endpoint accepted a bogus key, so the proxy replaced the header.
  passthrough  Endpoint rejected the bogus key (401/400/403). No header rewrite happened. The host is
               missing from inject, or the domain, port or plain HTTP is outside the match.
  421          The host is in inject but missing from permissions.network.allow.
  unreachable  No response. Check network.allow and the endpoint.
USAGE
}

script_dir="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")"
spec="${script_dir}/../kits/all/spec.yaml"
urls=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --spec) spec="$2"; shift 2 ;;
  --url) urls+=("$2"); shift 2 ;;
  -h | --help) usage; exit 0 ;;
  *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ${#urls[@]} -eq 0 ]]; then
  [[ -r "$spec" ]] || { echo "Cannot read spec: $spec" >&2; exit 2; }
  while read -r host; do
    case "$host" in
    api.*githubcopilot.com) urls+=("https://${host}/models") ;;
    *) urls+=("http://${host}/") ;;
    esac
  done < <(sed -n 's/^ *- domain: *//p' "$spec" | sort -u)
fi

failures=0
for url in "${urls[@]}"; do
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' \
    -H 'Authorization: Bearer probe-bogus-key-000' "$url" 2>/dev/null)
  case "$code" in
  000) verdict="unreachable"; failures=$((failures + 1)) ;;
  421) verdict="421 (host in inject but missing from network.allow)"; failures=$((failures + 1)) ;;
  401 | 400 | 403) verdict="passthrough (sentinel rejected, ${code})"; failures=$((failures + 1)) ;;
  *) verdict="injected (${code})" ;;
  esac
  printf '%-60s %s\n' "$url" "$verdict"
done

echo
echo "Note: pi auth check reports ready for any value. Only a request that reaches the endpoint proves injection."
[[ $failures -eq 0 ]]
