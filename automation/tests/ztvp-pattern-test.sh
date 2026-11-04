#!/usr/bin/env bash
# The Pattern carries the RHDP base-operator overrides by default, the parent passes them to the ztvp child,
# and bootstrap.yaml's "extraParameters: []" leaves the pattern's own defaults.
set -uo pipefail
cd "$(dirname "$0")/../.."
fail=0

# value_of <rendered yaml> <parameter name>: the value on the line after "- name: <name>".
value_of() { awk -v n="$2" '$0 ~ "- name: " n "$" {getline; sub(/^[ \t]*value:[ \t]*/, ""); gsub(/"/, ""); print; exit}' <<<"$1"; }

pattern=$(helm template t components/ztvp -f values.yaml --show-only templates/pattern.yaml) || { echo "FAIL: ztvp chart does not render"; fail=1; }
[[ $(value_of "$pattern" clusterGroup.namespaces.cert-manager-operator.operatorGroup) == false ]] || { echo "FAIL: Pattern does not set the cert-manager OperatorGroup override to false"; fail=1; }
[[ $(value_of "$pattern" clusterGroup.subscriptions.rhbk.channel) == stable-v26.6 ]] || { echo "FAIL: Pattern does not set the RHBK channel to stable-v26.6"; fail=1; }

parent=$(helm template t . --set deployer.domain=apps.example.com) || { echo "FAIL: parent chart does not render"; fail=1; }
grep -q 'name: clusterGroup.subscriptions.rhbk.channel' <<<"$parent" || { echo "FAIL: parent does not pass extraParameters to the ztvp child"; fail=1; }

grep -A3 '^        ztvp:' automation/bootstrap.yaml | grep -q 'extraParameters: \[\]' || { echo "FAIL: bootstrap.yaml does not clear extraParameters"; fail=1; }
if bare=$(helm template t components/ztvp -f values.yaml --set-json 'ztvp.extraParameters=[]' --show-only templates/pattern.yaml); then
  grep -q 'kind: Pattern' <<<"$bare" || { echo "FAIL: no Pattern rendered with an empty list"; fail=1; }
  ! grep -q extraParameters <<<"$bare" || { echo "FAIL: an empty list still renders extraParameters"; fail=1; }
else
  echo "FAIL: ztvp chart does not render with an empty extraParameters list"; fail=1
fi

[[ $fail == 0 ]] && echo "PASS: ztvp-pattern-test"
exit "$fail"
