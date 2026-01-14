# AGENTS.md — Automated Plan Reviser Pro (APR)

## RULE 1 – ABSOLUTE (DO NOT EVER VIOLATE THIS)

You may NOT delete any file or directory unless I explicitly give the exact command **in this session**.

- This includes files you just created (tests, tmp files, scripts, etc.).
- You do not get to decide that something is "safe" to remove.
- If you think something should be removed, stop and ask. You must receive clear written approval **before** any deletion command is even proposed.

Treat "never delete files without permission" as a hard invariant.

---

## IRREVERSIBLE GIT & FILESYSTEM ACTIONS

Absolutely forbidden unless I give the **exact command and explicit approval** in the same message:

- `git reset --hard`
- `git clean -fd`
- `rm -rf`
- Any command that can delete or overwrite code/data

Rules:

1. If you are not 100% sure what a command will delete, do not propose or run it. Ask first.
2. Prefer safe tools: `git status`, `git diff`, `git stash`, copying to backups, etc.
3. After approval, restate the command verbatim, list what it will affect, and wait for confirmation.
4. When a destructive command is run, record in your response:
   - The exact user text authorizing it
   - The command run
   - When you ran it

If that audit trail is missing, then you must act as if the operation never happened.

---

## Project Overview

**APR (Automated Plan Reviser Pro)** is a CLI tool that automates iterative specification refinement using GPT Pro Extended Reasoning via Oracle browser automation.

### Core Concept

Like numerical optimization converging on a steady state, specification design improves through multiple iterations:

1. **Early rounds** fix major issues (security gaps, architectural flaws)
2. **Middle rounds** refine architecture and interfaces
3. **Later rounds** polish abstractions and fine-tune details

APR automates the tedious parts:
- Bundling documents (README, spec, implementation)
- Sending to GPT Pro 5.2 with Extended Reasoning
- Session management and monitoring
- Round tracking and history

---

## Bash Script Discipline

This is a **pure Bash project** (no embedded languages).

### Bash Rules

- Target **Bash 4.0+** compatibility. Use `#!/usr/bin/env bash` shebang.
- Use `set -euo pipefail` for strict error handling.
- Use ShellCheck to lint all scripts. Address all warnings at severity `warning` or higher.
- Prefer functions over inline code for reusability.
- Use meaningful variable names, avoid single letters except in loops.

### Key Patterns

- **Stream separation** — stderr for human-readable output (progress, errors), stdout for structured data.
- **XDG compliance** — Data in `~/.local/share/apr/`, cache in `~/.cache/apr/`.
- **No global `cd`** — Use absolute paths; change directory only when necessary.
- **Graceful degradation** — gum → ANSI colors, Oracle global → npx.

---

## Project Architecture

```
automated_plan_reviser_pro/
├── apr                  # Main script (~800 LOC)
├── install.sh           # Curl-bash installer
├── README.md            # Comprehensive documentation
├── AGENTS.md            # This file
├── VERSION              # Semver version file
├── LICENSE              # MIT License
├── workflows/           # Example workflow configs
│   └── fcp-example.yaml
├── templates/           # Prompt templates
│   └── standard.md
└── lib/                 # Shared functions (future)
```

### Per-Project Configuration

When APR is used in a project, it creates:

```
<project>/
└── .apr/
    ├── config.yaml           # Default workflow setting
    ├── workflows/            # Workflow definitions
    │   └── <name>.yaml
    ├── rounds/               # GPT Pro outputs
    │   └── <workflow>/
    │       └── round_N.md
    └── templates/            # Custom prompt templates
```

---

## Workflow Configuration Format

```yaml
# .apr/workflows/example.yaml

name: example
description: Example workflow for project specification

documents:
  readme: README.md
  spec: SPECIFICATION.md
  implementation: docs/implementation.md  # Optional

oracle:
  model: "5.2 Thinking"

rounds:
  output_dir: .apr/rounds/example
  impl_every_n: 4  # Auto-include implementation every 4th round

template: |
  First, read this README:
  ...
```

**Key config options:**

- `impl_every_n: N` — Automatically include implementation document every Nth round (e.g., rounds 4, 8, 12...)
- This keeps the spec grounded in implementation reality without manual `--include-impl` flags

**Run APR from your project directory** where your README, spec, and implementation files live. The `.apr/` configuration is per-project.

---

## Code Editing Discipline

- Do **not** run scripts that bulk-modify code (codemods, invented one-off scripts, giant `sed`/regex refactors).
- Large mechanical changes: break into smaller, explicit edits and review diffs.
- Subtle/complex changes: edit by hand, file-by-file, with careful reasoning.

---

## Backwards Compatibility & File Sprawl

We optimize for a clean architecture now, not backwards compatibility.

- No "compat shims" or "v2" file clones.
- When changing behavior, migrate callers and remove old code.
- New files are only for genuinely new domains that don't fit existing modules.
- The bar for adding files is very high.

---

## Console Output Design

Output stream rules:
- **stderr**: All human-readable output (progress, errors, banners, `[apr]` prefix)
- **stdout**: Only structured output when applicable

Visual design:
- Use **gum** when available for beautiful terminal UI (banners, spinners, styled text)
- Fall back to ANSI color codes when gum is unavailable
- Suppress gum in CI environments or when `APR_NO_GUM=1`

---

## Dependencies

### Required

| Package | Version | Purpose |
|---------|---------|---------|
| Bash | 4.0+ | Script runtime |
| Oracle | latest | GPT Pro browser automation |
| Node.js | 18+ | Oracle runtime |
| curl/wget | any | HTTP requests |

### Optional

| Package | Purpose |
|---------|---------|
| gum | Beautiful terminal UI |

---

## Oracle Integration

APR uses [Oracle](https://github.com/steipete/oracle) for GPT Pro browser automation.

Key Oracle features used:
- `--engine browser` — Browser automation for ChatGPT webapp
- `-m "5.2 Thinking"` — Model selection with extended reasoning
- `--browser-attachments never` — **Paste inline instead of file uploads** (more reliable)
- `--slug` — Human-readable session identifier
- `--write-output` — Save response to file
- `--notify` — Desktop notification on completion (if supported)
- `--heartbeat` — Progress updates

**Critical: Inline Pasting vs File Uploads**

APR always uses `--browser-attachments never` to paste document contents directly into the chat. This is far more reliable than file uploads because:
- File uploads can fail silently or trigger "duplicate file" errors
- File uploads can trigger "you've already uploaded this file" rejections
- Inline pasting works consistently for documents up to ~200KB

Session management:
- `oracle status` — List recent sessions
- `oracle session <slug>` — Attach to session
- `oracle session <slug> --render` — View with output

For headless/SSH environments, see README.md section on Oracle Remote Setup.

---

## Issue Tracking with bd (beads)

All issue tracking goes through **bd**. No other TODO systems.

Key invariants:

- `.beads/` is authoritative state and **must always be committed** with code changes.
- Do not edit `.beads/*.jsonl` directly; only via `bd`.

### Basics

```bash
bd ready --json                    # Check ready work
bd create "Issue title" -t task    # Create issue
bd update bd-42 --status in_progress  # Update status
bd close bd-42 --reason "Done"     # Complete issue
```

---

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - ShellCheck for bash scripts
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

---

## Quality Gates

Before committing changes to `apr` or `install.sh`:

```bash
# ShellCheck
shellcheck apr install.sh

# Syntax check
bash -n apr
bash -n install.sh
```

---

## Testing Checklist

When modifying APR:

1. [ ] `apr --help` displays correctly
2. [ ] `apr setup` wizard works (interactive)
3. [ ] `apr run 1 --dry-run` shows correct command
4. [ ] `apr status` shows Oracle sessions
5. [ ] `apr list` shows workflows
6. [ ] gum fallback works when gum unavailable
7. [ ] Oracle npx fallback works when not globally installed

---

## Common Patterns

### Adding a New Command

1. Add case to `main()` function
2. Create handler function `cmd_<name>()`
3. Add to help text
4. Test interactively

### Adding a New Option

1. Add to option parsing loop in `main()`
2. Add global variable for state
3. Document in help text
4. Pass to relevant functions

### Modifying Gum Output

1. Test with gum installed
2. Test with `APR_NO_GUM=1`
3. Test in non-TTY (pipe to file)
4. Ensure ANSI fallback matches intent

---

## Security Considerations

- APR does not store credentials
- Oracle uses browser cookies for ChatGPT auth
- Session data stored locally in `.apr/`
- No data sent to external services except ChatGPT via Oracle

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1.0 | 2026-01-12 | Self-update, NO_COLOR support, checksum verification, GitHub Actions CI/release |
| 1.0.0 | 2026-01-12 | Initial release |
