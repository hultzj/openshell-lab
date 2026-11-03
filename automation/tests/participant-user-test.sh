#!/usr/bin/env bash
# Self-check for participant-user.sh with a stub `oc`: a failed OAuth read must not patch anything,
# an existing provider list must be appended to (never replaced), the participant must get cluster-admin,
# and a re-run must not add a duplicate.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/oc" <<'STUB'
#!/usr/bin/env bash
echo "oc $*" >> "$OC_LOG"
case "$1 $2" in
  "get oauth") [[ $OC_MODE == fail ]] && exit 1; cat "$OC_STATE" ;;
  "patch oauth") echo "$*" >> "$OC_PATCHES" ;;
  "create secret") echo "{}" ;;
esac
exit 0
STUB
chmod +x "$tmp/oc"
printf '#!/usr/bin/env bash\necho "$3:stub" > "$2"\n' > "$tmp/htpasswd"; chmod +x "$tmp/htpasswd"   # no apache2-utils needed
fail=0
run() { PATH="$tmp:$PATH" OC_LOG="$tmp/log" OC_PATCHES="$tmp/patches" OC_STATE="$tmp/state" OC_MODE=$1 LAB_USER_PASSWORD=x bash "$here/../participant-user.sh" >/dev/null 2>&1; }
: > "$tmp/patches"; echo '{"spec":{"identityProviders":[{"name":"corp-ldap"}]}}' > "$tmp/state"
run fail && { echo "FAIL: script succeeded although the OAuth read failed"; fail=1; }
[[ -s $tmp/patches ]] && { echo "FAIL: patched OAuth after a failed read"; fail=1; }
: > "$tmp/patches"; run ok || { echo "FAIL: normal run failed"; fail=1; }
grep -q '"op":"add","path":"/spec/identityProviders/-"' "$tmp/patches" || { echo "FAIL: did not append to the existing list"; fail=1; }
grep -q '"identityProviders":\[\]' "$tmp/patches" && { echo "FAIL: replaced the provider list"; fail=1; }
grep -q 'oc adm policy add-cluster-role-to-user cluster-admin lab-admin --rolebinding-name=openshell-lab-participant' "$tmp/log" || { echo "FAIL: did not grant cluster-admin to the participant"; fail=1; }
: > "$tmp/patches"; echo '{"spec":{"identityProviders":[{"name":"corp-ldap"},{"name":"openshell-lab-htpasswd"}]}}' > "$tmp/state"
run ok; [[ -s $tmp/patches ]] && { echo "FAIL: re-run patched again"; fail=1; }
: > "$tmp/patches"; echo '{"spec":{}}' > "$tmp/state"
run ok; grep -q '"path":"/spec/identityProviders","value":\[' "$tmp/patches" || { echo "FAIL: did not create the list when absent"; fail=1; }
[[ $fail == 0 ]] && echo PASS
exit $fail
