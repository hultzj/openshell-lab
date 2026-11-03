#!/usr/bin/env bash
# Facilitator readiness check: one PASS/FAIL line per lab prerequisite.
set -uo pipefail

GITOPS_NS=${GITOPS_NS:-vp-gitops}
SHOWROOM_NS=${SHOWROOM_NS:-showroom}
LAB_NS=${LAB_NS:-openshell-system}
# The parent Application name; children are named <LAB_APP>-<component>.
LAB_APP=${LAB_APP:-openshell-lab}
# Permission checks impersonate the participant user (the Showroom terminal is off).
failed=0

check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    failed=1
  fi
}

apps_synced_healthy() {
  local apps
  apps=$(oc -n "$GITOPS_NS" get applications.argoproj.io \
    -l demo.redhat.com/application=field-content \
    -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status}/{.status.health.status} {.metadata.labels.app\.kubernetes\.io/part-of}{"\n"}{end}') || return 1
  # This lab's Applications carry part-of=<LAB_APP>: the showroom child must exist, and all must be Synced/Healthy.
  awk -v app="$LAB_APP" '
    $1 != app && $3 != app { next }  # the parent by name: RHDP creates it without the label
    $1 == app { p = 1 }  # the parent: missing children or a missing parent must fail
    $1 == app "-showroom" { s = 1 }
    $2 != "Synced/Healthy" { bad = 1 }
    END { exit !(p && s && !bad) }
  ' <<<"$apps"
}

showroom_answers() {
  local host
  host=$(oc -n "$SHOWROOM_NS" get route showroom -o jsonpath='{.spec.host}') || return 1
  curl -fsk --max-time 10 -o /dev/null "https://$host"
}

# Every url: tab in ui-config.yml is an iframe: its target must answer 2xx (after redirects) and allow
# framing. A default OpenShift console sends X-Frame-Options: DENY and renders as a blank tab; RHDP
# orders embed it, elsewhere drop the tab or get the cluster owner's OK. Report-only CSP is ignored.
frameable() {
  local headers last csp
  headers=$(curl -skIL --max-time 10 "$1") || return 1
  last=$(awk '/^HTTP\// {b = ""} {b = b $0 "\n"} END {printf "%s", b}' <<<"$headers" | tr -d '\r')
  grep -qE '^HTTP/[0-9.]+ 2[0-9][0-9]' <<<"$last" || return 1
  ! grep -qi '^x-frame-options:' <<<"$last" || return 1
  # Browsers enforce every policy, so every enforced frame-ancestors directive (across headers and
  # comma-separated policies) must contain a bare * source; a scoped wildcard (https://*.x) is not enough.
  csp=$(grep -i '^content-security-policy:' <<<"$last" | cut -d: -f2- || true)  # none is fine
  tr ',;' '\n\n' <<<"$csp" |
    awk '{d = tolower($0); sub(/^[ \t]+/, "", d)} d ~ /^frame-ancestors/ && d !~ /(^| )\*( |$)/ {bad = 1} END {exit bad}'
}

check "lab Applications are Synced/Healthy" apps_synced_healthy
check "Showroom route answers" showroom_answers
ui_config="$(dirname "$0")/../ui-config.yml"
if [[ ! -r $ui_config ]]; then
  check "ui-config.yml is readable (its url: tabs are checked)" false
else
  domain=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
  for url in $(awk '{sub(/^[[:space:]]*-[[:space:]]*/, "")} $1 == "url:" {print $2}' "$ui_config" | tr -d "'\""); do
    url=$(sed "s|\${DOMAIN}|$domain|g" <<<"$url")
    check "Showroom tab $url can embed (2xx, framing allowed)" frameable "$url"
  done
fi
LAB_USER=${LAB_USER:-lab-admin}
AS_USER=(--as "$LAB_USER" --as-group system:authenticated --as-group system:authenticated:oauth)

ztvp_healthy() {
  local apps
  apps=$(oc get applications.argoproj.io -n "$GITOPS_NS" -o jsonpath='{range .items[*]}{.metadata.labels.app\.kubernetes\.io/part-of}{" "}{.status.sync.status}/{.status.health.status}{"\n"}{end}') || return 1
  # ZTVP's own applications carry no part-of label; this lab's are checked above.
  awk '$1 == "" || $1 !~ /openshell-lab/ { n++; if ($NF != "Synced/Healthy") bad = 1 } END { exit !(n > 0 && !bad) }' <<<"$(sed 's/^ /- /' <<<"$apps")"
}
csv_succeeded() { oc get csv -n openshift-operators -o jsonpath='{range .items[*]}{.metadata.name} {.status.phase}{"\n"}{end}' | grep -q "^$1.* Succeeded$"; }
idp_present() { oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}' | tr ' ' '\n' | grep -qx openshell-lab-htpasswd; }
eso_store_ready() { [[ $(oc get clustersecretstore vault-backend -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}') == True ]]; }
url_ok() { curl -fsSL --max-time 20 -r 0-0 -o /dev/null "$1"; }   # one byte: proves the object itself is served
maas_reachable() { local c; c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://maas-rhdp.apps.maas.redhatworkshops.io/v1/models"); [[ $c == 401 || $c == 200 ]]; }

check "ZTVP Argo CD applications are Synced/Healthy" ztvp_healthy
check "Vault is running" oc -n vault wait pod/vault-0 --for=condition=Ready --timeout=10s
check "ClusterSecretStore vault-backend is Ready" eso_store_ready
check "Keycloak admin secret exists" oc -n keycloak-system get secret keycloak-admin-user
check "Web Terminal operator Succeeded" csv_succeeded web-terminal
check "identity provider openshell-lab-htpasswd configured" idp_present
check "$LAB_USER can create CRDs (cluster-admin)" oc auth can-i create customresourcedefinitions "${AS_USER[@]}"
check "$LAB_USER can read the Keycloak admin secret" oc auth can-i get secrets -n keycloak-system "${AS_USER[@]}"
check "$LAB_USER can create HelmChartRepositories" oc auth can-i create helmchartrepositories.helm.openshift.io "${AS_USER[@]}"
check "chart repository index answers" url_ok https://avijra.github.io/openshell-ztm-demo-chart/index.yaml
check "OpenShell CLI release tarball answers" url_ok https://github.com/NVIDIA/OpenShell/releases/download/v0.1.6/openshell-x86_64-unknown-linux-musl.tar.gz
check "OpenShell CLI checksum file answers" url_ok https://github.com/NVIDIA/OpenShell/releases/download/v0.1.6/openshell-checksums-sha256.txt
check "MaaS endpoint answers (401 without a key is fine)" maas_reachable

exit "$failed"
