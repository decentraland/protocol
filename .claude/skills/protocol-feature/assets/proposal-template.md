---
title: <Short imperative title>
slug: <kebab-slug>                 # bundle dir: <PROPOSAL_DIR>/<slug>/
kind: field                        # field | enum-value | semantics | component | result-component | api (anything under kernel/apis, incl. one request field) | comms | none
size: small                        # small | medium | large (references/process.md)
mode: plan                         # plan | execute
draft: true                        # true = one-session simulation of all six phases
phase: 1                           # 1 need | 2 design | 3 tech-check | 4 define | 5 implement | 6 review | done
status: draft                      # draft | designed | verified | defined | implementing | in-review | done | rejected | blocked | parked
target_branch: main                # main | experimental-bevy (only if ALLOW_EXPERIMENTAL_BEVY_FIRST=yes)
component: PBAvatarShape (1080)    # or `new`, the RPC name, or the message name
owner: <github handle>
created: YYYY-MM-DD
updated: YYYY-MM-DD
policy:                            # copied from references/policy.md when the bundle is created
  merge_gate: all-accounted
  adr_by_size: "small: none · medium: alongside · large: before"
  rollout_includes: [test-scene, docs, sdk-skills]
  reserve_bevy_numbers: comment
  test_scene_pin: published
links:
  issue:
  adr:
  protocol_pr:
  protocol_tarball:                # from the "Test this pull request" bot comment; keep the literal branch//
  sdk_pr:
  unity_pr:
  bevy_pr:
  godot_pr:
  test_scene_pr:
  docs_pr:
  sdk_skills_pr:
---

# <Title>

> One paragraph a reviewer can read alone: what scenes can do after this ships, and what stays exactly the same when the new field or component is absent.
> Small track: sections 1 and 2 may be merged as `## 1-2. Need and design` and must stay under 25 lines.

## 1. Need

- **Problem**: what a creator cannot express today, in creator words.
- **Who asked / evidence**: issue, thread, scene, or the docs / sdk-skills text that describes today's behaviour.
- **Workaround today** and why it is not enough.
- **Today's behaviour per engine** (claimed here; verified in section 3):

  | Engine | Today | Source of the claim |
  |---|---|---|
  | unity-explorer | | path or "unverified" |
  | bevy-explorer | | |
  | godot-explorer | | |

- **Non-goals**.

## 2. Design

- **Change**: `<kind>` on `<message or service>` in `proto/decentraland/<path>.proto` (new component: `proto/decentraland/sdk/components/<snake>.proto`, root message `PB<Pascal>`).
- **Proposed shape** (draft numbering; final numbers are set in section 4):

  ```protobuf
  // <message doc comment: valid entities, who writes it, LWW vs grow-only, scene-local vs relayed, no-op platforms>
  optional <type> <lower_snake> = <N>; // <meaning, units> (default: <X>, which is today's behaviour)
  ```

- **Semantics**: each value; unset == today's behaviour; interaction with existing fields (for AvatarShape: `expression_trigger_id`, tweens, the PLAYER entity).
- **Prior art**: hits on `origin/main`, `origin/experimental-bevy`, `origin/protocol-squad`, open protocol PRs, ADRs, docs, sdk-skills, bevy's vendored tree, with paths; say explicitly when there is none.
- **Alternatives considered** (at least two, each with the reason it loses; include "engine-side change, no protocol change" and "do nothing").
- **Compatibility**: additive? any rename or retype? relayed over rfc4 / Pulse? numbers skipped and why.
- **Numbering preview**: pasted `scripts/field-numbers.sh` / `scripts/next-component-id.sh` output, date-stamped.
- **ADR**: none | amend ADR-NNN in place | new ADR (template: SDK-COMPONENT | generic), per `policy.adr_by_size`.
- **Open questions**.

## 3. Technology verification

| Target | L0 schema (copy / pin) | L1 consumers (paths, generated dirs excluded) | Hook (path:symbol) | Baseline behaviour | Verdict | Effort | L2 runtime |
|---|---|---|---|---|---|---|---|
| js-sdk-toolchain | pin `<ver>` | | | | | S/M/L | n/a |
| unity-explorer | pin `<ver>`; `.gen.cs` has the field? | | | | | | pending / observed (who, how, date) |
| bevy-explorer | vendored matches main / experimental-bevy / neither | | | | | | |
| godot-explorer | pin commit `<sha7>` has it? | | | | | | |

Verdicts: `already-supported` (L1 consumer exists AND L2 observed), `feasible` (hook named, bounded file list), `uncertain` (hook not found, code paths disagree, or inferred from code only), `blocked` (missing subsystem or needs a comms / RFC change), `n/a`.

- **Branch drift**: which protocol branch each engine would receive this from (unity `@next`; SDK exact pin; godot pin commit; bevy == `origin/experimental-bevy`).
- **Cross-engine mismatches to decide**: from `references/subsystems.md` for this area.
- **Runtime confirmation plan**: sdk7-test-scenes `scenes/<x>,<y>-<slug>` (free parcel checked with `npm run check-parcels`), the snippet, one run command per engine, the observable, baseline first.
- **Spikes / blockers**: for `uncertain` or `blocked` rows, the question and where to file it (godot: issue with `need tech test`).

## 4. Definition

- **Final numbers**: component id `NNNN` / field `N`; checked against: `origin/main`, `origin/experimental-bevy`, `origin/protocol-squad`, `origin/experimental`, open PRs #..., engine copies; skipped: ...
- **Diff**: `protocol.diff` in this bundle (or the protocol PR link).
- **Index line**: `import public "decentraland/sdk/components/<snake>.proto";` in `public/sdk-components.proto` (or `public/sdk-apis.proto`).
- **Validation**: `make install && make buf-lint && make buf-breaking && make test`; `make list-components-ids`; `make check-component-id ID=N` -> results, or "to run" in plan mode.
- **ADR**: none (policy) | `content/ADR-<n>-<slug>.md` Draft, link.
- **Protocol PR**: `pr-protocol.md`; tarball URL once open.

## 5. Implementation

Merge order: protocol -> (sdk | unity | bevy | godot on the PR tarball) -> repin to the published `@dcl/protocol` -> merge SDK and engines -> test scene -> docs / sdk-skills.

| Repo | Branch | Protocol source | Files / steps | Gate | PR | State |
|---|---|---|---|---|---|---|
| js-sdk-toolchain | feat/<slug> | tarball -> @next | repin x2, spec, snapshots, api.md (+ extended / react-ecs) | `make build && make test` | | |
| unity-explorer | feat/<slug> | tarball -> @next | pin + build-protocol + system(s) (+ IDirtyMarker / ComponentsContainer / plugin) | `npm run build-protocol`; EditMode test (human) | | hand-off? |
| bevy-explorer | feat/<slug> | copy of <branch> | touched .proto (+ build.rs, SceneComponentId, impl), consumer, literal fixes | `cargo clippy --locked -- -D warnings && cargo test --all` | | |
| godot-explorer | feat/<slug> | pin URL | PROTOCOL_FIXED_VERSION_URL, system / GDScript, literal fixes | `cargo run -- build`; itest | | |
| sdk7-test-scenes | feat/<slug> | SDK tarball -> published | `scenes/<x>,<y>-<slug>` | `npm run check-parcels`; `npm run build` | | |
| docs / sdk-skills / adr | | | page + version hint; skill text; ADR flip | | | per `policy.rollout_includes` (N/A allowed with a reason) |

Per-repo briefs with exact commands and PR bodies: `actions.md`.

## 6. Review

- **Alignment matrix result**: ids, field numbers, optional-ness, grow-only parity across the four lists, defaults, bevy vendored file byte-equal.
- **Findings**: P0 / P1 / P2, each with a path or PR as evidence.
- **Pins before merge**: SDK published; unity `package.json` + lockfile + `.gen.cs` agree; godot npm URL; test scene per `policy.test_scene_pin`.
- **Merge-order readiness** and pending repins.
- **Follow-ups**: docs, sdk-skills, ADR Draft -> Living, non-gating engines, parity issues.
- Report: `review.md`.

## Gate log

| Gate | Result | Date | By | Evidence |
|---|---|---|---|---|
| 1 need | pending | | | section 1 |
| 2 design | pending | | | section 2 |
| 3 tech-check | pending | | | matrix + runtime plan |
| 4 define | pending | | | protocol.diff + checks |
| 5 implement | pending | | | per-repo gates |
| 6 review | pending | | | review.md |

## Decision log

| Date | Phase | Decision | Policy value used | By |
|---|---|---|---|---|
