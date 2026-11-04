#!/usr/bin/env bash
# Create the participant's OpenShift user (htpasswd identity provider) and grant it cluster-admin,
# which the lab needs (CRD, cluster-scoped HelmChartRepository, Keycloak admin secret).
# The password comes from LAB_USER_PASSWORD and never enters git. Runs in the lab-prereqs Job
# (GitOps) or from a facilitator shell. Re-runnable: it leaves an htpasswd secret that already
# matches alone (rewriting it restarts the OAuth server) and adds the identity provider only once.
set -euo pipefail

LAB_USER=${LAB_USER:-lab-admin}
IDP_NAME=openshell-lab-htpasswd
SECRET=openshell-lab-htpasswd
: "${LAB_USER_PASSWORD:?set LAB_USER_PASSWORD (for example from a local file, never from git)}"
# An OpenShift user name that is also safe in htpasswd and RBAC: lowercase letters, digits, hyphens.
[[ $LAB_USER =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || { echo "LAB_USER must be lowercase letters, digits and hyphens" >&2; exit 1; }
have_bcrypt() { python3 -c 'import bcrypt' 2>/dev/null; }
command -v htpasswd >/dev/null || have_bcrypt || { echo "htpasswd or python3-bcrypt is required" >&2; exit 1; }

# Keep a secret that already holds this user with this password.
current=$(oc get secret "$SECRET" -n openshift-config -o jsonpath='{.data.htpasswd}' --ignore-not-found | base64 -d 2>/dev/null || true)
matches=false
if [[ -n $current ]] && have_bcrypt; then
  LINE=$(awk -F: -v u="$LAB_USER" '$1 == u { print; exit }' <<<"$current")
  # Password and hash go in on stdin, never on the command line.
  if [[ -n $LINE ]] && printf '%s\n%s\n' "$LAB_USER_PASSWORD" "${LINE#*:}" | python3 -c '
import bcrypt, sys
pw, h = sys.stdin.read().split("\n")[:2]
h = "$2b$" + h[4:] if h[:4] in ("$2y$", "$2a$") else h
sys.exit(0 if bcrypt.checkpw(pw.encode(), h.encode()) else 1)' 2>/dev/null; then matches=true; fi
fi

if [[ $matches == true ]]; then
  echo "htpasswd secret $SECRET already matches; leaving it unchanged"
else
  tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
  if command -v htpasswd >/dev/null; then
    # Password on stdin, not argv, so it never shows in the process list.
    printf '%s\n' "$LAB_USER_PASSWORD" | htpasswd -iBc "$tmp" "$LAB_USER" 2>/dev/null
  else
    # bcrypt writes $2b$; the OpenShift OAuth server accepts the same hash under the $2y$ prefix htpasswd uses.
    printf '%s' "$LAB_USER_PASSWORD" | python3 -c '
import bcrypt, sys
h = bcrypt.hashpw(sys.stdin.read().encode(), bcrypt.gensalt(rounds=10)).decode()
print(sys.argv[1] + ":$2y$" + h[4:])' "$LAB_USER" > "$tmp"
  fi
  oc create secret generic "$SECRET" -n openshift-config --from-file=htpasswd="$tmp" \
    --dry-run=client -o yaml | oc apply -f -
fi

# Append the identity provider without touching any provider the cluster already has. Read the OAuth
# config once: if that read fails, set -e stops here instead of treating "unknown" as "no providers".
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
oauth=$(oc get oauth cluster -o json)
if ! jq -e --arg n "$IDP_NAME" '(.spec.identityProviders // []) | any(.name == $n)' <<<"$oauth" >/dev/null; then
  idp=$(jq -cn --arg n "$IDP_NAME" --arg s "$SECRET" '{name:$n, mappingMethod:"claim", type:"HTPasswd", htpasswd:{fileData:{name:$s}}}')
  if jq -e '.spec.identityProviders | type == "array"' <<<"$oauth" >/dev/null; then
    oc patch oauth cluster --type=json -p "[{\"op\":\"add\",\"path\":\"/spec/identityProviders/-\",\"value\":$idp}]"
  else
    oc patch oauth cluster --type=json -p "[{\"op\":\"add\",\"path\":\"/spec/identityProviders\",\"value\":[$idp]}]"
  fi
fi

oc adm policy add-cluster-role-to-user cluster-admin "$LAB_USER" --rolebinding-name=openshell-lab-participant >/dev/null
echo "participant user $LAB_USER: identity provider $IDP_NAME, cluster-admin via openshell-lab-participant"
