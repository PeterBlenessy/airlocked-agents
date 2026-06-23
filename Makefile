# airlocked-agents — Makefile entrypoint
# All targets are idempotent. Run `make help` for the list.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Load .env if present so targets can reference variables.
ifneq (,$(wildcard ./.env))
include .env
export
endif

ANSIBLE := ansible-playbook -i ansible/inventory.ini

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: setup
setup: ## Guided, interactive setup — checks the system, collects config, provisions (start here)
	bash scripts/setup.sh

.PHONY: doctor
doctor: ## Report what's installed/missing for a setup, then exit
	bash scripts/setup.sh --doctor

.PHONY: check-env
check-env: ## Fail early if .env is missing
	@test -f .env || { echo "Missing .env — run 'make setup' (guided) or: cp .env.example .env && edit it"; exit 1; }

.PHONY: mac
mac: check-env ## Provision the Mac: llama.cpp + tunnel proxy, Khoj, Open Interpreter, Cua (idempotent)
	$(ANSIBLE) ansible/mac.yml --limit mac

.PHONY: vps
vps: check-env ## Provision the VPS: docker, n8n, firewall, wireguard, suna clone (idempotent)
	$(ANSIBLE) ansible/vps.yml --limit vps

.PHONY: model
model: check-env ## Download the local GGUF model (multi-GB, opt-in)
	bash mac/download-model.sh

.PHONY: tunnel
tunnel: check-env ## Bring up the WireGuard Mac<->VPS tunnel
	$(ANSIBLE) ansible/vps.yml --limit vps --tags wireguard
	@echo "On the Mac, import wireguard/wg0.mac.conf (rendered) into the WireGuard app and activate it."

.PHONY: harden
harden: check-env ## Lock VPS SSH to the WireGuard tunnel (run AFTER `make tunnel` is up)
	@echo "Locking SSH (22) to the tunnel. Requires an active WireGuard handshake; aborts if not."
	$(ANSIBLE) ansible/vps.yml --limit vps --tags firewall -e ssh_hardened=true
	@echo "SSH is now tunnel-only. Set SSH_HARDENED=true in .env so future runs stay hardened"
	@echo "and management routes over VPS_TUNNEL_IP."

.PHONY: workflows
workflows: check-env ## Import the n8n workflow skeletons via the n8n CLI
	@echo "Importing n8n workflows (verify/finish them in the editor afterwards)..."
	$(ANSIBLE) ansible/vps.yml --limit vps --tags workflows

.PHONY: up
up: ## Bring the container stacks up (run inside the relevant host targets)
	@echo "Use 'make mac' and 'make vps' — Compose is managed by Ansible."

.PHONY: down
down: ## Stop the container stacks (n8n, Khoj) on their hosts
	$(ANSIBLE) ansible/vps.yml --limit vps --tags down || true
	$(ANSIBLE) ansible/mac.yml --limit mac --tags down || true

.PHONY: verify
verify: check-env ## Run health + security boundary checks
	bash scripts/verify.sh

.PHONY: repo
repo: ## Init git + create & push the GitHub repo (via gh). Usage: make repo [NAME=airlocked-agents] [VIS=private]
	bash scripts/bootstrap-repo.sh $(or $(NAME),airlocked-agents) $(or $(VIS),private)

.PHONY: lint
lint: ## Sanity-check Ansible and Compose files
	@command -v ansible-lint >/dev/null && ansible-lint ansible/*.yml || echo "ansible-lint not installed (optional)"
	@docker compose -f compose/n8n.yml config -q && echo "compose/n8n.yml OK"
	@docker compose -f compose/khoj.yml config -q && echo "compose/khoj.yml OK"
