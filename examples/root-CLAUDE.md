# Workspace tree policy (`~/r/`)

This file sits above every workspace under `~/r/` (`0/`, `1/`, `2/`, …). Claude Code loads
`CLAUDE.md` hierarchically from the session cwd upward, so anything here is in context for
**every session and subagent started anywhere under `~/r/`**, not just one workspace.

This is an example — copy it to `~/r/CLAUDE.md` and replace the two sections below with whatever
standing instructions actually matter to you. Keep it short: this file loads into every session
under `~/r/`, so only put things that genuinely apply to all of them here. Project-specific detail
(build commands, board quirks, architecture decisions) belongs in each workspace's own
`CLAUDE.md`, not here.

## Hardware verification is mandatory

- **A task is not "done" until it has been verified on real hardware.** Build-passing,
  compile-checked, or simulator-only results are *in progress*, never finished. State HW
  results plainly (board serial + pass/fail); if HW verification was skipped, say so and treat
  the task as unfinished.

## Lease hardware dynamically with `dk`

- **Claim a board only for the duration of the verification, then release it.** Do not hold a
  lease across tasks or park one "just in case" — boards are shared across the sibling
  workspaces.
  - `dk status` / `dk which` — see what's available / what this workspace holds.
  - `dk claim [<serial>]` — lease a board for the HW run.
  - `dk release` — hand it back **as soon as the verification is done**, including on failure.
- If no board is free, wait or ask — do not fabricate a HW result.
