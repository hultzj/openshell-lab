#!/usr/bin/env bash
# Self-check for setup-participant.sh with a stub `oc` and a stub participant script: the first run generates and
# stores a password, applies it, and publishes it in a userinfo ConfigMap; a second run reuses the stored password.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
script="$here/../../components/lab-prereqs/files/setup-participant.sh"
cat > "$tmp/oc" <<'STUB'
#!/usr/bin/env bash
echo "oc $*" >> "$OC_LOG"
case "$1 $2" in
  "get secret") [[ -f $OC_STORE ]] && base64 < "$OC_STORE" ;;
  "create secret") for a in "$@"; do [[ $a == --from-literal=password=* ]] && printf '%s' "${a#--from-literal=password=}" > "$OC_STORE"; done ;;
  "create configmap") printf '%s\n' "$@" ;;   # stands in for the dry-run YAML on stdout
  "label --local") cat > "$OC_CM" ;;
  "apply -f") cat > /dev/null ;;
esac
exit 0
STUB
printf '#!/usr/bin/env bash\necho "$LAB_USER_PASSWORD" >> "$APPLIED"\n' > "$tmp/participant.sh"
chmod +x "$tmp/oc" "$tmp/participant.sh"
run() { PATH="$tmp:$PATH" OC_LOG="$tmp/log" OC_STORE="$tmp/store" OC_CM="$tmp/cm" APPLIED="$tmp/applied" \
  NS=openshell-lab LAB_USER=lab-admin CONSOLE_URL=https://console.example.com PARTICIPANT_SCRIPT="$tmp/participant.sh" \
  bash "$script" >/dev/null 2>&1; }
fail=0
run || { echo "FAIL: first run failed"; fail=1; }
pw=$(cat "$tmp/store" 2>/dev/null)
[[ $pw =~ ^[0-9a-f]{20}$ ]] || { echo "FAIL: no 20-hex-char password stored (got '$pw')"; fail=1; }
[[ $(tail -1 "$tmp/applied") == "$pw" ]] || { echo "FAIL: the stored password was not the one applied"; fail=1; }
grep -q -- "--from-literal=lab_user_password=$pw" "$tmp/cm" || { echo "FAIL: userinfo ConfigMap lacks the password"; fail=1; }
grep -q -- "lab-user-info" "$tmp/cm" || { echo "FAIL: userinfo ConfigMap not named lab-user-info"; fail=1; }
: > "$tmp/log"; run || { echo "FAIL: second run failed"; fail=1; }
grep -q "create secret" "$tmp/log" && { echo "FAIL: second run created a new password"; fail=1; }
[[ $(tail -1 "$tmp/applied") == "$pw" ]] || { echo "FAIL: second run did not reuse the stored password"; fail=1; }
[[ $fail == 0 ]] && echo PASS
exit $fail
