---
title: Keep an AvatarShape's emote playing while its entity moves
slug: avatar-shape-keep-emote-on-move
kind: field
size: small
mode: plan
draft: true
phase: 3
status: designed
target_branch: main
component: PBAvatarShape (1080)
owner: kuruk-mm
created: 2026-10-10
updated: 2026-10-10
policy:
  merge_gate: all-accounted
  adr_by_size: "small: none · medium: alongside · large: before"
  rollout_includes: [test-scene, docs, sdk-skills]
  reserve_bevy_numbers: comment
  test_scene_pin: published
links:
  issue:
  adr:
  protocol_pr:
  protocol_tarball:
  sdk_pr:
  unity_pr:
  bevy_pr:
  godot_pr:
  test_scene_pr:
  docs_pr:
  sdk_skills_pr:
---

# Keep an AvatarShape's emote playing while its entity moves

> A scene that moves an NPC (an entity with `PBAvatarShape`) with a Transform update or a Tween can ask the explorer to keep the NPC's current emote playing instead of switching it to the walk/run locomotion animation. When the new flag is absent or `false`, nothing changes: engines keep doing what they do today.

## 1. Need

- **Problem**: creators move NPCs along paths (a vendor walking to a stall, a dancer sliding on a float) and want a scene emote to keep playing during the move. Today, moving the entity makes the NPC drop the emote and play walk/run, so "dance while the float moves" is impossible.
- **Who asked / evidence**: the user (Godot explorer maintainer) raised it as the example feature for this process; decentraland/sdk#566 ("AvatarShape doesn't walk", 2023) documents that SDK6 inferred walk/run from position changes; the sdk-skills `npcs` skill tells creators that "moving the Transform position causes the NPC to walk/run ... the avatar plays its walk animation along the tween".
- **Workaround today**: none that keeps the emote; creators either freeze the NPC or accept the walk animation.
- **Today's behaviour per engine** (claimed; verified in section 3):

  | Engine | Today | Source of the claim |
  |---|---|---|
  | unity-explorer | NPC movement drives the animator `MovementBlend` (walk/run plays); on `origin/dev` the `Emote -> Movement` exit on `MovementBlend > 0.1` is muted for both `Emote` and `Emote Loop`, so whether the emote survives a move is unconfirmed | `Explorer/Assets/DCL/Character/CharacterMotion/Systems/SDKAvatarShapesMotionSystem.cs` (`UpdateAnimations`), `Explorer/Assets/DCL/AvatarRendering/AvatarShape/Assets/Animator/CharacterAnimator.controller` (unverified at runtime) |
  | bevy-explorer | scene NPC velocity is derived from the transform delta; `animate()` cancels a playing emote once velocity rises (`velocity_cancels` is true for every non-foreign avatar) and picks walk/run | `crates/avatar/src/npc_dynamics.rs` (`update_npc_velocity`), `crates/avatar/src/animate.rs` (unverified at runtime) |
  | godot-explorer | AvatarShape avatars spawn with `movement_type: ExternalController` and nothing sets `walk/jog/run` for them, so a moved AvatarShape stays idle and keeps its emote | `lib/src/godot_classes/dcl_avatar.rs`, `lib/src/scene_runner/components/avatar_shape.rs` (unverified at runtime) |

- **Non-goals**: real players' avatars (their locomotion comes from comms and input, not from scene transforms); looping scene emotes (AvatarShape emotes play once; a separate change); AvatarShape placed on the PLAYER entity (bevy honours it, #1242; semantics for that case are recorded as an open question, not changed here).

## 2. Design

- **Change**: `field` on `PBAvatarShape` in `proto/decentraland/sdk/components/avatar_shape.proto` (component id 1080, LWW, scene-written, scene-local: AvatarShape state is never relayed over comms).
- **Proposed shape** (draft numbering; final in section 4):

  ```protobuf
  // Appended to PBAvatarShape
  optional bool keep_emote_on_move = 14; // when true, moving the entity does not cancel the current emote and no walk/run locomotion animation is played (default: false, today's behaviour)
  ```

- **Semantics**: `true`: while `expression_trigger_id` names an emote, entity movement (Transform updates, Tween, TweenSequence) neither cancels it nor plays locomotion; when no emote is playing, locomotion behaves as today. `false` or unset: today's behaviour. The flag is read on every AvatarShape update, so a scene can flip it per move. Rotation toward the movement direction is unchanged.
- **Prior art**: `origin/main`: none for AvatarShape; `AvatarEmoteCommand.ES_INTERRUPTED` lists movement as an interruption cause. `origin/experimental-bevy`: `PBAvatarMovement` / `MovementAnimation.idle` ("true: a triggerSceneEmote may take over; false: emotes are suppressed while this animation plays") solves the player case, not NPCs; `PBAvatarShape` there has `repeated string force_render = 13`. Open protocol PRs: only the branch-mirror PRs #472 (`experimental-bevy`) and #202 (`protocol-squad`) touch avatar_shape.proto, both carrying `force_render = 13` (checked 2026-10-10). ADRs: none for AvatarShape; ADR-245 covers player components, ADR-215 animation defaults. docs: `creator/sdk7/interactivity/avatars/npc-avatars.md` (origin/main) "Animations" section. bevy issues: #1271 (read AvatarEmoteCommand as a play command for scene avatars), #1242 (AvatarShape on the PLAYER entity).
- **Alternatives considered**:
  - Engine-side change, no protocol change (never cancel NPC emotes on movement): changes every deployed scene that relies on walk/run during moves; rejected.
  - A `locomotion` enum (`LOC_AUTO`, `LOC_NONE`, `LOC_KEEP_EMOTE`): more expressive, but the only requested case is "keep the emote"; an enum can be added later without breaking (`AvatarEmoteCommand.state` precedent); rejected for now.
  - Drive NPC animation through `AvatarEmoteCommand` with a loop/mask (bevy #1271): a larger, cross-engine behaviour change already tracked separately; rejected as the vehicle.
  - Do nothing: the use case stays impossible; rejected.
- **Compatibility**: additive, `optional`, default reproduces today; no rename, no retype; scene-local, so no rfc4 / Pulse change. Field 13 is skipped (`force_render` on `origin/experimental-bevy` and `origin/protocol-squad`); per `policy.reserve_bevy_numbers = comment` the diff carries `// 13 is force_render on experimental-bevy`.
- **Numbering preview** (2026-10-10, `scripts/field-numbers.sh PBAvatarShape`): main 1-12; experimental-bevy and protocol-squad add 13 `force_render`; experimental adds enum `AvatarEmoteMask` only; open PRs: none; `NEXT_SAFE_FIELD=14`.
- **ADR**: none (`policy.adr_by_size`: small -> none).
- **Open questions**: (1) does the flag also apply when a scene puts an AvatarShape on the PLAYER entity (bevy honours that; unity/godot ignore it)? (2) should rotation toward the movement direction also be suppressed? (3) godot's current behaviour must be confirmed at runtime before calling it "already-supported".

## 3. Technology verification

| Target | L0 schema (copy / pin) | L1 consumers (paths, generated dirs excluded) | Hook (path:symbol) | Baseline behaviour | Verdict | Effort | L2 runtime |
|---|---|---|---|---|---|---|---|
| js-sdk-toolchain | | | | | | | n/a |
| unity-explorer | | | | | | | |
| bevy-explorer | | | | | | | |
| godot-explorer | | | | | | | |

- **Branch drift**:
- **Cross-engine mismatches to decide**:
- **Runtime confirmation plan**:
- **Spikes / blockers**:

## 4. Definition

- **Final numbers**:
- **Diff**:
- **Index line**: none (existing component).
- **Validation**:
- **ADR**: none (policy).
- **Protocol PR**:

## 5. Implementation

Merge order: protocol -> (sdk | unity | bevy | godot on the PR tarball) -> repin to the published `@dcl/protocol` -> merge SDK and engines -> test scene -> docs / sdk-skills.

| Repo | Branch | Protocol source | Files / steps | Gate | PR | State |
|---|---|---|---|---|---|---|
| js-sdk-toolchain | | | | | | |
| unity-explorer | | | | | | |
| bevy-explorer | | | | | | |
| godot-explorer | | | | | | |
| sdk7-test-scenes | | | | | | |
| docs / sdk-skills / adr | | | | | | |

## 6. Review

- **Alignment matrix result**:
- **Findings**:
- **Pins before merge**:
- **Merge-order readiness**:
- **Follow-ups**:

## Gate log

| Gate | Result | Date | By | Evidence |
|---|---|---|---|---|
| 1 need | passed | 2026-10-10 | model | section 1 |
| 2 design | passed | 2026-10-10 | model | section 2 |
| 3 tech-check | pending | | | matrix + runtime plan |
| 4 define | pending | | | protocol.diff + checks |
| 5 implement | pending | | | per-repo gates |
| 6 review | pending | | | review.md |

## Decision log

| Date | Phase | Decision | Policy value used | By |
|---|---|---|---|---|
| 2026-10-10 | 2 | Shape is `optional bool keep_emote_on_move`; `false`/unset keeps today's behaviour | — | model |
| 2026-10-10 | 2 | Field 14; 13 skipped for `force_render` on experimental-bevy / protocol-squad, recorded as a comment | reserve_bevy_numbers = comment | model |
| 2026-10-10 | 2 | No ADR | adr_by_size = small: none | model |
| 2026-10-10 | 2 | Gating engines: unity, bevy, godot each need an implementation PR or a parity-gap issue | merge_gate = all-accounted | model |
| 2026-10-10 | 2 | Rollout rows: test scene, docs (npc-avatars.md), sdk-skills (npcs) | rollout_includes = test-scene, docs, sdk-skills | model |
