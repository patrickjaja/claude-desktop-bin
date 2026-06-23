## New upstream version detected

| | Version |
|---|---|
| **Upstream** | `{{UPSTREAM}}` |
| **Current (`.upstream-version`)** | `{{TRACKED}}` |

---

## How to pick this up

1. Clone this repo and `cd` into it:
   ```
   git clone https://github.com/{{REPO}}.git && cd claude-desktop-bin
   ```
2. Start **Claude Code** in the project (`claude`).
3. Add the sibling daemon repo so the skill can check the cowork RPC cross-dependency:
   ```
   /add-dir ../claude-cowork-service
   ```
   (clone [claude-cowork-service](https://github.com/patrickjaja/claude-cowork-service) next to this repo first if you don't have it).
4. Run the update skill from inside this project:
   ```
   /update {{UPSTREAM}}
   ```

That's it. The skill drives the whole release: it re-builds against the new upstream msix, fixes any patches the re-minify broke, then runs the analysis (new platform gates, feature flags, ion-dist, platform-gate re-audit, `claude-cowork-service` cross-dependency), updates the docs, bumps `.upstream-version`, and ends with `/deploy`.

**What you're checking for, in one line:** did anything new arrive that should be made Linux-compatible, and does existing Linux functionality still work? The skill surfaces both - you decide what (if anything) needs a new patch.

Closing this issue: bumping `.upstream-version` to `{{UPSTREAM}}` (the skill does this) is what closes it and greens the README badge. `version-check.yml` recreates the issue every 2h until upstream `.latest` matches that file.

---

<details><summary>No Claude Code? Manual prompt / fallback</summary>

```
{{CC_PROMPT}}
```

Full reference: [update-prompt.md](https://github.com/{{REPO}}/blob/master/update-prompt.md) · [CLAUDE.md](https://github.com/{{REPO}}/blob/master/CLAUDE.md) (architecture + distro/session support tables).

</details>

---
*Auto-detected by [version-check workflow](https://github.com/{{REPO}}/actions/workflows/version-check.yml)*
