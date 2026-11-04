#!/usr/bin/env bash
# Run by the participant-setup Job. Generates the participant password once and keeps it in the Secret
# lab-user-credentials (a re-run reuses it), applies the user with participant-user.sh, and publishes the
# credentials in a ConfigMap labelled demo.redhat.com/userinfo, which RHDP shows on the order page.
set -euo pipefail
: "${NS:?}" "${LAB_USER:?}" "${CONSOLE_URL:?}"
PARTICIPANT_SCRIPT=${PARTICIPANT_SCRIPT:-/scripts/participant-user.sh}

PW=$(oc get secret lab-user-credentials -n "$NS" -o jsonpath='{.data.password}' --ignore-not-found | base64 -d)
if [[ -z $PW ]]; then
  PW=$(openssl rand -hex 10)
  oc create secret generic lab-user-credentials -n "$NS" --from-literal=username="$LAB_USER" --from-literal=password="$PW"
fi
LAB_USER_PASSWORD="$PW" bash "$PARTICIPANT_SCRIPT"
oc create configmap lab-user-info -n "$NS" \
  --from-literal=lab_user="$LAB_USER" --from-literal=lab_user_password="$PW" \
  --from-literal=lab_user_login="$CONSOLE_URL (identity provider openshell-lab-htpasswd)" \
  --dry-run=client -o yaml | oc label --local -f - demo.redhat.com/userinfo= -o yaml | oc apply -f -
echo "participant $LAB_USER ready"
