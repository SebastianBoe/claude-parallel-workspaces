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
   policy + the leasing rule below).

3. **A leasing tool for scarce shared hardware** — [`scripts/dk`](scripts/dk). Any workspace/agent
   that needs the physical resource claims it first, uses the *exact* serial/id it got back, and
   releases it when done. This turns "two agents fighting over one board" into "the second agent
   waits or asks," which is a much better failure mode. See "Setup" below for adapting it to your
   own hardware.

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

3. **Install the leasing tool.** Copy [`scripts/dk`](scripts/dk) somewhere on `PATH` (e.g.
   `~/.local/bin/dk`, `chmod +x`), and edit the seeded pool near the top of the script
   (`printf '%s\n' 1051875858 1051890455 > "$POOL"`) to list your own resource ids. The script
   identifies "which workspace am I" by walking up from `$PWD` looking for a `.west` directory —
   if your repos aren't west workspaces, change `ws_root()`'s marker to `.git` (or whatever
   identifies your workspace root) so a lease binds to the right directory. See the script's own
   header comment for how the lease state works.

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
- Before touching the shared hardware: `dk claim` (or `dk claim <specific-id>` if you need a
  particular one), then always pass the exact id/serial you got back to whatever command actually
  drives the hardware. `dk release` as soon as verification is done — including on failure. Don't
  hold a lease "just in case" between tasks; it's shared, and another workspace may be waiting.
- `dk status` any time you want to see the whole pool: what's leased, to whom, and what's actually
  plugged in / reachable right now.

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
- **A leasing tool only helps if everything agrees to use it.** `dk`'s mutual exclusion is
  advisory — nothing stops a command that ignores the lease and grabs a resource directly. The
  discipline of "always claim first, always pass the exact id back" has to be a standing
  instruction (piece #2), not something the tool can enforce by itself.
