## New upstream version detected

| | Version |
|---|---|
| **Upstream** | `{{UPSTREAM}}` |
| **Current (`.upstream-version`)** | `{{TRACKED}}` |

---

## What happens automatically

An **automatic release run** for `{{UPSTREAM}}` has been dispatched ([Build & Release](https://github.com/{{REPO}}/actions/workflows/build-and-release.yml)). Since we repackage Anthropic's official Linux `.deb` (1p Linux support), most upstream bumps need no manual work - the pipeline downloads the new `.deb`, applies all patches (every sub-patch must apply or the build fails loud), validates, smoke-tests, publishes the release, and bumps `.upstream-version`.

- **If it succeeds:** this issue is closed automatically with a comment. Nothing to do.
- **If it fails:** a comment appears below with a link to the failed run. That's the signal for manual work - see below.

## If the automatic release failed

The two likely causes, per CLAUDE.md's Patch Strictness Rules:

1. **Upstream's re-minify moved a patch anchor** → fix the regex (`[\w$]+` wildcards + capture/replace).
2. **Upstream natively implemented something we patch** → remove the patch, or convert it to a regression guard. This is the expected direction over time: Anthropic maintains 1p Linux support now, so our patch set should shrink, not grow.

To pick it up:

1. Clone this repo and `cd` into it:
   ```
   git clone https://github.com/{{REPO}}.git && cd claude-desktop-bin
   ```
2. Start **Claude Code** in the project (`claude`) and run the update skill:
   ```
   /update {{UPSTREAM}}
   ```

The skill drives the whole flow: rebuilds against the new upstream `.deb`, fixes or removes broken patches, runs the analysis (new platform gates, feature flags, ion-dist), updates the docs, bumps `.upstream-version`, and ends with `/deploy`.

Closing this issue: a successful release run closes it automatically (the release job bumps `.upstream-version`, which also stops the 2-hourly re-detection). If you handled the update fully manually, bump `.upstream-version` and close the issue yourself.

---

<details><summary>No Claude Code? Manual prompt / fallback</summary>

```
{{CC_PROMPT}}
```

Full reference: [update-prompt.md](https://github.com/{{REPO}}/blob/master/update-prompt.md) · [CLAUDE.md](https://github.com/{{REPO}}/blob/master/CLAUDE.md) (architecture + distro/session support tables).

</details>

---
*Auto-detected by [version-check workflow](https://github.com/{{REPO}}/actions/workflows/version-check.yml)*
