# openshell-lab

A Showroom lab: run the Pi AI coding agent in an NVIDIA OpenShell sandbox on OpenShift with the
[Zero Trust Validated Pattern](https://github.com/validatedpatterns/layered-zero-trust), and prove what the
agent cannot do: unapproved egress, writes outside its working directory, and access to its LLM API key.

Rebuilt from [avijra/openshell-ztm-lab](https://avijra.github.io/openshell-ztm-lab/), with every step re-run
on a live single-node OpenShift 4.22 cluster and short videos recorded from that run.

## Layout

| Path | What it is |
|---|---|
| `Chart.yaml`, `values.yaml`, `templates/` | The RHDP field-content chart (repo root): one child Application per component |
| `components/` | `ztvp` (patterns operator, Pattern, in-cluster secret loading), `lab-prereqs` (Web Terminal, participant user, RHDP userinfo) |
| `content/` | The Antora guide (AsciiDoc pages, screenshots, videos) |
| `automation/` | `make bootstrap`, `make verify`, `make teardown` for clusters without an RHDP order |
| `cluster/install-config.example.yaml` | The verified single-node install config, with the pull secret and SSH key left as placeholders |
| `PLAN.md` | Intake decisions, verified versions, and what the live pass found |

## Deploy

**RHDP:** order the Field Content CI with *GitOps Repo* `https://github.com/hultzj/openshell-lab`, *GitOps
Revision* `field-automation`, and *GitOps Path* `.` (an empty path makes Argo CD reject the Application). The chart installs the Zero Trust Validated Pattern, the
Web Terminal, the participant user and the Showroom guide.

**Any other cluster:** `make -C automation bootstrap ZTVP=true` (or `ZTVP=false` where the pattern already runs),
then `make -C automation verify`. Details in the Facilitator Guide (`content/modules/ROOT/pages/92-facilitator-guide.adoc`).

## Build the guide locally

```bash
npm ci && npm run build && bash scripts/check-lab.sh
```

No credentials live in this repository. Passwords and API keys come from environment variables or are typed
by the participant, and `gitleaks` runs in the review gate.
