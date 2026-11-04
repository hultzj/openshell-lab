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
  "get secret") [[ -f ${OC_SECRET:-} ]] && base64 < "$OC_SECRET" ;;
  "patch oauth") echo "$*" >> "$OC_PATCHES" ;;
  "apply -f") cat > /dev/null ;;   # read stdin like the real oc, or the writer dies of SIGPIPE
  "create secret") for a in "$@"; do [[ $a == --from-file=htpasswd=* && -n ${OC_HTFILE:-} ]] && cp "${a#--from-file=htpasswd=}" "$OC_HTFILE"; done; echo "{}" ;;
esac
exit 0
STUB
chmod +x "$tmp/oc"
# Stub htpasswd (no apache2-utils needed), unless NO_HTPASSWD=1 tests the python3-bcrypt path.
[[ ${NO_HTPASSWD:-} == 1 ]] || { printf '#!/usr/bin/env bash\necho "$3:stub" > "$2"\n' > "$tmp/htpasswd"; chmod +x "$tmp/htpasswd"; }
fail=0
run() { PATH="$tmp:$PATH" OC_HTFILE="$tmp/htfile" OC_SECRET="${OC_SECRET:-}" OC_LOG="$tmp/log" OC_PATCHES="$tmp/patches" OC_STATE="$tmp/state" OC_MODE=$1 LAB_USER_PASSWORD=x bash "$here/../../components/lab-prereqs/files/participant-user.sh" >/dev/null 2>&1; }
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
# A secret that already holds this password is left alone (rewriting it restarts the OAuth server).
if python3 -c 'import bcrypt' 2>/dev/null; then
  printf 'lab-admin:%s\n' "$(python3 -c 'import bcrypt; h=bcrypt.hashpw(b"x", bcrypt.gensalt(rounds=4)).decode(); print("$2y$"+h[4:])')" > "$tmp/secret"
  : > "$tmp/log"; OC_SECRET="$tmp/secret" run ok
  grep -q 'create secret' "$tmp/log" && { echo "FAIL: rewrote a matching htpasswd secret"; fail=1; }
  printf 'lab-admin:%s\n' "$(python3 -c 'import bcrypt; h=bcrypt.hashpw(b"other", bcrypt.gensalt(rounds=4)).decode(); print("$2y$"+h[4:])')" > "$tmp/secret"
  : > "$tmp/log"; OC_SECRET="$tmp/secret" run ok
  grep -q 'create secret' "$tmp/log" || { echo "FAIL: kept a secret with a different password"; fail=1; }
else
  echo "(python3 bcrypt not installed: matching-secret case skipped)"
fi
# The python3-bcrypt path (the in-cluster Job has no htpasswd) writes a hash the OAuth server accepts and that
# verifies against the password.
if [[ ${NO_HTPASSWD:-} == 1 ]] && python3 -c 'import bcrypt' 2>/dev/null; then
  : > "$tmp/htfile"; echo '{"spec":{}}' > "$tmp/state"
  PATH="$tmp:$PATH" OC_HTFILE="$tmp/htfile" OC_LOG="$tmp/log" OC_PATCHES="$tmp/patches" OC_STATE="$tmp/state" OC_MODE=ok \
    LAB_USER_PASSWORD=x bash "$here/../../components/lab-prereqs/files/participant-user.sh" >/dev/null 2>&1
  line=$(head -1 "$tmp/htfile")
  [[ $line == 'lab-admin:$2y$'* ]] || { echo "FAIL: generated htpasswd line is not lab-admin:\$2y\$... (got '${line:0:16}')"; fail=1; }
  printf '%s' "${line#lab-admin:}" | python3 -c '
import bcrypt, sys
h = sys.stdin.read().strip(); h = "$2b$" + h[4:]
sys.exit(0 if bcrypt.checkpw(b"x", h.encode()) else 1)' || { echo "FAIL: generated hash does not verify the password"; fail=1; }
  printf '%s' "${line#lab-admin:}" | python3 -c '
import bcrypt, sys
h = sys.stdin.read().strip(); h = "$2b$" + h[4:]
sys.exit(1 if bcrypt.checkpw(b"wrong", h.encode()) else 0)' || { echo "FAIL: generated hash accepts a wrong password"; fail=1; }
fi
# A user name with regex or htpasswd metacharacters is refused before anything is written.
: > "$tmp/patches"; : > "$tmp/log"; echo '{"spec":{}}' > "$tmp/state"
PATH="$tmp:$PATH" OC_LOG="$tmp/log" OC_PATCHES="$tmp/patches" OC_STATE="$tmp/state" OC_MODE=ok LAB_USER='lab.*' LAB_USER_PASSWORD=x \
  bash "$here/../../components/lab-prereqs/files/participant-user.sh" >/dev/null 2>&1 && { echo "FAIL: accepted user name lab.*"; fail=1; }
[[ -s $tmp/log ]] && { echo "FAIL: called oc for a refused user name"; fail=1; }
[[ $fail == 0 ]] && echo PASS
exit $fail
