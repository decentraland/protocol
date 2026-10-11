---
title: Keep an AvatarShape emote while the scene moves it
slug: avatar-shape-keep-emote-on-move
kind: field
size: small
mode: plan
draft: true
phase: done
status: in-review
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

# Keep an AvatarShape emote while the scene moves it

> After this ships a scene can set `keepEmoteOnMove: true` on an `AvatarShape` and the NPC keeps playing the emote it was given through `expressionTriggerId` while the scene moves it with a `Transform` write or a `Tween`, instead of the explorer blending in walk/run (bevy, documented behaviour) or whatever the engine does today. When the field is absent or `false` nothing changes: every explorer keeps its current locomotion rule for moved NPCs, which already differs per engine (section 3). The field is scene-local, never relayed, and ignored on the player's own entity and on other players.
>
> Dry run (plan mode, `--draft`): this bundle is the only output; no branch, PR, issue or sibling-repo edit was made. Bundle dir comes from `PROTOCOL_FEATURE_OUT`.

## 1. Need

- **Problem**: A creator who moves an NPC (an `AvatarShape` entity) along a path with `Transform` or `Tween` while it plays an emote cannot keep the emote playing. In creator words: "my mannequin on the conveyor stops dancing and walks", "the NPC waving from the moving cart drops its arm and runs". There is no field that says "animate the emote, not the legs".
- **Who asked / evidence**: this request (kuruk-mm, 2026-10-10, dry run). Adjacent evidence that NPC emotes under scene-driven motion are a live surface: decentraland/sdk-skills `npcs/SKILL.md` ~120 states today's behaviour as "Moving the `Transform` position causes the NPC to walk/run to the destination ... the avatar plays its walk animation along the tween" (and ~204 "4,19-avatar-shape-movement ... (walks to target)"); bevy-explorer #714 / godot-explorer #1838 "Store displays in plaza: wearables freeze and show mannequin after animation" (animated `AvatarShape` displays); unity-explorer #5047 "Scene emotes on AvatarShape not working correctly" (closed). No open issue asks for this exact flag: `gh issue list --search 'AvatarShape emote move'` on unity-explorer, bevy-explorer, godot-explorer, protocol and sdk7-test-scenes returned nothing on point (2026-10-10); js-sdk-toolchain has issues disabled.
- **Workaround today**: re-trigger the emote every N seconds with a rising `expressionTriggerTimestamp` (the docs' "Looping Animations" recipe). It restarts the clip (visible pop), fights the engine (bevy cancels again as soon as the NPC's damped speed exceeds the slowest speed seen since the emote began, `crates/avatar/src/animate.rs:animate` ~632), and is engine-dependent. The other workaround, a `GltfContainer` + `Animator` instead of an `AvatarShape`, loses wearables and the avatar look.
- **Today's behaviour per engine** (claimed here; verified in section 3):

  | Engine | Today | Source of the claim |
  |---|---|---|
  | unity-explorer | `SDKAvatarShapesMotionSystem.UpdateAnimations` writes `MovementBlend` from the NPC's position delta (Tween moves too), but on `origin/dev` the `Emote` and `Emote Loop` states' `MovementBlend > 0.1 -> Movement` transitions are muted, and no `CharacterEmoteSystem` cancel query matches an NPC. Code says: the emote plays to its end while the NPC slides, then walk/run. Docs and sdk-skills say: walks. **Unverified at runtime.** | `Explorer/Assets/DCL/Character/CharacterMotion/Systems/SDKAvatarShapesMotionSystem.cs:UpdateAnimations`; `Explorer/Assets/DCL/AvatarRendering/AvatarShape/Assets/Animator/CharacterAnimator.controller` (transitions `4154687653260660565`, `-7991627196901748505`, `m_Mute: 1`); `Explorer/Assets/DCL/AvatarRendering/Emotes/Systems/Play/CharacterEmoteSystem.cs:CancelEmotes` / `:CancelEmotesByMovementInput` (origin/dev 41a9e92) |
  | bevy-explorer | NPC velocity is derived from the transform delta (`npc_dynamics.rs:update_npc_velocity`); `animate` cancels the emote when `velocity_cancels && damped_velocity_len * 0.9 > playing_min_vel` (true for every scene NPC) and the velocity-selected walk/run takes over. From rest, any motion cancels. | `crates/avatar/src/npc_dynamics.rs:update_npc_velocity` ~49; `crates/avatar/src/animate.rs:animate` ~625-642 (origin/main ad56994) |
  | godot-explorer | Nothing sets walk/jog/run for an `AvatarShape` (`dcl_avatar.rs` defaults to `ExternalController`, whose `process` arm only updates the parcel), so `self_idle` stays true, `avatar_emote_controller.process(idle=true)` never cancels, and a moved NPC slides in idle with its emote intact. Code-level only. | `lib/src/godot_classes/dcl_avatar.rs` ~244 / ~576; `godot/src/decentraland_components/avatar/avatar.gd` ~1460-1463; `godot/src/decentraland_components/avatar/avatar_emote_controller.gd:process` ~1276 (origin/main cada2d9) |

- **Non-goals**: changing the default (unset) behaviour of any engine; adding NPC locomotion inference to godot (separate parity issue); relaying the flag over comms (AvatarShape state is scene-local); applying it to `engine.PlayerEntity` or other players' avatars (their emotes follow input-cancel rules, unity `CharacterEmoteSystem.cs` (`CancelEmotesByMovementInput` comment)); looping scene emotes (`loop: false` stays); masked (upper-body) emotes (godot already keeps them under motion; AvatarShape emotes are full body in Unity and bevy); changing position or facing (an NPC with the flag still translates and turns toward its travel direction).

## 2. Design

- **Change**: `field` on `PBAvatarShape` (component 1080) in `proto/decentraland/sdk/components/avatar_shape.proto`.
- **Proposed shape** (draft numbering; final numbers set in section 4):

  ```protobuf
  // (message doc comment gains:) Movement: when the scene moves an AvatarShape entity (Transform or Tween)
  // each explorer derives the locomotion animation from the motion. `keep_emote_on_move` lets a full-body
  // emote started with `expression_trigger_id` play through that motion instead. Scene-local (never relayed),
  // read only on scene-owned AvatarShape entities, ignored on `engine.PlayerEntity` and on other players'
  // entities. Explorers without support keep their current behaviour.

  // 13 is force_render on experimental-bevy
  // true: a full-body emote keeps playing while the scene moves this entity (Transform or Tween); no walk/run
  // is blended in until the emote ends or is replaced, then the explorer's locomotion rule applies again.
  // false: today's behaviour, the explorer's locomotion rule may interrupt the emote
  optional bool keep_emote_on_move = 14; // keep the running emote while the scene moves this entity (default: false)
  ```

- **Semantics**:
  - `true`: while an emote started by `expression_trigger_id` is playing, the explorer does not derive walk/run from the entity's motion and does not cancel the emote because of motion; the entity still translates and turns. When the emote reaches its natural end, is replaced by a new `expression_trigger_id` / `expression_trigger_timestamp`, or is cleared, the explorer's normal locomotion rule resumes (walk/run if the NPC is still moving, idle otherwise).
  - `false` / unset: today's behaviour in each explorer (section 1 table). Proto3 `bool` cannot express "unset" without `optional`; the field is `optional` and named so that `false` is today, as the propose rules require.
  - Interaction with existing fields: `expression_trigger_id` / `expression_trigger_timestamp` keep their meaning (a re-trigger while moving restarts the emote; the flag applies to the new play). `talking`, `show_only_wearables`, wearables: unaffected. Tweens: same path as Transform in every engine (Unity computes the blend from `TargetPosition` vs `LastPosition` whether or not `IsPositionManagedByTween`; bevy from the `GlobalTransform` delta; godot never).
  - AvatarShape on the PLAYER entity (bevy honours it, bevy-explorer #1242) and on other players' entities: the flag is ignored; those avatars keep the explorer's input-driven cancel rules.
  - Writer: the scene. LWW (as the whole component). Scene-local: never relayed over rfc4 / Pulse, so no comms section and no `size: large`.
- **Prior art** (2026-10-10):
  - protocol `origin/main`, `origin/experimental-bevy`, `origin/protocol-squad`: `git grep -n -i -E 'keep_emote|emote_on_move|locomotion|walk' <branch> -- proto` finds no NPC locomotion/emote flag. Nearest: `avatar_locomotion_settings.proto` (player speeds, not animation), `input_modifier.proto:disable_walk` (player input); on `experimental-bevy` / `protocol-squad` only, `avatar_movement.proto` ("When absent the engine falls back to its built-in velocity-based selection (walk/run/jump/idle)") and `avatar_movement_info.proto` are the bevy movement-scene protocol for the player, not for NPCs.
  - `avatar_shape.proto` across branches: `main` and `experimental` end at `show_only_wearables = 12` (`experimental` only adds `enum AvatarEmoteMask`); `experimental-bevy` and `protocol-squad` add `repeated string force_render = 13`.
  - Open protocol PRs (`gh pr list --state open`, 31 PRs): only #472 (`experimental-bevy`, do not merge) and #202 (`protocol-squad`) touch `avatar_shape.proto`, both with `force_render = 13`. No PR proposes this flag.
  - ADRs: `git grep -n -i -E 'avatar_shape|avatarshape' origin/main -- content` in decentraland/adr: no hit; AvatarShape 1080 has no ADR. ADR-245 (player components) and ADR-215 (animation defaults) are the neighbours. No open ADR PR mentions avatar/emote/npc.
  - docs `creator/sdk7/interactivity/avatars/npc-avatars.md` (origin/main 9729496), verbatim: "Avatars play default idle animations while still." / "Animations on an `AvatarShape` play once, if you want the avatar to keep looping an animation, you should create a system that tells it to play the animation again every couple of seconds." The page never describes what happens to an emote when the NPC is moved.
  - sdk-skills `npcs/SKILL.md` ~120 and ~204 (quoted in section 1) describe walk/run along Transform/Tween moves; both lines change when this ships.
  - bevy vendored `crates/dcl_component/src/proto/decentraland/sdk/components/avatar_shape.proto`: `experimental-bevy` content with `force_render = 13` (comment drift on 12), so the next free tag there is 14 too.
  - Engine issues: bevy-explorer #1271 (open, read `AvatarEmoteCommand` as a play command for scene avatars), #1242 (open, AvatarShape on real players), #1244 / #683 (merged, expressionTriggerId fixes); godot-explorer #2690 (merged, masks + EmoteState), #1265 (merged, AvatarShape scene emotes); unity-explorer #5047 (closed). None covers locomotion vs emote on a moved NPC.
- **Alternatives considered**:
  1. **Engine-side change, no protocol change**: make every explorer keep NPC emotes under scene-driven motion by default. Loses: it changes released behaviour in bevy and the documented behaviour (sdk-skills), so deployed scenes that rely on "walks along the tween" change the day an engine ships it; and it would silently legislate the Unity question (muted transitions) without a decision.
  2. **Do nothing**: keep the re-trigger workaround. Loses: visible restarts, engine-dependent, and no way to express the intent.
  3. **Enum mode field** `optional AvatarMovementAnimation movement_animation = 14 { AMA_DEFAULT = 0; AMA_KEEP_EMOTE = 1; AMA_NONE = 2 }` (never animate locomotion). Loses today on YAGNI: the third value is speculative, godot's baseline already is `NONE`, and a later need can add an enum and deprecate the bool (#470 `max_player_distance` precedent). Kept as open question (a).
  4. **A play command with the flag** (e.g. reading `AvatarEmoteCommand` with a `keep_on_move` field for scene avatars). Loses: `AvatarEmoteCommand` is write-only in Unity (`WriteAvatarEmoteCommandSystem.cs`) and bevy (`emote_report.rs`), read as a command only in godot (#2690) and requested for bevy in #1271; this would be a medium/large change for a one-bit need.
  5. **Flag on `PBTween` / Transform**: wrong owner; Transform is a core component and the behaviour belongs to the avatar, not to the mover.
- **Compatibility**: additive; a new `optional bool`, no rename, no retype, no `optional` added to an existing field (`buf breaking` WIRE_JSON would flag all three). Field 13 is skipped because `experimental-bevy` / `protocol-squad` / bevy's vendored copy carry `force_render = 13`; per `reserve_bevy_numbers: comment` the skip is written as `// 13 is force_render on experimental-bevy` next to the new field, not as `reserved`. Not relayed over comms. Scenes that set the field on an explorer without support keep today's behaviour there (prost / protobuf-net ignore unknown fields; the SDK types it as optional).
- **Numbering preview** (`bash .claude/skills/protocol-feature/scripts/field-numbers.sh PBAvatarShape`, 2026-10-10, protocol origin/main d7ddc10, 31 open PRs scanned):

  ```
  == union (all sources; owners ordered: protocol branches, open PRs, engine copies, pins, other branches)
    PBAvatarShape: 1 id, 2 name, 3 body_shape, 4 skin_color, 5 hair_color, 6 eye_color, 7 expression_trigger_id,
                   8 expression_trigger_timestamp, 9 talking, 10 wearables, 11 emotes, 12 show_only_wearables, 13 force_render
    off-main (absent on origin/main; owner list):
      13 force_render origin/experimental-bevy,origin/protocol-squad,#202,#472,bevy,chore/scroll-result-id-align,feat/controls-customization,protocol-squad-sync-main
    NEXT_SAFE_FIELD=14 PBAvatarShape
  ```

  Engine copies: bevy vendored has 1-13; godot extracted copy (pin 0ff6038) has 1-12; unity pin d7ddc10 has 1-12; sdk pin 6402953 has 1-12.
- **ADR**: none (policy `adr_by_size`: small = none; #489 / #470 precedent). Recorded in the Decision log.
- **Open questions**:
  - (a) bool vs enum (alternative 3): decide at the design stop; the bundle proceeds with the bool.
  - (b) Unity baseline: is the muted `Emote -> Movement` transition on `dev` intentional (remote players cancel over the wire) or an accident for NPCs? If a moved NPC already keeps its emote on Unity, the Unity PR is a near no-op for `true`, and the team must decide whether `false` should start cancelling (parity with bevy and the docs). Not decided here; logged as a P1 for review.
  - (c) Godot: `false` can only mean "walk/run interrupts" once godot infers locomotion for moved AvatarShapes, which it does not today; file the parity-gap issue (`need tech test`) rather than widen this feature.
  - (d) Facing: the NPC keeps turning toward its travel direction (Unity `UpdateRotation`); the flag only affects the animation. Confirm with design.

## 3. Technology verification

Evidence from `bash .claude/skills/protocol-feature/scripts/engine-support.sh PBAvatarShape` and `git show` / `git grep` on the fetched branches (js-sdk-toolchain origin/main 60e3717, unity-explorer origin/dev 41a9e92, bevy-explorer origin/main ad56994, godot-explorer origin/main cada2d9, protocol origin/main d7ddc10; FETCH_HEAD 0-3 h old, no `--fetch` needed), 2026-10-10. The field does not exist yet, so L1 is the consumer of the message and the hook is where the flag would be read.

| Target | L0 schema (copy / pin) | L1 consumers (paths, generated dirs excluded) | Hook (path:symbol) | Baseline behaviour | Verdict | Effort | L2 runtime |
|---|---|---|---|---|---|---|---|
| js-sdk-toolchain | pin `1.0.0-34643020503.commit-6402953` in both `package.json` files (4 commits behind main; file present) | `test/ecs/components/AvatarShape.spec.ts` (two full literals ~17-21 / ~32-36); no `extended/AvatarShape.ts` on main; not in `GROWN_ONLY_COMPONENTS` | codegen only: new key in both spec literals, regenerated `playground-assets.api.md` (`keepEmoteOnMove?: boolean \| undefined;`), snapshots | the generated `PBAvatarShape` type gains an optional property; `create()` defaults unchanged | `feasible` | S (#1165, titled 'skin color alpha', which also added `showOnlyWearables`; #1560) | n/a |
| unity-explorer | pin `^1.0.0-37324405267.commit-d7ddc10` (= npm `next`, = main head); `AvatarShape.gen.cs` present; `ComponentID.AVATAR_SHAPE = 1080` | 146 hits; registration `ComponentsContainer.cs` `.Add(SDKComponentBuilder<PBAvatarShape>...AsProtobufComponent())`, `IDirtyMarker.cs` partial; scene->global twin via `AvatarShapeHandlerSystem.cs` (`globalWorld.Create(pbAvatarShape, ...)` ~79, `globalWorld.Set(..., pbAvatarShape)` on `IsDirty` ~102) so a new field is readable in the global world with no registration | `Explorer/Assets/DCL/Character/CharacterMotion/Systems/SDKAvatarShapesMotionSystem.cs:UpdateAnimations` (~110-135; query `[All(typeof(PBAvatarShape))]` ~40 gains `in PBAvatarShape` and the emote state): keep `movementBlendValue = 0` while `HasKeepEmoteOnMove && KeepEmoteOnMove` and an emote is playing; resolve at read time, never write back (#9902) | uncertain: both `Emote` and `Emote Loop` own a `MovementBlend > 0.1 -> Movement` transition with `m_Mute: 1` (`CharacterAnimator.controller` transitions `4154687653260660565` and `-7991627196901748505`, dst `-4050450968213979288` = `Movement`, parsed from origin/dev), and `CharacterEmoteSystem.CancelEmotes` only finishes when the animator leaves the Emote tags; `CancelEmotesByMovementInput` needs `MovementInputComponent` + `Profile` (local player only). Code says the emote survives and the NPC slides; legacy-animation emotes (`emoteReference.legacy`) bypass Mecanim | `feasible` (hook confirmed, 2-3 files); baseline `uncertain` | S (#3487 FOV, #9902 maxCameraDistance) | pending: a human runs the 4,25 scene with the PR build (agents cannot compile Unity) |
| bevy-explorer | vendored `avatar_shape.proto` = `experimental-bevy` content (`force_render = 13`), matches neither main nor experimental-bevy byte-wise (comment drift); `build.rs` stem and `SceneComponentId::AVATAR_SHAPE = 1080` present | `crates/avatar/src/lib.rs` `add_crdt_lww_component::<PbAvatarShape, AvatarShape>` (~160, `ComponentPosition::Any`); wrapper `AvatarShape(pub PbAvatarShape)` ~253; exhaustive literal `From<&UserProfile> for AvatarShape` ~263 (needs `keep_emote_on_move: None`); ~462 literal uses `..clone()` | `crates/avatar/src/animate.rs:animate` (~468 query; `velocity_cancels` ~625-627): add `Option<&AvatarShape>` and `Has<PrimaryUser>` to the avatars query and AND `!keep_emote_on_move` into `velocity_cancels`; the kept emote then claims the avatar so the velocity-selected walk/run (~660+) is not applied. Fallback hook: `npc_dynamics.rs:update_npc_velocity` ~49 reporting zero velocity (coarser: also idles after the emote) | emote cancelled on motion for every scene NPC (`maybe_foreign.is_none() && scene_anim.is_none() && source != SceneMovementAnim`); walk `<= 2.6 m/s`, else run. Headless (`NoRenderApp`, `AvatarCorePlugin` only) runs no animation | `feasible` | S (#962, #1158 two-file precedents) | pending: `just native-debug --realm http://127.0.0.1:8000 --preview --position 4,25`; console `/set_component <entity> AvatarShape {"keepEmoteOnMove":true,"expressionTriggerId":"dance"}` + `/inspect_component` before any SDK build |
| godot-explorer | `PROTOCOL_FIXED_VERSION_URL` pin commit `0ff6038` (15 behind main) lacks the field: needs a pin bump (which also pulls `avatar_nametag`, `explorer_item_purchase_result`, `explorer_ui_events_result`, `font_src` and turns the two `build.rs` proto patches into no-ops); not in `GROW_ONLY_SET_COMPONENTS` (correct, LWW) | `lib/src/scene_runner/components/avatar_shape.rs:update_avatar_shape` (~84; builds `avatar_shape_config` ~153-200 and calls `async_update_avatar`); `godot/src/decentraland_components/avatar/avatar.gd:async_update_avatar` ~528 reads the config | plumb: `avatar_shape.rs` `avatar_shape_config.set("keep_emote_on_move", ...)` -> `avatar.gd:async_update_avatar` stores it (through a static helper in `avatar_anim_helpers.gd`, `avatar.gd` is at 1885 of the 1900-line gdlint cap) -> `avatar.gd` ~1463 `emote_controller.process(self_idle or keep_emote_on_move)` becomes the gate once locomotion exists | AvatarShape never gets walk/jog/run: `dcl_avatar.rs` init `movement_type: ExternalController` ~244, `process` ExternalController arm ~576 only updates the parcel, `classify_locomotion` runs for `LerpTwoPoints` only; `avatar.gd` ~1460 `self_idle` true; `avatar_emote_controller.gd:process` ~1276 cancels only when `not idle`. So `true` is already today's behaviour and `false` has nothing to interrupt. Code-level only; no `PbAvatarShape {` literal under `lib/src` | `uncertain` (likely already the proposed `true` behaviour; inferred from code only; `false` needs NPC locomotion inference that does not exist) | S for the plumbing + pin bump; M if locomotion inference is added | pending: `cargo run -- run -- --preview --realm http://localhost:8000 --location 4,25 --skip-lobby`, phone via `https://mobile.dclexplorer.com/open?realm=sdk7testscenes.dcl.eth&position=4,25`; file `need tech test` |

- **Branch drift**: unity receives the field from `@dcl/protocol@next` after the merge (pin already at main head d7ddc10); the SDK pins an exact version (`6402953` today, so its repin to `@next` also pulls `font_src` #489 and three other commits); godot pins commit `0ff6038` and needs a deliberate bump (PR tarball, then the npm URL); bevy's vendored tree follows `origin/experimental-bevy`, so the bevy PR must hand-add field 14 to its copy and keep `force_render = 13`: byte-equality with main is impossible for this file until `force_render` lands on `main` (review compares the field list instead).
- **Cross-engine mismatches to decide** (from `references/subsystems.md`, extended):
  - Unity drives walk/run from the position delta but the animator's emote-to-movement exits are muted on `dev` (both `Emote` and `Emote Loop`); bevy cancels on velocity; godot never drives NPC locomotion. The three `false` baselines differ and this proposal does not harmonise them (open question (b), (c)).
  - `AvatarEmoteCommand` is write-only in Unity/bevy and a play command in godot (#2690, bevy #1271): not used by this design.
  - AvatarShape on the PLAYER entity is honoured in bevy (#1242): the flag is ignored there (semantics above; bevy gates with `Has<PrimaryUser>`).
  - Scene emotes are `loop: false` in Unity (`AvatarShapeHandlerSystem.cs` ~168/~181) and bevy (`EmoteCommand { r#loop: false }`, `lib.rs` ~859): the flag keeps the emote only until its natural end; looping stays a scene-side re-trigger.
  - Headless bevy runs no animation; Unity legacy-animation emotes bypass Mecanim (local-dev GLBs behave differently).
  - Godot masked emotes already survive movement; AvatarShape emotes are full body.
- **Runtime confirmation plan** (L2; plan mode, executed by a human or in execute mode):
  - Scene: sdk7-test-scenes `scenes/4,25-avatar-shape-keep-emote` (4,19-4,24 are taken on origin/main 06b52ff; 4,25 is free by `git ls-tree`; `npm run check-parcels` to run at the repo root). Base it on `scenes/4,19-avatar-shape-movement/src/index.ts`. Two NPCs side by side: **A** (`keepEmoteOnMove` unset) and **B** (`keepEmoteOnMove: true`); buttons **Play emote** (sets `expressionTriggerId: 'dance'`, bumps `expressionTriggerTimestamp` on both), **Move (Transform)** (jumps both targets 10 m), **Move (Tween)** (`Tween.Mode.Move` 6 s on both), **Replay while moving**. `scene.json` `worldConfiguration.name: sdk7testscenes.dcl.eth`.
  - Observable, one per case, baseline first (field absent on both): A behaves as the engine does today (record it per engine: walks / slides with emote / idle); then B with the flag: the emote keeps playing for its full length while B translates, no walk/run frames; after the emote ends B walks/runs if still moving (Unity, bevy) or idles (godot).
  - unity: `npm run start -- --explorer-alpha` from the scene folder, or `npm run start -- --mcp --skip-auth-screen true` driven through the sdk-skills `unity-explorer-mcp` skill for screenshots; otherwise a human runs `metaforge explorer run <PR>` and enters `sdk7testscenes.dcl.eth` at `4,25` (zone / SEPOLIA). Record `observed (who, how, date)`.
  - bevy: `just native-debug --realm http://127.0.0.1:8000 --preview --position 4,25`; console `/set_component`, `/inspect_component`, `/debug_dump_avatar`.
  - godot: `cargo run -- run -- --preview --realm http://localhost:8000 --location 4,25 --skip-lobby`; phones via the deeplink above.
- **Spikes / blockers**: no gating row is `blocked`. Unity: observe the baseline first (whether a moved NPC already keeps its emote) because it decides how much of the Unity PR is behaviour vs plumbing. Godot: file `need tech test` + `feature parity` issue "AvatarShape NPCs moved by Transform/Tween play no locomotion (ExternalController); confirm and decide whether to infer walk/run" so that `false` can mean something there later.

## 4. Definition

- **Final numbers**: field `keep_emote_on_move = 14` on `PBAvatarShape` (component id 1080 unchanged); `NEXT_SAFE_FIELD=14` from `scripts/field-numbers.sh PBAvatarShape` (2026-10-10). Checked: `origin/main`, `origin/experimental-bevy`, `origin/protocol-squad`, `origin/experimental`, 31 open PRs (#472 and #202 carry 13), bevy vendored copy (13), godot extracted copy (12), unity pin d7ddc10 (12), sdk pin 6402953 (12), plus the other `origin/*` branches the script unions. Skipped: **13** = `repeated string force_render` on `experimental-bevy` / `protocol-squad` / bevy; written as the comment `// 13 is force_render on experimental-bevy` (policy `reserve_bevy_numbers: comment`). Not a new component: no id, no `make check-component-id`.
- **Diff**: `protocol.diff` in this bundle (one file, +13 lines: doc comment + the field), produced against a scratch `git archive origin/main proto` export in a `mktemp -d` directory, never in the working tree.
- **Index line**: `public/sdk-components.proto` already has `import public "decentraland/sdk/components/avatar_shape.proto";` (line 13); no change.
- **Validation** (2026-10-10, buf 1.8.0 from `node_modules/.bin/buf`, scratch exports):
  - `buf lint <export>/proto`: **OK**.
  - `buf breaking <export>/proto --against <pristine export of origin/main>/proto`: **OK** (local comparison; `make buf-breaking` compares against GitHub `main` over the network, to run on the branch).
  - `git apply --check protocol.diff` on the pristine export: **OK**.
  - By eye: the new field is `optional`; no enum touched; no comment line contains both `option` and `ecs_component_id`.
  - To run on the real branch in execute mode: `make install && make buf-lint && make buf-breaking && make test` (`make test` runs `scripts/test.sh`: protoc TS + C# over `public/*.proto`, then `tsc`), `make list-components-ids` (1080 unchanged).
- **ADR**: none (policy, small).
- **Protocol PR**: `pr-protocol.md` (title `feat: add keep_emote_on_move to AvatarShape`, branch `feat/avatar-shape-keep-emote-on-move`, base `main`); tarball URL goes into `links.protocol_tarball` once CI posts "Test this pull request".

## 5. Implementation

Merge order: protocol -> (sdk | unity | bevy | godot on the PR tarball) -> repin to the published `@dcl/protocol@next` -> merge SDK and engines -> test scene -> docs / sdk-skills.

| Repo | Branch | Protocol source | Files / steps | Gate | PR | State |
|---|---|---|---|---|---|---|
| js-sdk-toolchain | feat/avatar-shape-keep-emote-on-move | PR tarball in both `package.json` -> `make update-protocol` (`@next`) | repin x2 + lockfiles; `test/ecs/components/AvatarShape.spec.ts` (`keepEmoteOnMove` in both literals); regenerated `packages/@dcl/playground-assets/etc/playground-assets.api.md`; `test/snapshots/**/*.crdt` goldens; no hand-written surface | `make build && make test && make lint` | `pr-sdk.md` | pending |
| unity-explorer | feat/avatar-shape-keep-emote-on-move (off `dev`) | `scripts/package.json` tarball -> `@next` + `npm run build-protocol` | regenerated `AvatarShape.gen.cs`; `SDKAvatarShapesMotionSystem.cs:UpdateAnimations` (+ query params); EditMode test `Character/CharacterMotion/Tests/SDKAvatarShapesMotionSystemShould.cs` | `npm run build-protocol`; Unity compile + `make test-editmode` (human) | `pr-unity.md` | pending; small track, no architect hand-off |
| bevy-explorer | feat/avatar-shape-keep-emote-on-move | hand-add field 14 to the vendored `avatar_shape.proto` (keep `force_render = 13`); say so in the PR | vendored proto; `crates/avatar/src/animate.rs:animate` (`velocity_cancels`); `crates/avatar/src/lib.rs` literal `keep_emote_on_move: None` | `cargo fmt --all -- --check && cargo clippy --locked -- -D warnings && cargo test --all` | `pr-bevy.md` | pending |
| godot-explorer | feat/avatar-shape-keep-emote-on-move | `PROTOCOL_FIXED_VERSION_URL` = PR tarball -> npm URL of the `next` build; wipe `lib/src/dcl/components/proto/`, `cargo run -- install --no-templates` | pin bump + literal fixes the bump causes (`git grep -n 'Pb[A-Za-z]* {' lib/src`); `lib/src/scene_runner/components/avatar_shape.rs` (config key + itest); `avatar_anim_helpers.gd` helper + `avatar.gd:async_update_avatar` read; parity issue filed | `cd lib && cargo fmt --all && cargo clippy -- -D warnings`; `cargo run -- build`; `cargo run -- run --itest`; `gdformat godot/ && gdlint godot/` | `pr-godot.md` | pending; alternative under `all-accounted`: issue only |
| sdk7-test-scenes | feat/avatar-shape-keep-emote-on-move | SDK PR tarballs -> published `@dcl/sdk` before merge (`test_scene_pin: published`) | `scenes/4,25-avatar-shape-keep-emote` | `npm run check-parcels`; `npm run build` in the scene | `pr-test-scene.md` | pending |
| docs / sdk-skills / adr | feat/avatar-shape-keep-emote-on-move | | docs: `creator/sdk7/interactivity/avatars/npc-avatars.md` (new `### Keep an animation while moving` under `## Animations`, version hint, ES copy pending), draft until an `@dcl/sdk` release; sdk-skills: `npcs/SKILL.md` ~120 / ~204, `sdk-scenes/references/components-reference.md`; adr: N/A (policy: small) | GitBook preview; `node --test tests/*.test.mjs` | `pr-docs.md`, `pr-sdk-skills.md` | pending |

Per-repo briefs with exact commands and PR bodies: `actions.md`.

## 6. Review

- **Alignment matrix result** (plan mode, nothing built): numbers 1080 / 14 consistent across the sources checked; `optional` on the new field; grow-only n/a (LWW); defaults: proto comment == proposed engine code == SDK (`undefined`); bevy vendored copy will NOT be byte-equal to main by design (field 13), compare the field list; godot pin must contain the merged commit; public index line already present.
- **Findings**: P0 none at draft time (becomes P0 under `all-accounted` if any engine has neither a PR nor a parity issue when the protocol PR is up). P1: (1) bevy vendored file cannot match main byte-wise, the PR must hand-merge and the reviewer must not "fix" it by copying main (would drop `force_render`); (2) Unity baseline unobserved: the muted animator exits may already keep the emote, so decide explicitly whether `false` should cancel on Unity; (3) godot pin bump pulls 15 commits incl. three components and surfaces the pre-existing grow-only drift (`ExplorerUiEventsResult`, `ExplorerItemPurchaseResult` missing from `GROW_ONLY_SET_COMPONENTS`); (4) godot `false` has no observable meaning until NPC locomotion inference exists (parity issue). P2: docs/sdk-skills lines that describe "walks along the tween" need the new caveat; `ai-sdk-context/sdk7-complete-reference.md` drifts separately; SDK repin to `@next` also pulls `font_src`.
- **Pins before merge**: SDK both `package.json` on a published build; unity `scripts/package.json` + lockfile + `.gen.cs` on the same `@next`; godot npm URL (not sdk-team-cdn); test scene on a published `@dcl/sdk`.
- **Merge-order readiness**: nothing open yet; all pending (see `review.md`).
- **Follow-ups**: docs draft PR, sdk-skills PR, godot parity issue (`need tech test`), Unity decision on the muted transitions, bevy #1271 unaffected.
- Report: `review.md`.

## Gate log

| Gate | Result | Date | By | Evidence |
|---|---|---|---|---|
| 1 need | passed | 2026-10-10 | model | section 1 |
| 2 design | passed | 2026-10-10 | model | section 2 |
| 3 tech-check | passed | 2026-10-10 | model | matrix + runtime plan |
| 4 define | passed | 2026-10-10 | model | protocol.diff + checks |
| 5 implement | passed | 2026-10-10 | model | per-repo gates |
| 6 review | passed | 2026-10-10 | model | review.md |

## Decision log

| Date | Phase | Decision | Policy value used | By |
|---|---|---|---|---|
| 2026-10-10 | 0 | Mode: plan (`--draft`, "dry run": all six phases, markdown only). Bundle dir from `PROTOCOL_FEATURE_OUT`. Canonical protocol clone: `<protocol>` (the harness names it; the extra clone under `Projects/decentraland/protocol` is 14 behind). sdk-skills is MISSING locally but is not counted by the merge gate; read via `gh api`. | `PROPOSAL_DIR` overridden by `PROTOCOL_FEATURE_OUT`; `MERGE_GATE=all-accounted` | model |
| 2026-10-10 | 0 | Classified `kind: field`, `size: small` (optional field on an existing component; precedent #489 / #470). No `--size` override. | size tracks (`references/process.md`) | model |
| 2026-10-10 | 1 | Need written from the request plus docs / sdk-skills text and engine issue searches; no originating issue exists, recorded as such. Today's behaviour claimed from code on the fetched branches, Unity marked unverified. | — | model |
| 2026-10-10 | 2 | Shape: `optional bool keep_emote_on_move = 14` on `PBAvatarShape`; `false`/unset = today's behaviour per engine; `true` = emote plays through scene-driven motion. Bool chosen over an enum (alternative 3) on YAGNI; recorded as open question (a). | propose rules: new fields `optional`, `false` = today | model |
| 2026-10-10 | 2 | Field 13 skipped (`force_render` on experimental-bevy / protocol-squad / bevy), written as a comment next to the new field. Target branch `main`. | `RESERVE_BEVY_NUMBERS=comment`; `ALLOW_EXPERIMENTAL_BEVY_FIRST=no` | model |
| 2026-10-10 | 2 | ADR: none. | `ADR_BY_SIZE` small: none | model |
| 2026-10-10 | 2 | Scene-local, not relayed: no comms section; stays `size: small`. | `V1_SCOPE` components, fields, enums, restricted-actions | model |
| 2026-10-10 | 3 | Verdicts: sdk feasible, unity feasible (baseline uncertain), bevy feasible, godot uncertain-likely-current-behaviour with a hook. No gating row blocked. L2 left `pending` for every engine (small track allows it); runtime plan on parcel 4,25. | `MERGE_GATE=all-accounted` (unity, bevy, godot each need a PR or a parity issue; sdk PR required) | model |
| 2026-10-10 | 3 | Godot: `false` cannot be honoured without NPC locomotion inference; out of scope, to be filed as a `need tech test` + `feature parity` issue, which also satisfies `all-accounted` for godot if the plumbing PR is not wanted. | `MERGE_GATE=all-accounted` | model |
| 2026-10-10 | 4 | Number 14 taken from `NEXT_SAFE_FIELD` (every branch, open PR and engine copy checked). Diff validated in scratch exports: buf lint OK, buf breaking OK (local), git apply --check OK; `make test` / network `make buf-breaking` listed as "to run". | `RESERVE_BEVY_NUMBERS=comment`; `ADR_BY_SIZE` small: none | model |
| 2026-10-10 | 5 | Briefs for sdk, unity, bevy, godot, test scene, docs, sdk-skills; adr N/A (policy). Protocol source while open: the PR tarball (placeholder until CI posts it); after merge `@next`. Unity is small: no `feature-description-unity.md`. Test scene must be repinned to a published SDK before merge. | `ROLLOUT_INCLUDES=test-scene, docs, sdk-skills`; `TEST_SCENE_PIN=published`; `EXECUTE_DELEGATION` not exercised (plan mode) | model |
| 2026-10-10 | 6 | Review written against the bundle only (no PRs exist): no P0; four P1 and four P2 recorded in `review.md`; merge-order readiness all unchecked; existing-PR / issue searches per engine cited. | `MERGE_GATE=all-accounted`; `REVIEWER_HANDLES` empty, CODEOWNERS named instead | model |
