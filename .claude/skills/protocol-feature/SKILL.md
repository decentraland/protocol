---
name: protocol-feature
description: Drives a Decentraland protocol or SDK feature through need, design, engine feasibility (unity-explorer, bevy-explorer, godot-explorer), .proto definition, cross-repo implementation (js-sdk-toolchain, the engines, test scene, docs) and review, with one resumable proposal bundle and a dry-run mode that writes only markdown. Use whenever someone wants to add or change a proto field, SDK component, enum value, restricted action, scene API or comms message, write a draft proposal, ask whether the engines can support something, pick a component id or field number or check whether one is free (make check-component-id misses open PRs and experimental-bevy), review a protocol PR across engines, or resume proposals/<slug>. Use it even if they only mention @dcl/protocol, a .proto file, experimental-bevy or "proposal".
argument-hint: "[idea | proposals/<slug>] [--draft] [--phase propose|tech-check|define|implement|review] [--size small|medium|large] [--execute] [--out <dir>]"
---

# Protocol feature process

Six phases, one bundle, two modes. The phases are need (1), design (2), technology verification (3), definition (4), implementation (5) and review (6). The **proposal bundle** (`<PROPOSAL_DIR>/<slug>/proposal.md` plus `protocol.diff`, `actions.md`, `pr-<repo>.md`, `review.md`) is the only memory between sessions; nothing lives in chat alone. **Plan mode** is the default and writes only inside the bundle; **execute mode** edits sibling repos and opens PRs, one confirmation per outward action. A **draft proposal** is plan mode through all six phases in one session, so a feature can be judged end to end before anyone touches a repo.

Why this much ceremony: scenes deployed to the world are immutable, so a field name, number or default that reaches `main` is permanent, and three engines plus the SDK implement every change by hand with their own pins and registration lists. The process exists to catch the wrong shape, the colliding number and the silently-unwired engine before they ship.

Arguments received: $ARGUMENTS

## 1. Pre-flight

Repositories found on this machine (from `scripts/find-repos.sh`; paths are discovered, never hardcoded):

!`bash "${CLAUDE_SKILL_DIR}/scripts/find-repos.sh"`

- If a repo the merge gate counts is `MISSING`, ask one question: its path, or permission to clone it with the printed command. If two protocol clones are listed, ask which one is canonical. Ask nothing else at pre-flight.
- Working trees may be stale or on feature branches. Read facts from the fetched remote branch (`git show origin/main:<path>`, `git grep <pattern> origin/main -- <dir>`; unity-explorer uses `origin/dev`) and say which branch you read. Run `bash .claude/skills/protocol-feature/scripts/find-repos.sh --fetch` when FETCH_HEAD is older than a day.
- Read `.claude/skills/protocol-feature/references/policy.md` and print the values in force in one line. Every phase quotes the value it applied in the Decision log.

## 2. Parse the request

| Signal | Effect |
|---|---|
| a free-text idea, or `--phase propose` | new bundle, start at phase 1 |
| `proposals/<slug>` or `--phase <p>` with a bundle | resume at the first gate not yet `passed`, or jump to `<p>` if its gate allows |
| `--draft`, "draft proposal", "simulate the whole thing" | plan mode through phases 1-6 in this session |
| "dry run", "simulate", "hypothetical", "don't open anything", "just markdown" | plan mode, even if `--execute` was passed |
| `--execute`, "go ahead and implement / open the PRs" | execute mode (needs a bundle at phase >= 4 before any sibling repo is edited) |
| `--out <dir>` or `PROTOCOL_FEATURE_OUT` | bundle directory override (evals and scratch runs use it) |
| a bare question ("could godot support X?") | standalone technology check: stub bundle at phase 3 |
| a PR number ("review #499") | standalone review: stub bundle at phase 6 |
| `--size` | overrides the classification below |

State the mode and the bundle path in one sentence before doing anything else. The phase skills do not see `$ARGUMENTS`; they take the bundle path and mode from that sentence.

## 3. Classify size and kind

| Change | `kind` | Size | Precedent |
|---|---|---|---|
| optional field on an existing component message, enum value, comment or default clarification | `field` / `enum-value` / `semantics` | small | #489 font_src, #470 max_camera_distance |
| optional request or response field on an existing RPC, or anything else under `proto/decentraland/kernel/apis/` | `api` | small (new RPC: medium) | #477 TeleportToRequest.realm, #444 StopEmote |
| new component, result (grow-only) component, new shared type in `sdk/components/common/` | `component` / `result-component` | medium | #474 AvatarNametag, #455 ExplorerUiEventsResult |
| rfc4 / Pulse comms, new kernel API file, semantics change of released behaviour, anything `breaks compat` | `comms` or the kind above | large | #495 skybox, #499 nearby voice |
| no protocol change needed (the field exists, or it is an engine or SDK-only change) | `none` | none | `MovePlayerToRequest.duration` already exists |

A request that needs no protocol change gets a bundle with `kind: none`, `status: rejected` and the reason, then a short engine-support answer; it never allocates a number. The tracks are described in `references/process.md`.

## 4. Create or resume the bundle

- New: copy `.claude/skills/protocol-feature/assets/proposal-template.md` to `<dir>/<slug>/proposal.md`, fill the frontmatter (`kind`, `size`, `mode`, `draft`, `component`, `owner` from `gh api user --jq .login`, dates, the `policy:` block from `references/policy.md`). Slug: kebab-case of the title, unique in the directory. Do not create a second bundle for the same component + field; resume the existing one.
- Resume: run `bash .claude/skills/protocol-feature/scripts/proposal-gate.sh status <slug>` and print its card. Read `## Decision log` before asking anything; a question it already answers is not asked again.
- Bundle directory: `PROPOSAL_DIR` from `references/policy.md` (`proposals/`) unless `--out` or `PROTOCOL_FEATURE_OUT` is set. If a write is refused (Claude Code's own plan permission mode), print the full document instead of skipping it.

## 5. Route

Run `bash .claude/skills/protocol-feature/scripts/proposal-gate.sh <proposal.md> <phase>` before entering a phase and again when leaving it. Then read the phase file and follow it; it is the authority for that phase:

| Phase | Read and follow |
|---|---|
| 1 need, 2 design | `.claude/skills/protocol-propose/SKILL.md` |
| 3 technology verification | `.claude/skills/protocol-tech-check/SKILL.md` |
| 4 definition | `.claude/skills/protocol-define/SKILL.md` |
| 5 implementation | `.claude/skills/protocol-implement/SKILL.md` |
| 6 review | `.claude/skills/protocol-review/SKILL.md` |

Small track: phases 1-4 run in one session. `--draft`: all six. Stop and show the section after design (phase 2), after the matrix (phase 3), and before any write in execute mode; otherwise continue and record decisions in the Decision log. Each phase ends by printing the next command (for example `/protocol-tech-check proposals/<slug>`).

## 6. Plan-mode contract

Allowed: `git fetch`, `git show origin/<branch>:<path>`, `git grep`, `git log`, `gh pr list/view/diff`, `gh api repos/decentraland/<repo>/contents/<path>`, reading any sibling repo, the bundled scripts, `npm view`, and scratch exports in a temporary directory (`git archive origin/main proto | tar -x -C "$(mktemp -d)"`) for `buf` or `git apply --check`. Writes: only `proposal.md`, `protocol.diff`, `actions.md`, `pr-<repo>.md`, `review.md`, `feature-description-unity.md` inside the bundle; helper scripts, scratch exports and throwaway git repos go under `mktemp -d`, never next to the bundle. Every statement about what a repo, file or pin contains comes from a command you ran in this session, not from memory or from a reference file. Not allowed: creating branches, editing sibling repos, `npm install`, `cargo`, `make` in sibling repos, `gh pr create`, `gh issue create`, comments, labels. A dry run that edits a repo is not a dry run.

## 7. Execute-mode contract

- One branch `feat/<slug>` per repo, from the fetched default branch (`dev` for unity-explorer). Refuse to switch a dirty checkout; say what is dirty.
- Run each repo's gate (listed in `actions.md`) before marking its brief done. Long gates are fine; print an estimate first.
- One confirmation question per action, with the exact command printed, never batched: `git commit`, `git push`, `gh pr create` (print the body in full first), `gh pr comment`, `gh pr edit --add-label`, `gh issue create`, overwriting snapshots or goldens, bumping a protocol pin in a repo the user did not name.
- Medium and large Unity work: write `feature-description-unity.md` in the bundle from `assets/feature-description-unity.md`, then print `cp <bundle>/feature-description-unity.md <unity>/feature-description.md && cd <unity> && claude --agent dcl-sdk-feature-architect --permission-mode plan`. That agent assumes `../protocol` siblings and never commits; its plugin snippet and the `dcl-workspace.json` step are stale (see `references/repos/unity.md`).

## 8. Branch and pin model (what "the protocol" means to each consumer)

| Consumer | Where the protocol comes from | Pin while a PR is open | After the protocol merge |
|---|---|---|---|
| js-sdk-toolchain | `@dcl/protocol` in root `package.json` and `packages/@dcl/sdk-commands/package.json` (exact version) | the PR tarball URL in both | `make update-protocol` (= `@next` exact) |
| unity-explorer | `scripts/package.json`, `npm run build-protocol` regenerates committed `.gen.cs` | tarball URL | `npm install @dcl/protocol@next && npm run build-protocol` |
| godot-explorer | `PROTOCOL_FIXED_VERSION_URL` in `src/install_dependency.rs`, extracted by `cargo run -- install` | tarball URL | the published npm URL |
| bevy-explorer | hand-vendored `.proto` files under `crates/dcl_component/src/proto/`, closest to `origin/experimental-bevy` but drifted per file | copy the touched file(s) from the branch the feature targets | same |

`main` publishes `@dcl/protocol@next`; `latest` is stale; `experimental` is deprecated; `experimental-bevy` (PR #472, do not merge) holds bevy-only features and claims numbers `main` must skip. Details: `references/repos/*.md`.

## Common mistakes

- Picking an id or field number from the local tree only. `make check-component-id` cannot see open PRs, `experimental-bevy` or the engines' copies; use `scripts/next-component-id.sh` and `scripts/field-numbers.sh`, and paste their rationale into the PR body.
- Treating a generated type as support. Unity has `ComponentID` constants for 1218, 1219 and 1222 and handles none of them; `PBAvatarShape.talking` is never read. Grep for consumers outside generated directories.
- Adding `optional` to an existing field or renaming one: buf reports both as breaking against `main`. New fields are `optional`; old fields stay as they are and get `// @deprecated` comments.
- Running phases out of order, or waiving a gate on the model's own authority. A waiver is written by the user with their handle.
- Writing into a sibling repo in plan mode, or hand-editing generated code (`.gen.cs`, `generated/*.gen.ts`, prost output).
- Copying line numbers from a reference file, a map or memory: they rot within weeks. Cite `path:symbol`; add `~N` only for a line you printed in this run.
- Claiming in a draft PR body that something was built, run, observed or posted when it was not. Plan mode drafts say "to run" / "to post".
- Assuming all engines animate an NPC the same way. Unity drives walk/run from the position delta but its animator's emote-to-movement exit is muted on `dev`; bevy cancels emotes on velocity; godot does not drive locomotion for AvatarShape at all. Check `references/subsystems.md` and verify at runtime.

## Where things are

| Need | Open |
|---|---|
| phase gates, size tracks, modes, merge order, resume rules | `.claude/skills/protocol-feature/references/process.md` |
| policy values in force | `.claude/skills/protocol-feature/references/policy.md` |
| per-repo wiring, pins, gates, PR style | `.claude/skills/protocol-feature/references/repos/{protocol,sdk,unity,bevy,godot,verification,adr}.md` |
| which file implements which subsystem in each engine | `.claude/skills/protocol-feature/references/subsystems.md` |
| PR body skeletons per repo | `.claude/skills/protocol-feature/references/pr-styles.md`, `assets/protocol-pr-body.md`, `assets/engine-pr-bodies.md` |
| the bundle template | `.claude/skills/protocol-feature/assets/proposal-template.md` |
| numbers and collisions | `scripts/next-component-id.sh`, `scripts/field-numbers.sh` |
| engine schema and consumer evidence | `scripts/engine-support.sh <PbName> [--field f]` |
| consumer pins and repin status | `scripts/consumer-pins.sh` |
| gates and bundle status | `scripts/proposal-gate.sh` |
| a worked plan-mode bundle | `.claude/skills/protocol-feature/examples/avatar-shape-keep-emote-on-move/` |
