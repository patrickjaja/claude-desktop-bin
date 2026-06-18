---
name: deploy
description: Trigger the claude-desktop-bin Build & Release GitHub Actions pipeline (build-and-release.yml). Default run does not force; "/deploy force" sets force_rebuild=true to release even when the upstream version is unchanged (bumps pkgrel).
disable-model-invocation: true
argument-hint: "[force]"
allowed-tools: Bash(gh workflow run *), Bash(gh run list *), Bash(gh run view *), Bash(gh workflow view *)
---

# Deploy - trigger Build & Release

Args: `$ARGUMENTS` (only the literal word `force` is meaningful; anything else → non-force run).

## Context
- Repo: `patrickjaja/claude-desktop-bin` · Workflow: `build-and-release.yml` · default branch: `master`.
- Current branch: !`git -C /home/patrickjaja/development/claude-desktop-bin branch --show-current`
- Tracked upstream version: !`cat /home/patrickjaja/development/claude-desktop-bin/.upstream-version 2>/dev/null`
- Recent runs: !`gh -R patrickjaja/claude-desktop-bin run list --workflow=build-and-release.yml --limit 3 2>/dev/null || echo "(gh not ready)"`

The workflow has one `workflow_dispatch` input: `force_rebuild` (boolean, default false). `workflow_dispatch` always runs the full pipeline (build → package deb/rpm/appimage/pkgbuild/nix → release → deploy-rpm-repo → deploy-pages). `force_rebuild=true` releases even if upstream is unchanged (bumps pkgrel for patch/feature-only updates).

## Steps
1. Decide force: if `$ARGUMENTS` (trimmed, lowercased) equals `force` → `FORCE=true`, else `FORCE=false`.
2. Print a one-line plan: "Triggering build-and-release.yml on `master` (force_rebuild=<FORCE>)". (The pipeline ignores branch for dispatch; it builds against the latest upstream msix and the committed tree on the default branch.)
3. Fire it (no interactive confirmation - the user already typed /deploy):
   ```bash
   gh -R patrickjaja/claude-desktop-bin workflow run build-and-release.yml -f force_rebuild=<FORCE>
   ```
4. Wait ~3s, then resolve the run and report its URL:
   ```bash
   gh -R patrickjaja/claude-desktop-bin run list --workflow=build-and-release.yml --limit 1 \
     --json databaseId,url,status,event,createdAt
   ```
   Report the run URL and status. Offer: "Watch with `gh -R patrickjaja/claude-desktop-bin run watch <id>`".

## Notes
- Non-force is the default and is correct for a normal new-upstream release (after `.upstream-version` was bumped). Use `force` for patch/feature changes where upstream version did not move.
- Do NOT bump versions or edit files here - this only triggers the pipeline. Version/patch work belongs in `/update`.
- If `gh workflow run` errors with "Workflow does not have 'workflow_dispatch'" it's a permissions/branch issue - confirm the workflow file on `master` still declares `workflow_dispatch`.
