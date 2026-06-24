# Repo Security Audit — 2026-06-24

Generated for the `PeterBlenessy` org against the checks in
[`scripts/security-audit.sh`](../scripts/security-audit.sh). Checklist +
remediation recipes: [`docs/security-audit-checklist.md`](../docs/security-audit-checklist.md).

> Methodology note: this run was compiled from the GitHub API (branch state) and
> static analysis of each repo's `.github/workflows/` + `git log` signing state.
> Admin-scoped checks (secret age, default-token policy, branch-protection
> sub-config) are marked **Not assessed** below — re-run the script with an
> admin token to fill those in. Reproduce with:
> `scripts/security-audit.sh PeterBlenessy/airlocked-agents PeterBlenessy/notesage PeterBlenessy/openscans`

**Repositories scanned (3):** `PeterBlenessy/airlocked-agents` `PeterBlenessy/notesage` `PeterBlenessy/openscans`

| Severity | Count |
| --- | --- |
| 🔴 Critical | 0 |
| 🟠 High | 2 |
| 🟡 Medium | 5 |
| 🔵 Low | 5 |
| ⚪ Info | 0 |
| **Total** | **12** |

## Prioritized findings

### 🟠 High

1. **[`PeterBlenessy/openscans`] Default branch `main` has NO branch protection rule**  
   - _Check:_ `branch-protection`  
   - _Fix here:_ https://github.com/PeterBlenessy/openscans/settings/branches  
   - _Remediation:_ Add a protection rule for `main`: require a PR before merge, ≥1 approval, status checks, signed commits; block force-push + deletion; include administrators. (Confirmed live: `main` reports `protected: false`, while every other repo's `main` is protected.)

2. **[`PeterBlenessy/notesage`] `aw-ci-repair.yml`: `workflow_run` checks out the triggering head branch AND uses secrets**  
   - _Check:_ `risky-trigger`  
   - _Fix here:_ https://github.com/PeterBlenessy/notesage/blob/HEAD/.github/workflows/aw-ci-repair.yml#L4  
   - _Remediation:_ The job triggers on `workflow_run` of "Tests", checks out `${{ github.event.workflow_run.head_branch }}` (an attacker-influenceable `claude/*` branch) with `fetch-depth: 0`, and hands `secrets.WORKFLOW_PAT` + `secrets.CLAUDE_CODE_OAUTH_TOKEN` to `claude-code-action`. Treat the head branch as untrusted: pin the checkout to a trusted base SHA for any privileged step, keep secrets out of steps that process head-branch content, and add an explicit minimal `permissions:` block (this workflow has none — see Medium #1).

### 🟡 Medium

1. **[`PeterBlenessy/notesage`] `aw-ci-repair.yml`: no `permissions:` block — GITHUB_TOKEN inherits the repo/org default**  
   - _Check:_ `github-token`  
   - _Fix here:_ https://github.com/PeterBlenessy/notesage/blob/HEAD/.github/workflows/aw-ci-repair.yml#L1  
   - _Remediation:_ Add a least-privilege top-level `permissions:` block (e.g. `contents: read`) and widen only the specific scope the repair job needs. Especially important here because it runs in the privileged `workflow_run` context (High #2).

2. **[`PeterBlenessy/notesage`] `test.yml`: no `permissions:` block — GITHUB_TOKEN inherits the repo/org default**  
   - _Check:_ `github-token`  
   - _Fix here:_ https://github.com/PeterBlenessy/notesage/blob/HEAD/.github/workflows/test.yml#L1  
   - _Remediation:_ Add `permissions: { contents: read }` at the top; this is a pure test job and needs nothing more.

3. **[`PeterBlenessy/notesage`] `test-perf-e2e.yml`: no `permissions:` block — GITHUB_TOKEN inherits the repo/org default**  
   - _Check:_ `github-token`  
   - _Fix here:_ https://github.com/PeterBlenessy/notesage/blob/HEAD/.github/workflows/test-perf-e2e.yml#L1  
   - _Remediation:_ Add a `contents: read` top-level `permissions:` block.

4. **[`PeterBlenessy/notesage`] `smoke-agent-install.yml`: no `permissions:` block — GITHUB_TOKEN inherits the repo/org default**  
   - _Check:_ `github-token`  
   - _Fix here:_ https://github.com/PeterBlenessy/notesage/blob/HEAD/.github/workflows/smoke-agent-install.yml#L1  
   - _Remediation:_ Add a `contents: read` top-level `permissions:` block.

5. **[`PeterBlenessy/airlocked-agents`] `ci.yml`: no `permissions:` block — GITHUB_TOKEN inherits the repo/org default**  
   - _Check:_ `github-token`  
   - _Fix here:_ https://github.com/PeterBlenessy/airlocked-agents/blob/HEAD/.github/workflows/ci.yml#L1  
   - _Remediation:_ Add `permissions: { contents: read }` at the top of the validation workflow.

### 🔵 Low

1. **[`PeterBlenessy/notesage`] Secret `WORKFLOW_PAT` looks like a long-lived personal access token**  
   - _Check:_ `long-lived-pat`  
   - _Fix here:_ https://github.com/PeterBlenessy/notesage/settings/secrets/actions  
   - _Remediation:_ `WORKFLOW_PAT` is referenced across ~10 AW workflows (e.g. `aw-tdd.yml`, `aw-pipeline.yml`, `aw-merge.yml`, `aw-iterate.yml`, `aw-rebase.yml`) to trigger downstream workflows that `GITHUB_TOKEN` can't. Replace it with a fine-grained **GitHub App installation token** (short-lived, scoped to this repo) and set an expiry. Confirm rotation age with an admin-token run.

2. **[`PeterBlenessy/openscans`] Recent commits on `main` are unsigned/unverified**  
   - _Check:_ `gpg-signing`  
   - _Fix here:_ https://github.com/PeterBlenessy/openscans/commits/main  
   - _Remediation:_ All sampled recent commits on `main` are unsigned. Have contributors sign (GPG/SSH) and, once branch protection exists (High #1), enable "Require signed commits".

3. **[`PeterBlenessy/notesage`] Bot release commits on `main` are unsigned**  
   - _Check:_ `gpg-signing`  
   - _Fix here:_ https://github.com/PeterBlenessy/notesage/commits/main  
   - _Remediation:_ Human commits/merges are signed, but the auto-cut `chore: release …` commits land unsigned. Sign bot commits (commit via a GitHub App so the API signs them) and enable "Require signed commits" on the branch ruleset.

4. **[`PeterBlenessy/airlocked-agents`] `ci.yml`: action pinned to a moving branch ref (`@master`)**  
   - _Check:_ `action-pinning`  
   - _Fix here:_ https://github.com/PeterBlenessy/airlocked-agents/blob/HEAD/.github/workflows/ci.yml  
   - _Remediation:_ `ludeeus/action-shellcheck@master` re-runs whatever is on `master` today. Pin to a full commit SHA (or an immutable release tag) to close the supply-chain gap.

5. **[`PeterBlenessy/airlocked-agents`] Recent commits on `main` include unsigned commits**  
   - _Check:_ `gpg-signing`  
   - _Fix here:_ https://github.com/PeterBlenessy/airlocked-agents/commits/main  
   - _Remediation:_ Several recent `main` commits are unsigned. Sign commits and enable "Require signed commits" in the branch ruleset.

## Not assessed (need an admin-scoped token)

These checks are in the script but require admin on each repo; re-run
`scripts/security-audit.sh` (without `--static-only`) authenticated as an admin
to populate them:

- **Branch-protection sub-config** for `airlocked-agents` and `notesage` — both have `main` protected, but required-reviews / required-checks / enforce-admins / force-push / required-signatures detail wasn't read in this run.
- **Secret rotation age** — flags any Actions secret older than 180 days.
- **Default `GITHUB_TOKEN` policy** — `default_workflow_permissions` (read vs write) and the "Actions can approve PRs" setting, per repo.

## Notes

- Admin-scoped checks (branch protection sub-config, secrets, token policy) are skipped where the token lacks admin — absence of a finding there means *not assessed*, not *passed*.
- `gpg-signing` commit-level findings sample the latest commits; a commit shows unverified when its signer's public key isn't on GitHub.
- openscans' `ci.yml` and `release.yml` already declare least-privilege `permissions:` blocks (`contents: read` default, `contents: write` only on the release jobs) and use no risky triggers — no workflow findings there.
