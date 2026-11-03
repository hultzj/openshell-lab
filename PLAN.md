# OpenShell on Zero Trust lab plan

Working document. Not rendered by Antora.

Source lab rebuilt here: https://avijra.github.io/openshell-ztm-lab/ (docsify, repo avijra/openshell-ztm-lab).

## Intake

- Audience and the customer question: platform and security engineers asking
  "Can we let an autonomous AI coding agent run on OpenShift without it being able
  to exfiltrate data, read secrets, or leak our LLM API key?"
- Products and pinned versions (verified live, see "Verified versions" below):
  OpenShift 4.22.11 (Single Node), Zero Trust Validated Pattern (validatedpatterns/layered-zero-trust),
  NVIDIA OpenShell 0.1.6 via chart `openshell-ztm-demo` (avijra/openshell-ztm-demo-chart), Pi agent image `ghcr.io/avijra/pi-sandbox:v1.0`.
- Tracks and time budget: one track, about 50 minutes.
- Where: pre-existing cluster (facilitator-built SNO on AWS, `make -C automation bootstrap`).
- Who builds the stack: ZTVP is a facilitator prerequisite (pattern.sh). The lab chart deploys Showroom and
  the Web Terminal operator. Participants install OpenShell themselves (Helm chart from the catalog).
- Tenancy: dedicated cluster per participant.
- Participant identity: their own cluster-admin OpenShift user (the lab installs a CRD and a
  cluster-scoped HelmChartRepository, and reads the Keycloak admin secret). Showroom terminal **off**;
  participants use the OpenShift Console Web Terminal.
- Test cluster: `sno-ztm.sandbox3022.opentlc.com` (m6i.8xlarge, us-east-2a). Repo: https://github.com/hultzj/openshell-lab

## Changes from the source lab

- Bastion + SSH replaced by the OpenShift Web Terminal (no bastion on this SNO).
- Config bar replaced by Showroom attributes (`cluster_domain` from user_data); the MAAS key is typed into the
  participant's own shell, never into the guide.
- Each step gets an observed `Expected result:` and a negative control.
- Video sections recorded from the live pass for the GUI install, the Pi agent run, the network denials and the live policy update.

## Lab map

| Module | Outcome | Time |
|---|---|---|
| 1. Deploy OpenShell from the catalog | Chart repo registered, release installed, sandbox Running | 8 min |
| 2. Connect the OpenShell CLI | `openshell sandbox list` shows `pi-agent-demo` Ready | 3 min |
| 3. AI agent coding with Pi | Pi generates and runs code through MAAS | 6 min |
| 4. Network zero trust | Allowed hosts answer; others refused | 5 min |
| 5. Filesystem zero trust | Landlock allows /sandbox and /tmp only | 5 min |
| 6. Credential security | Sandbox sees only a resolver token | 5 min |
| 7. ZTVP integration | Vault, ESO, SPIRE, ACS, Keycloak wiring observed | 6 min |
| 8. User authentication | Keycloak JWT for the gateway client | 6 min |
| 9. Dynamic policy | Allow and revoke pypi.org live | 4 min |

## Verified versions (live pass 2026-11-03)

- OpenShift 4.22.11 SNO, m6i.8xlarge, us-east-2a; console perspectives *Core platform* / *Fleet Management* (ACM).
- ZTVP layered-zero-trust main @ 10e37e5; 15 Argo CD apps Synced/Healthy in vp-gitops.
- Operators: web-terminal.v1.17.2 (fast), devworkspace-operator.v1.0.0, rhacs-operator.v4.11.6,
  openshift-external-secrets-operator.v1.2.1, openshift-gitops-operator.v1.21.6, patterns-operator.v0.0.82.
- Chart openshell-ztm-demo 1.3.6 (app 0.1.6), OpenShell CLI v0.1.6 (musl x86_64), Pi 1.4.0, MaaS model qwen36-35b-a3b.
- Every guide block run verbatim in the Web Terminal as lab-admin; outputs in evidence/ (gitignored).

## Findings from the live pass (all reflected in the guide)

- Chart default OIDC issuer points at the author's ROSA cluster; gateway crash-loops on this cluster's Keycloak
  without the ingress CA -> set issuer + oidc.caConfigMapName.
- Keycloak tokens carry no `aud`; gateway rejects with `Missing required claim: aud` -> audience mapper exercise.
- `gateway add --oidc-issuer` starts a browser login that cannot complete in a Web Terminal -> OPENSHELL_NO_BROWSER=1.
- `openshell sandbox exec` forwards stdin and swallows pasted lines -> `< /dev/null` on every exec.
- `read -rs` in a pasted block eats the next line -> key prompt in its own block.
- Chart installer Job creates Vault role openshell-admin bound to SA `*` with delete rights -> shown in Module 7.
- Chart ClusterSPIFFEID class `openshift` is ignored by ZTWIM; ZTVP default issues per-SA IDs; no pod mounts SVIDs.
- /etc and /usr denials are also explained by file ownership -> /var/tmp vs /tmp comparison proves Landlock.
- Web Terminal: no python3 (use jq), home wiped on restart, 10-minute OAuth inactivity timeout (Compliance Operator).
- HelmChartRepository has no status on 4.22.
