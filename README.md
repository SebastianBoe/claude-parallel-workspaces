# Parallel Claude Code workspaces with shared hardware and shared memory

A workflow for running **several Claude Code agents in parallel against the same repo**,
alongside your own manual work, when:

- editing the same working tree from multiple agents (or you + an agent) causes collisions —
  stomped file edits, confused git state, "who's touching this file right now?"
- verification needs a **scarce physical resource** (a dev kit, a test rig, a GPU, whatever) that
  only one agent/human can use at a time
- you want standing personal instructions (e.g. *"always verify on real hardware before calling
  something done"*) to apply to every agent automatically, without copy-pasting them into every
  project's own `CLAUDE.md`
- Claude Code's memory is scoped **per project** (keyed by working directory), so several
  workspaces of the same repo end up with disconnected memories — an agent that learns *"here's
  how you recover a bricked dev board"* in one workspace doesn't share that lesson with the other
  two

If any of that sounds familiar: point your Claude Code at this repo and ask it to set things up
as described below.

## The four pieces

1. **Several sibling workspaces**, each a full checkout of the repo you're working on:
   ```
   ~/r/0
   ~/r/1
   ~/r/2
   ```
   Each agent (or you, doing manual work) is started from one specific workspace and stays there
   for the session. This is what actually buys the "working peace" — two agents editing
   `~/r/0` and `~/r/1` never see each other's uncommitted changes or fight over the index/HEAD.
   Pick the number of workspaces to match how much parallelism you actually want; more workspaces
   than you have hands/agents to run in them is just wasted disk.

2. **One shared `CLAUDE.md` above all the workspaces** — `~/r/CLAUDE.md`. Claude Code loads
   `CLAUDE.md` hierarchically from the session's working directory upward, so a file placed above
   `~/r/0`, `~/r/1`, `~/r/2` is automatically in context for **every session and subagent started
   anywhere underneath**, without needing to duplicate it into each workspace or each project's own
   `CLAUDE.md`. This is the right place for your standing, cross-project instructions — see
   [`examples/root-CLAUDE.md`](examples/root-CLAUDE.md) for a real one (hardware-verification
   policy + the board-allocation rule below).

3. **A static allocation table for scarce shared hardware** — [`scripts/dk`](scripts/dk). Each
   physical resource (keyed by, e.g., a J-Link serial) is assigned to a named *owner* — a
   workspace/agent, or `debug` for your own interactive use — in a small hand-editable config
   file. Before touching the hardware, a workspace/agent resolves its own owner name to the exact
   id it's allowed to use, so two workspaces never accidentally grab the same physical board. This
   turns "two agents fighting over one board" into "the second agent waits or asks," which is a
   much better failure mode. See "Setup" below for adapting it to your own hardware.

4. **Shared memory across workspaces**, via a symlink. Claude Code's own memory files live under
   `~/.claude/projects/<hash-of-the-workspace-path>/memory/` — one store per distinct working
   directory. With three sibling workspaces you'd otherwise get three unconnected memory stores.
   Making the `memory/` directories of workspace 1 and 2 symlinks to workspace 0's turns them into
   one shared store: a lesson learned by an agent in any workspace becomes visible to agents in all
   of them, from then on.

None of this is specific to embedded/hardware work — swap "dev kit" for whatever scarce resource
you're actually contending over (a GPU, a staging environment, a license seat, a single physical
test rig) and the same four pieces apply.

## Setup

Ask your Claude Code session to do this for you — it's written as concrete steps precisely so an
agent can follow it directly. Replace `~/r/N` and the dev-kit specifics with your own paths and
hardware.

1. **Create the sibling workspaces.** For a plain git repo, `git worktree` is lighter than N full
   clones (one object store, N working trees):
   ```
   git clone <repo-url> ~/r/0/<repo>
   git -C ~/r/0/<repo> worktree add ~/r/1/<repo>
   git -C ~/r/0/<repo> worktree add ~/r/2/<repo>
   ```
   If your project is a multi-repo workspace (e.g. Zephyr/west, or anything where each workspace
   needs its own resolved dependency tree), use N independent clones/inits instead — heavier, but
   each workspace's dependencies are then genuinely isolated too, which can be a feature rather
   than a cost.

2. **Add the shared `CLAUDE.md`.** Copy [`examples/root-CLAUDE.md`](examples/root-CLAUDE.md) to
   `~/r/CLAUDE.md` and edit it to say what *you* want every agent to always do (or never do). Keep
   it short — this file loads into every single session under `~/r/`, so put only the instructions
   that genuinely apply everywhere; project-specific detail belongs in each workspace's own
   `CLAUDE.md` instead.

3. **Install the allocation tool.** Copy [`scripts/dk`](scripts/dk) somewhere on `PATH` (e.g.
   `~/.local/bin/dk`, `chmod +x`; it's a standalone Python 3 script, stdlib only — no bash-isms to
   adapt). It reads/writes a TOML config, default `~/.config/nrf-dk/boards.toml` (override with
   `NRF_DK_CONFIG`), where each `[[board]]` maps a serial to an owner string. Seed it once per
   resource:
   ```
   dk allocate <serial-or-substring> agent:0   # -> workspace ~/r/0
   dk allocate <serial-or-substring> agent:1   # -> workspace ~/r/1
   dk allocate <serial-or-substring> debug     # -> your own interactive use
   ```
   `dk list` shows connected devices via `nrfutil device list --json`; if your hardware isn't a
   Nordic DK, swap `list_connected()` in the script for whatever inventory command your own
   hardware exposes.

4. **Merge and symlink memory.** Do this in two steps, in order — don't skip straight to
   symlinking if the workspaces already have their own accumulated memory, or you'll silently lose
   whichever store you don't keep.
   - **Merge first.** Ask Claude to read the `memory/` directory for each workspace (find them
     under `~/.claude/projects/` — one subdirectory per distinct workspace path Claude Code has
     been run from) and fold any memories that exist in one workspace's store but not another's
     into a single canonical set, dropping true duplicates and fixing anything written in a way
     that assumed it was the only workspace (e.g. a hardcoded path to *this* workspace, when the
     fact actually applies to all of them). This step needs judgement, which is why it's "ask
     Claude to do it," not a script.
   - **Then symlink.** Once one workspace's `memory/` directory holds the merged, canonical set,
     run [`scripts/symlink-memories.sh`](scripts/symlink-memories.sh) to back up and replace the
     others with symlinks to it:
     ```
     ./scripts/symlink-memories.sh <canonical-memory-dir> <other-memory-dir> [<other-memory-dir> ...]
     ```
     From then on, a memory saved from *any* workspace is visible from all of them.

## Day to day

- Start each agent (or your own interactive session) from one specific `~/r/N`, and let it stay
  there for the session — don't `cd` between workspaces mid-session (see "Things that don't work
  the way you'd expect" below for why).
- Before touching the shared hardware: `dk resolve <owner>` to get the exact id allocated to this
  workspace/agent, and pass *that exact id* to whatever command actually drives the hardware.
  Never let a tool auto-pick "the first" device when more than one is connected.
- `dk list` any time you want to see the whole picture: what's allocated to whom, and what's
  actually connected right now. `dk who <serial>` looks up an allocation the other direction;
  `dk allocate`/`dk free` change one.
- Allocation here is **static**, not a per-task lease: an owner keeps "their" board until someone
  explicitly re-`allocate`s it elsewhere. If the board you need is allocated to someone else, wait
  or ask — don't reassign another workspace's hardware out from under it.

## Things that don't work the way you'd expect

- **A session's `CLAUDE.md` context is resolved once, from the working directory it started in.**
  Don't try to collapse this into "one agent, dynamically `cd`s into whichever workspace it's
  leased" — the hierarchical `CLAUDE.md` loading (piece #2 above) is resolved at session start
  from the starting directory, not re-evaluated if the agent changes directory mid-session. Keep
  workspace identity == starting directory, fixed for the session; that's simpler and matches how
  the tool actually works.
- **Memory is just files.** The symlink trick (piece #4) works because Claude Code's memory system
  has no server component to get confused by two paths resolving to the same inode — it's plain
  file reads/writes. If a future version of your agentic tool moves memory into something other
  than flat files, this specific trick may need revisiting; the *goal* (one shared knowledge store
  across workspaces) still stands regardless of the mechanism.
- **An allocation table only helps if everything agrees to use it.** `dk`'s config is a
  hand-editable table, not a lock — nothing stops a command that ignores it and grabs a device
  directly. The discipline of "always resolve by owner first, always pass the exact id back" has
  to be a standing instruction (piece #2), not something the tool can enforce by itself.
