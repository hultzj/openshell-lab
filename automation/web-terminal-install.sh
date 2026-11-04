#!/usr/bin/env bash
# Prints "true" when the lab may manage the Web Terminal Subscription: no web-terminal Subscription exists, or every
# one that exists is already tracked by this lab's prereqs Application. Prints "false" when any other owner installed
# one, so Argo CD never adopts it (and, on teardown, deletes it). Usage: web-terminal-install.sh <parent-application-name>
set -euo pipefail
app=${1:?parent Application name}
subs=$(oc get subscriptions.operators.coreos.com -A -o json)
mine=$(jq -r --arg a "$app-prereqs" '
  [.items[] | select(.spec.name == "web-terminal")] as $wt
  | if ($wt | length) == 0 then "true"
    elif all($wt[]; (.metadata.labels["app.kubernetes.io/instance"] // "") == $a
                    or ((.metadata.annotations["argocd.argoproj.io/tracking-id"] // "") | startswith($a + ":")))
    then "true" else "false" end' <<<"$subs")
echo "$mine"
