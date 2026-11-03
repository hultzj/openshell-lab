#!/usr/bin/env bash
# Facilitator prerequisite: create the participant's OpenShift user (htpasswd identity provider)
# and grant it cluster-admin, which the lab needs (CRD, cluster-scoped HelmChartRepository,
# Keycloak admin secret). The password comes from LAB_USER_PASSWORD and never enters git.
# Re-runnable: it replaces the htpasswd secret and adds the identity provider only once.
set -euo pipefail

LAB_USER=${LAB_USER:-lab-admin}
IDP_NAME=openshell-lab-htpasswd
SECRET=openshell-lab-htpasswd
: "${LAB_USER_PASSWORD:?set LAB_USER_PASSWORD (for example from a local file, never from git)}"
command -v htpasswd >/dev/null || { echo "htpasswd is required" >&2; exit 1; }

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
# Password on stdin, not argv, so it never shows in the process list.
printf '%s\n' "$LAB_USER_PASSWORD" | htpasswd -iBc "$tmp" "$LAB_USER" 2>/dev/null
oc create secret generic "$SECRET" -n openshift-config --from-file=htpasswd="$tmp" \
  --dry-run=client -o yaml | oc apply -f -

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
