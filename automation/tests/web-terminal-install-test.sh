#!/usr/bin/env bash
# Self-check for web-terminal-install.sh with a stub `oc`: install when no Subscription exists or this lab's
# Application tracks it (label or annotation tracking); do not when another owner installed it; fail on a read error.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf '#!/usr/bin/env bash\n[[ ${OC_MODE:-} == fail ]] && exit 1\ncat "$OC_STATE"\n' > "$tmp/oc"; chmod +x "$tmp/oc"
run() { printf '%s' "$1" > "$tmp/state"; PATH="$tmp:$PATH" OC_STATE="$tmp/state" OC_MODE="${2:-}" bash "$here/../web-terminal-install.sh" openshell-lab 2>/dev/null; }
fail=0
expect() { local got; got=$(run "$2" "${3:-}"); [[ $got == "$1" ]] || { echo "FAIL: $4 (got '$got', want '$1')"; fail=1; }; }
expect true '{"items":[]}' '' 'no Subscription'
expect true '{"items":[{"spec":{"name":"web-terminal"},"metadata":{"labels":{"app.kubernetes.io/instance":"openshell-lab-prereqs"}}}]}' '' 'tracked by label'
expect true '{"items":[{"spec":{"name":"web-terminal"},"metadata":{"annotations":{"argocd.argoproj.io/tracking-id":"openshell-lab-prereqs:operators.coreos.com/Subscription:openshift-operators/web-terminal"}}}]}' '' 'tracked by annotation'
expect false '{"items":[{"spec":{"name":"web-terminal"},"metadata":{"labels":{"app.kubernetes.io/part-of":"openshell-lab"}}}]}' '' 'installed by someone else'
expect false '{"items":[{"spec":{"name":"web-terminal"},"metadata":{"annotations":{"argocd.argoproj.io/tracking-id":"openshell-lab-prereqsX:x"}}}]}' '' 'similar but different Application'
expect true '{"items":[{"spec":{"name":"other"},"metadata":{}}]}' '' 'only other operators'
PATH="$tmp:$PATH" OC_STATE=/dev/null OC_MODE=fail bash "$here/../web-terminal-install.sh" openshell-lab >/dev/null 2>&1 && { echo "FAIL: succeeded although oc failed"; fail=1; }
[[ $fail == 0 ]] && echo PASS
exit $fail
