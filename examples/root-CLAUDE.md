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

## Boards are shared — resolve by owner, never grab "the first" device

- Allocation is static, not a per-task lease: check who owns a board before using it
  (`~/.config/nrf-dk/boards.toml`, or `dk list`), and coordinate with the user if the one you need
  is busy.
- `dk list` — show connected devices and their current allocation.
- `dk resolve <owner>` — get the exact serial allocated to your owner name; pass that **exact**
  serial to every command that drives the hardware.
- If no board allocated to you is connected, or the one you need is owned by someone else, wait or
  ask — do not fabricate a HW result.
