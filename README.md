# openshell-lab

A Showroom lab: run the Pi AI coding agent in an NVIDIA OpenShell sandbox on OpenShift with the
[Zero Trust Validated Pattern](https://github.com/validatedpatterns/layered-zero-trust), and prove what the
agent cannot do: unapproved egress, writes outside its working directory, and access to its LLM API key.

Rebuilt from [avijra/openshell-ztm-lab](https://avijra.github.io/openshell-ztm-lab/), with every step re-run
on a live single-node OpenShift 4.22 cluster and short videos recorded from that run.

## Layout

| Path | What it is |
|---|---|
| `content/` | The Antora guide (AsciiDoc pages, screenshots, videos) |
| `automation/` | `make prereqs`, `make bootstrap`, `make verify`, `make teardown`; the GitOps chart Showroom is deployed from (`automation/argocd`) |
| `cluster/install-config.example.yaml` | The verified single-node install config, with the pull secret and SSH key left as placeholders |
| `PLAN.md` | Intake decisions, verified versions, and what the live pass found |

## Deploy

See the Facilitator Guide (`content/modules/ROOT/pages/92-facilitator-guide.adoc`): install ZTVP, run
`LAB_USER_PASSWORD=... make -C automation prereqs`, then `make -C automation bootstrap` and `make -C automation verify`.

## Build the guide locally

```bash
npm ci && npm run build && bash scripts/check-lab.sh
```

No credentials live in this repository. Passwords and API keys come from environment variables or are typed
by the participant, and `gitleaks` runs in the review gate.
