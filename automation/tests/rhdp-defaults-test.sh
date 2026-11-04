#!/usr/bin/env bash
# The chart's defaults fit an RHDP order and bootstrap.yaml turns them off:
# - the Pattern reuses the base install's cert-manager OperatorGroup and RHBK 26.6 (ztvp.extraParameters);
# - a KubeletConfig raises the single node's pod limit (prereqs.maxPods).
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
grep -q 'maxPods: 500' <<<"$parent" || { echo "FAIL: parent does not pass prereqs.maxPods to the prereqs child"; fail=1; }

grep -A3 '^        ztvp:' automation/bootstrap.yaml | grep -q 'extraParameters: \[\]' || { echo "FAIL: bootstrap.yaml does not clear extraParameters"; fail=1; }
if bare=$(helm template t components/ztvp -f values.yaml --set-json 'ztvp.extraParameters=[]' --show-only templates/pattern.yaml); then
  grep -q 'kind: Pattern' <<<"$bare" || { echo "FAIL: no Pattern rendered with an empty list"; fail=1; }
  ! grep -q extraParameters <<<"$bare" || { echo "FAIL: an empty list still renders extraParameters"; fail=1; }
else
  echo "FAIL: ztvp chart does not render with an empty extraParameters list"; fail=1
fi

# prereqs child values as the parent passes them (values.yaml's prereqs block).
kc=$(helm template t components/lab-prereqs -f <(sed -n '/^prereqs:/,/^[a-z]/p' values.yaml | sed '$d') --show-only templates/max-pods.yaml) || { echo "FAIL: lab-prereqs does not render the KubeletConfig"; fail=1; }
grep -q 'kind: KubeletConfig' <<<"$kc" && grep -q 'maxPods: 500$' <<<"$kc" && grep -q 'pools.operator.machineconfiguration.openshift.io/master: ""' <<<"$kc" ||
  { echo "FAIL: KubeletConfig does not set maxPods 500 on the master pool"; fail=1; }
grep -A6 '^        prereqs:' automation/bootstrap.yaml | grep -q 'maxPods: 0$' || { echo "FAIL: bootstrap.yaml does not set maxPods 0"; fail=1; }
if off=$(helm template t components/lab-prereqs --set prereqs.maxPods=0 2>&1); then
  ! grep -q 'kind: KubeletConfig' <<<"$off" || { echo "FAIL: maxPods 0 still renders a KubeletConfig"; fail=1; }
else
  echo "FAIL: lab-prereqs does not render with maxPods 0"; fail=1
fi

[[ $fail == 0 ]] && echo "PASS: rhdp-defaults-test"
exit "$fail"
