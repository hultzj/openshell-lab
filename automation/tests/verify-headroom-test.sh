#!/usr/bin/env bash
# Self-check for verify.sh's pod_headroom with a stub `oc`: room counts only on nodes that take ordinary pods,
# and pods waiting for a node use it up.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# The stub prints $OC_NODES for "get nodes" and $OC_PODS for "get pods"; OC_MODE=fail makes every call fail.
cat > "$tmp/oc" <<'EOF'
#!/usr/bin/env bash
[[ ${OC_MODE:-} == fail ]] && exit 1
case " $* " in *" nodes "*) printf '%b' "$OC_NODES" ;; *" pods "*) printf '%b' "$OC_PODS" ;; *) exit 1 ;; esac
EOF
chmod +x "$tmp/oc"
eval "$(sed -n '/^pod_headroom() {/,/^}/p' "$here/../verify.sh")"
declare -F pod_headroom >/dev/null || { echo "FAIL: pod_headroom not found in verify.sh"; exit 1; }
pods() { local out="" i; for ((i = 0; i < $2; i++)); do out+="n=$1\n"; done; printf '%s' "$out"; }
fail=0
expect() {  # expect <0|1> <nodes> <pods> <title>
  PATH="$tmp:$PATH" OC_NODES="$2" OC_PODS="$3" pod_headroom; local got=$?
  [[ $got == "$1" ]] || { echo "FAIL: $4 (got $got, want $1)"; fail=1; }
}
expect 1 'sno 250 u= t=\n' "$(pods sno 259)" 'single node over its limit'
expect 0 'sno 500 u= t=\n' "$(pods sno 259)" 'single node with maxPods 500'
expect 1 'sno 250 u= t=\n' "$(pods sno 241)" 'nine free slots is not enough'
expect 0 'sno 250 u= t=\n' "$(pods sno 240)" 'ten free slots is enough'
expect 1 'm 250 u= t=NoSchedule\nw 250 u= t=\n' "$(pods m 10)$(pods w 245)" 'room only on a NoSchedule node'
expect 1 'm 250 u= t=NoExecute\nw 250 u= t=\n' "$(pods w 245)" 'room only on a NoExecute node'
expect 1 'c 250 u=true t=\nw 250 u= t=\n' "$(pods w 245)" 'room only on a cordoned node'
expect 0 'p 250 u= t=PreferNoSchedule\nw 250 u= t=\n' "$(pods w 250)" 'PreferNoSchedule still takes pods'
expect 1 'w 250 u= t=\n' "$(pods w 235)$(pods '' 6)" 'pending pods use up the room'
expect 1 '' '' 'no nodes'
PATH="$tmp:$PATH" OC_MODE=fail pod_headroom && { echo "FAIL: passed although oc failed"; fail=1; }
[[ $fail == 0 ]] && echo PASS
exit $fail
