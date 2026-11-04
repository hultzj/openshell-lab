SHELL := /usr/bin/env bash

AUTOMATION_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_DIR := $(abspath $(AUTOMATION_DIR)/..)
# The Argo CD instance that runs the lab: openshift-gitops (RHDP, or any default GitOps install) or vp-gitops
# (a cluster where ZTVP brought its own instance). Detected when unset.
GITOPS_NS ?= $(shell oc get argocd -n openshift-gitops -o name 2>/dev/null | grep -q . && echo openshift-gitops || echo vp-gitops)
# ZTVP=true makes the chart install the Zero Trust Validated Pattern; false for clusters that already run it.
ZTVP ?= false
# WEB_TERMINAL=true|false overrides the check that keeps the lab from adopting someone else's Web Terminal Subscription.
WEB_TERMINAL ?=
# The parent Application name, from bootstrap.yaml; every namespace this lab creates carries part-of=<LAB_APP>.
LAB_APP := $(shell awk '/^metadata:/ {m = 1} m && $$1 == "name:" {print $$2; exit}' "$(AUTOMATION_DIR)/bootstrap.yaml" 2>/dev/null)
# Defaults to the revision values.yaml names, so a branch deploys itself.
REVISION ?= $(shell awk '/^gitops:/ {g = 1} g && $$1 == "revision:" {v = $$2; gsub(/["\047]/, "", v); print v; exit}' "$(REPO_DIR)/values.yaml" 2>/dev/null)
CHART_PATHS := Chart.yaml values.yaml .helmignore templates components automation

.PHONY: help bootstrap status verify teardown

help:
	@printf '%s\n' \
	  '  make bootstrap   Deploy the lab through OpenShift GitOps on a cluster without an RHDP order' \
	  '                   (ZTVP=true to install the Zero Trust Validated Pattern too; GITOPS_NS to override)' \
	  '  make status      Show sync and health of the lab Applications' \
	  '  make verify      PASS/FAIL readiness checks for class' \
	  '  make teardown    Delete the lab Applications (the ZTVP Pattern is kept)'

# bootstrap deploys exactly what Argo CD will sync: it refuses unless this checkout is the pushed
# REVISION (no local changes to the chart) and REVISION matches gitops.revision. It then guards every
# namespace a child Application deploys into (Argo CD would adopt a foreign one and teardown would delete
# it), creates each missing one with its labels, and applies the parent Application. No comments inside
# the recipe: after backslash-newline joining, a shell comment would swallow the rest of it.
bootstrap:
	@set -euo pipefail; \
	[[ "$(REVISION)" =~ ^[A-Za-z0-9._/-]+$$ ]] || { echo "REVISION '$(REVISION)' has unsafe characters" >&2; exit 1; }; \
	[[ "$(ZTVP)" == true || "$(ZTVP)" == false ]] || { echo "ZTVP must be true or false" >&2; exit 1; }; \
	vrev=$$(awk '/^gitops:/ {g = 1} g && $$1 == "revision:" {v = $$2; gsub(/["\047]/, "", v); print v; exit}' "$(REPO_DIR)/values.yaml"); \
	[[ "$$vrev" == "$(REVISION)" ]] || { echo "REVISION $(REVISION) differs from gitops.revision ($$vrev) in values.yaml; set it on that branch" >&2; exit 1; }; \
	head=$$(git -C "$(REPO_DIR)" rev-parse HEAD); \
	remote=$$(git -C "$(REPO_DIR)" ls-remote origin "refs/heads/$(REVISION)" | cut -f1); \
	if [[ -z "$$remote" || "$$remote" != "$$head" ]] || ! git -C "$(REPO_DIR)" diff --quiet HEAD -- $(CHART_PATHS) || \
	   [[ -n "$$(git -C "$(REPO_DIR)" status --porcelain --untracked-files=all -- $(CHART_PATHS))" ]]; then \
	  echo "check out the pushed $(REVISION) with no local changes to the chart: Argo CD deploys the remote" >&2; exit 1; fi; \
	domain=$$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}'); test -n "$$domain"; \
	wt="$(WEB_TERMINAL)"; [[ -n "$$wt" ]] || wt=$$(bash "$(AUTOMATION_DIR)/web-terminal-install.sh" "$(LAB_APP)"); \
	[[ "$$wt" == true ]] || echo "Web Terminal Subscription belongs to someone else: the lab will not manage it"; \
	apps=$$(helm template "$(LAB_APP)" "$(REPO_DIR)" --set deployer.domain="$$domain" --set argocd.namespace="$(GITOPS_NS)" --set ztvp.enabled="$(ZTVP)"); \
	nss=$$(awk '$$1 == "destination:" {d = 1} d && $$1 == "namespace:" {print $$2; d = 0}' <<<"$$apps" | sort -u); \
	missing=""; \
	for ns in $$nss; do \
	  state=$$(oc get namespace "$$ns" --ignore-not-found -o jsonpath='{.metadata.name}/{.metadata.labels.app\.kubernetes\.io/part-of}'); \
	  case "$$state" in "") missing="$$missing $$ns" ;; "$$ns/$(LAB_APP)") ;; \
	    *) echo "namespace $$ns exists and is not this lab's ($(LAB_APP)); on a cluster that already runs ZTVP use ZTVP=false" >&2; exit 1 ;; esac; \
	done; \
	for ns in $$nss; do \
	  case " $$missing " in \
	    *" $$ns "*) printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: %s\n  labels:\n    argocd.argoproj.io/managed-by: %s\n    app.kubernetes.io/part-of: %s\n' \
	                  "$$ns" "$(GITOPS_NS)" "$(LAB_APP)" | oc create -f - ;; \
	    *) oc label namespace "$$ns" "argocd.argoproj.io/managed-by=$(GITOPS_NS)" "app.kubernetes.io/part-of=$(LAB_APP)" --overwrite ;; \
	  esac; \
	done; \
	sed "s|DEPLOYER_DOMAIN|$$domain|; s|GIT_REVISION|$(REVISION)|g; s|GITOPS_NS|$(GITOPS_NS)|g; s|ZTVP_ENABLED|$(ZTVP)|; s|WEB_TERMINAL_INSTALL|$$wt|" "$(AUTOMATION_DIR)/bootstrap.yaml" | oc apply -f -

status:
	oc -n $(GITOPS_NS) get applications.argoproj.io -l demo.redhat.com/application=field-content

verify:
	GITOPS_NS=$(GITOPS_NS) bash "$(AUTOMATION_DIR)/verify.sh"

teardown:
	sed "s|GITOPS_NS|$(GITOPS_NS)|g" "$(AUTOMATION_DIR)/bootstrap.yaml" | oc delete -f - --ignore-not-found --wait=true
