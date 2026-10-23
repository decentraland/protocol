# The six-phase process

How a protocol feature moves from an idea to merged PRs across decentraland/protocol, js-sdk-toolchain, unity-explorer, bevy-explorer, godot-explorer, sdk7-test-scenes, docs and sdk-skills, and what each phase must leave behind.

## Contents
- [Why a process at all](#why-a-process-at-all)
- [Phases, owners and exit artifacts](#phases-owners-and-exit-artifacts)
- [Gates](#gates)
- [Size tracks](#size-tracks)
- [Modes: plan, draft, execute](#modes-plan-draft-execute)
- [Merge order and why](#merge-order-and-why)
- [Resuming a bundle](#resuming-a-bundle)
- [Standalone entries](#standalone-entries)
- [Stop-and-show points and questions](#stop-and-show-points-and-questions)
- [Open protocol PRs as of 2026-10-10](#open-protocol-prs-as-of-2026-10-10)
- [Existing per-repo processes reused by path](#existing-per-repo-processes-reused-by-path)

## Why a process at all

Scenes deployed to the world are immutable: whatever shape a scene serialized is what every explorer must keep reading forever. A field name, number or default that reaches `main` cannot be fixed later, only deprecated around (`pointer_events.proto` `max_player_distance`). Three engines plus the SDK implement every change by hand, each with its own pin, codegen and registration list, so a feature that is right in one engine and silently ignored in another is the common failure (`AvatarLocomotionSettings` was unregistered in bevy until #658; `PBAvatarShape.talking` is never read by Unity). The phases exist to answer, in order: is the need real, is the shape right, can each engine actually do it, are the numbers safe, did every consumer wire it, and does the whole thing align.

## Phases, owners and exit artifacts

| # | Phase | Skill | Rewrites | Sets `status` | Exit artifact |
|---|---|---|---|---|---|
| 1 | Need | `protocol-propose` | `## 1. Need` | `draft` | problem, who asked, workaround, today's behaviour per engine (claimed), non-goals |
| 2 | Design | `protocol-propose` | `## 2. Design` | `designed` | proposed shape with draft numbers, semantics (unset == today), prior art, >= 2 alternatives, compatibility, ADR decision |
| 3 | Technology verification | `protocol-tech-check` | `## 3. Technology verification` | `verified` or `blocked` | per-engine matrix with L0/L1/L2 evidence and a verdict, branch-drift line, runtime plan |
| 4 | Definition | `protocol-define` | `## 4. Definition` | `defined` | `protocol.diff`, final numbers with the sources checked, validation results, `pr-protocol.md`, ADR draft when policy says so |
| 5 | Implementation | `protocol-implement` | `## 5. Implementation` | `implementing` | `actions.md` (per-repo briefs in merge order), `pr-<repo>.md`, links as PRs open |
| 6 | Review | `protocol-review` | `## 6. Review` | `in-review` then `done` | `review.md`: alignment matrix, P0/P1/P2, pins, merge-order readiness, follow-ups |

Every phase appends a row to `## Gate log` and one or more rows to `## Decision log` (quoting the policy value used, from `references/policy.md`). The bundle is the only memory between sessions; nothing lives in chat alone.

## Gates

`scripts/proposal-gate.sh <proposal.md> <phase>` runs on entry and exit of every phase. Phase N may start only when Gate rows 1..N-1 read `passed` (or `waived` with a named person). The criteria:

- **G1 need**: problem stated in creator terms, who asked or what evidence, today's workaround, non-goals.
- **G2 design**: a wire shape whose absent/default value reproduces today's behaviour, at least two alternatives with the reason each loses (one of them "engine-side change, no protocol change"), locality stated (scene-local vs relayed over comms), ADR decision recorded.
- **G3 tech-check**: every engine the merge gate counts is `already-supported` or `feasible` with a hook path, or the user logged an exception; no gating row is `blocked`. On the small track an L2 (runtime) cell may stay `pending`; log it.
- **G4 define**: `protocol.diff` present, numbering rationale names every branch, open PR and engine copy checked, `make buf-lint` / `make buf-breaking` / `make test` results recorded (or listed as "to run" in plan mode), `pr-protocol.md` written.
- **G5 implement**: one brief per gating repo with its gate result, every `links:` entry either filled or explained.
- **G6 review**: no P0 finding, merge-order table complete, follow-ups listed.

A waiver is the user's call, written as `waived` with their handle in the `By` column; the model never waives a gate.

## Size tracks

Classified from the kind of change; `--size` overrides. Precedents are merged protocol PRs.

| Size | Kinds | Precedents | What changes |
|---|---|---|---|
| small | optional field on an existing message, enum value, comment or default clarification, optional request field on an existing RPC | #489 font_src, #470 max_camera_distance, #477 TeleportToRequest.realm | sections 1-2 may merge into one page (<= 25 lines); matrix from grep evidence; runtime plan only for `uncertain` rows; no ADR; propose, tech-check and define run in one session |
| medium | new component, result (grow-only) component, new RPC, new shared type under `sdk/components/common/` | #474 AvatarNametag, #455 ExplorerUiEventsResult, #444 StopEmote | full proposal; L1 evidence per engine and a runtime plan for every gating engine; registration checklist in every consumer; Draft ADR alongside; test scene mandatory; Unity hand-off to the architect agent |
| large | rfc4 / Pulse comms, a new kernel API file, semantics change of released behaviour, anything that needs the `breaks compat` label | #495 skybox, #499 nearby voice, #460 UiTransform yoga props | ADR before definition; migration section; RFC-4 (ADR-104) update for rfc4 edits; merge gate escalates to `all` |

## Modes: plan, draft, execute

- **plan** is the default. Allowed: `git fetch`, `git show origin/<branch>:<path>`, `git grep`, `gh pr list/view/diff`, `gh api repos/decentraland/<repo>/contents/<path>`, reading any sibling repo, the bundled scripts. The only writes are files inside the bundle directory: `proposal.md`, `protocol.diff`, `actions.md`, `pr-<repo>.md`, `review.md`, `feature-description-unity.md`. Never a branch, a commit, an `npm install`, a `cargo` or `make` in a sibling repo, a PR, an issue, a comment. Phrases like "dry run", "simulate", "hypothetical", "don't open anything", "just markdown" force plan mode even when `--execute` was passed.
- **draft** (`--draft`, "draft proposal") is plan mode through all six phases in one session: the bundle ends with the diff, the briefs, every PR body the feature would need and the review checklist, so the whole rollout can be judged before anyone touches a repo. Only L2 runtime observation is left as a plan, and the ADR is drafted only when policy requires it. `/protocol-propose` alone stops after phase 2 for people who want to iterate on the shape first.
- **execute** needs `--execute` or words like "go ahead and implement" and a bundle at phase >= 4 before any sibling repo is edited. One branch `feat/<slug>` per repo, created from the fetched default branch (`dev` for unity-explorer), never on a dirty checkout. Each repo's gate runs before its brief is marked done. These actions each get their own confirmation question, with the exact command printed, never batched: `git commit`, `git push`, `gh pr create` (the body is printed in full first), `gh pr comment`, `gh pr edit --add-label`, `gh issue create`, overwriting snapshots or goldens, bumping a protocol pin in a repo the user did not name.

If Claude Code's own plan permission mode refuses a write, print the documents in full instead of skipping them.

## Merge order and why

1. **Protocol PR first.** CI posts a tarball URL (`npm install "https://sdk-team-cdn.decentraland.org/@dcl/protocol/branch//dcl-protocol-1.0.0-<runId>.commit-<sha7>.tgz"`, the double slash is real) that every consumer can pin while the PR is open.
2. **SDK and engines in parallel on the tarball**: js-sdk-toolchain pins it in both `package.json` files; unity-explorer in `scripts/package.json`; godot-explorer in `PROTOCOL_FIXED_VERSION_URL`; bevy-explorer copies the touched `.proto` file(s) into its vendored tree. Validate end to end with the test scene.
3. **Merge the protocol PR** once the gate in `MERGE_GATE` is satisfied. `main` publishes `@dcl/protocol@next`.
4. **Repin every consumer to the published build** (`@next` or the exact `1.0.0-<runId>.commit-<sha7>`): the SDK's `check-local-deps` CI job rejects http/file pins on PRs to `main`, and unity/godot build from published tarballs.
5. **Merge SDK and engine PRs** in any order.
6. **Test scene last**, pinned per `TEST_SCENE_PIN`; then docs (draft until an `@dcl/sdk` release) and sdk-skills.

The order matters because a protocol change merged before any consumer validated it becomes permanent (see "Why a process at all"), and a consumer merged while pinned to a PR tarball breaks the moment the tarball is garbage-collected or the PR changes.

## Resuming a bundle

On `protocol-feature proposals/<slug>` (or any phase skill given a bundle path) run `scripts/proposal-gate.sh status <slug>` and print its card: title, status, size, kind, mode, next phase, empty links. Read `## Decision log` before asking anything; a question already answered there is not asked again. Continue from the first gate that is not `passed`.

## Standalone entries

`/protocol-review 499` and a bare question such as "could godot support X?" are valid entry points. They create a stub bundle (`kind`, `component` and the phase they start at filled, earlier gates marked `waived` by the user with the reason "standalone entry") so the answer is kept with the same structure as a full run.

## Stop-and-show points and questions

Pre-flight asks at most one question: the path of a missing gating repo, or which protocol clone is canonical when two are found. The router then prints the repo table and the policy values in force and continues. The phase skills stop and show their section after design (phase 2), after the matrix (phase 3) and before any write in execute mode; everywhere else they proceed and record decisions in the Decision log.

## Open protocol PRs as of 2026-10-10

Regenerate this with `gh pr list --repo decentraland/protocol --state open` and `scripts/next-component-id.sh` / `scripts/field-numbers.sh` at run time; the table only shows what an open PR can claim.

| PR | Claims |
|---|---|
| #495 feat: skybox component | component id 1223 |
| #499 PlayerVoiceState / VoiceChatModifierArea | component ids 1224, 1225 |
| #412 UiTransform scrolling + UiScrollResult | id 1202 (same as experimental-bevy), PBUiTransform 74-76 |
| #460 UiTransform gap/aspect_ratio/flex/direction/box_sizing | PBUiTransform 78-87 |
| #488 AudioEvent playback position | PBAudioEvent 3-5, PBAudioSource 8 |
| #476 EngineInfo total_runtime_f64 | PBEngineInfo 5, declared without `optional` (a counter-example to the convention, not a precedent) |
| #472 experimental-bevy integration branch | do not merge; ids 1200-1208, 1500, 1501, 1503 and several field numbers live only there |

## Existing per-repo processes reused by path

- unity-explorer `.claude/agents/dcl-sdk-feature-implementation/` (architect + protocol/sdk/explorer/test-scene specialists; Unity-only, phases 4-6, never commits, assumes `../` siblings) and `docs/how-to-implement-new-sdk-components.md`.
- godot-explorer `docs/PROTOCOL_DEV_WORKFLOW.md` (Flow A: protocol -> SDK + godot on the tarball -> merge protocol -> repin -> merge; Flow B via `protocol-squad` is legacy), `REVIEW.md`, `godot-explorer/.claude/skills/pr-description/`.
- js-sdk-toolchain `AGENTS.md`, `REVIEW.md`, `docs/adding-or-modifying-a-component.md` (stale in places: see `references/repos/sdk.md`).
- adr `content/.TEMPLATE.md`, `content/.SDK-COMPONENT-TEMPLATE.md`.

These skills add the front of the process (need, design, three-engine feasibility), the cross-engine numbering checks and the single state carrier; they do not replace those documents.
