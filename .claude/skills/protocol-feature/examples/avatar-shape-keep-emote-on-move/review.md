# Review: Keep an AvatarShape emote while the scene moves it (avatar-shape-keep-emote-on-move) — 2026-10-10

Scope: draft review of the bundle only. No PR exists: protocol PR (`feat/avatar-shape-keep-emote-on-move`, pending) against js-sdk-toolchain (pending), unity-explorer (pending), bevy-explorer (pending), godot-explorer (pending). Merge gate in force: `all-accounted` (unity, bevy and godot each need a linked implementation PR or a filed parity-gap issue, and the SDK PR must exist, before the protocol PR merges). Sources: `protocol.diff`, `actions.md`, the `pr-*.md` drafts, `scripts/field-numbers.sh PBAvatarShape`, `scripts/engine-support.sh PBAvatarShape`, `scripts/consumer-pins.sh` (all run 2026-10-10 against protocol origin/main d7ddc10).

## Alignment matrix

| Check | protocol | sdk | unity | bevy | godot | Result |
|---|---|---|---|---|---|---|
| component id / field numbers | 1080; `keep_emote_on_move = 14`; 13 skipped (`force_render` on experimental-bevy) | will follow the pin (codegen) | `ComponentID.AVATAR_SHAPE = 1080` on dev; field arrives with the regenerated `.gen.cs` | `SceneComponentId::AVATAR_SHAPE = 1080`; vendored copy must gain 14 and keep 13 | generated from the file name; field arrives with the pin bump | consistent (14 is `NEXT_SAFE_FIELD` across every branch, open PR and engine copy) |
| `optional` on new fields | yes | `keepEmoteOnMove?: boolean \| undefined` in api.md | `HasKeepEmoteOnMove` presence bit | prost `Option<bool>` | prost `Option<bool>` | ok |
| grow-only parity (SDK `GROWN_ONLY_COMPONENTS` · godot `GROW_ONLY_SET_COMPONENTS` · bevy `update_crdt`/`reg!` · unity `AsProtobufResult`) | n/a (LWW component) | not listed (correct) | `AsProtobufComponent()` (correct) | `add_crdt_lww_component` (correct) | not listed (correct) | ok for this feature; pre-existing drift reported below (P1-3) |
| defaults in proto comments == engine code == SDK helpers | `(default: false)` = today | `undefined` -> absent | read-time `HasX ? X : false`, never written back | `unwrap_or(false)` | `unwrap_or(false)` | ok as drafted; unset behaviour differs per engine by design (see P1-2, P1-4) |
| vendored / generated copy matches the merged proto | n/a | api.md regenerated | `.gen.cs` regenerated on the same build as `scripts/package.json` + lockfile | NOT byte-equal by design: experimental-bevy content + field 14 (compare field lists) | pin commit must contain the merge (npm URL) | to verify at review time |
| public index line present | already present (`public/sdk-components.proto` line 13) | n/a | n/a | n/a | n/a | ok |

Existing-PR / issue search for the merge gate (2026-10-10): `gh pr list --search 'AvatarShape emote' --state all` and `gh issue list --search 'AvatarShape emote move' --state all` on unity-explorer, bevy-explorer and godot-explorer, plus `--search 'AvatarShape'` on each: nothing covers locomotion vs emote on a moved NPC (nearest: bevy #1271 open "Read AvatarEmoteCommand as a play command", bevy #1242 open "Scene AvatarShape override of real players", godot #2690 merged masks/EmoteState, unity #5047 closed scene emotes on AvatarShape). So every engine starts unaccounted: a missing PR or parity issue is a P0 once the protocol PR is open.

## Findings

### P0 (blocks merge)
- none at draft time. Will become P0 under `all-accounted`: any of unity / bevy / godot with neither an implementation PR nor a parity-gap issue linked from the protocol PR, or no SDK PR, when the protocol PR is up for merge.

### P1 (should fix before merge)
- **bevy vendored file cannot be byte-equal to main.** `crates/dcl_component/src/proto/decentraland/sdk/components/avatar_shape.proto` carries `repeated string force_render = 13` (experimental-bevy); copying protocol `main` over it would delete a field bevy compiles against (`crates/avatar/src/lib.rs` literals, `force_render` consumers). The bevy PR must hand-add field 14 and the reviewer must compare the field list, not bytes. Evidence: `scripts/field-numbers.sh` (`bevy ... 13 force_render`), `references/repos/bevy.md`.
- **Unity baseline is unobserved and decides the meaning of `false`.** On `origin/dev` both `Emote` and `Emote Loop` own a muted (`m_Mute: 1`) `MovementBlend > 0.1 -> Movement` transition (`CharacterAnimator.controller` transitions `4154687653260660565` / `-7991627196901748505`, dst `Movement`), and no `CharacterEmoteSystem` cancel query matches an NPC (`CancelEmotesByMovementInput` needs `MovementInputComponent` + `Profile`). If a moved NPC already keeps its emote, the Unity PR changes nothing visible for `true` and the team must decide, before merge, whether `false` should start cancelling (parity with bevy and with the sdk-skills text "plays its walk animation along the tween"). Evidence: `Explorer/Assets/DCL/Character/CharacterMotion/Systems/SDKAvatarShapesMotionSystem.cs:UpdateAnimations`, `Explorer/Assets/DCL/AvatarRendering/Emotes/Systems/Play/CharacterEmoteSystem.cs:CancelEmotes`.
- **godot pin bump surfaces pre-existing grow-only drift.** Moving `PROTOCOL_FIXED_VERSION_URL` from `0ff6038` to the `next` build pulls `ExplorerUiEventsResult` (1220) and `ExplorerItemPurchaseResult` (1222), which the SDK lists in `GROWN_ONLY_COMPONENTS` but `lib/build.rs` `GROW_ONLY_SET_COMPONENTS` (6 entries) does not; they would register LWW. Unrelated to this feature, reported because the bump makes it real: add both names in the bump PR or file it. Evidence: `lib/build.rs` ~20-28 on origin/main; js-sdk-toolchain `scripts/protocol-buffer-generation/generateIndex.ts` ~18.
- **godot `false` has no observable meaning.** `dcl_avatar.rs` defaults AvatarShapes to `ExternalController` and nothing sets walk/jog/run for them, so `keep_emote_on_move=false` cannot interrupt anything there. The parity issue (`need tech test`, `feature parity`) must be filed and linked from the protocol PR so godot counts as accounted and the gap is tracked. Evidence: `lib/src/godot_classes/dcl_avatar.rs` ~244 / ~576, `godot/src/decentraland_components/avatar/avatar.gd` ~1460-1463.

### P2 (minor)
- docs and sdk-skills currently describe the walk-along-the-tween behaviour (`npcs/SKILL.md` ~120, ~204); both need the caveat and the 4,25 scene link, and `ai-sdk-context/sdk7-complete-reference.md` drifts separately.
- SDK repin to `@next` also pulls `font_src` (#489) and three other protocol commits (pin `6402953` is four behind); say so in the SDK PR body so the api.md diff is not mistaken for scope creep.
- Facing is unchanged (Unity `UpdateRotation` still turns the NPC toward its travel direction); the proto comment says "no walk/run is blended in" and the PR bodies say position and facing are untouched: keep both sentences aligned if design wants a "freeze facing" variant later (that would be a new field, not a change to this one).
- Protocol PR body: `make buf-breaking` runs only on pushes to upstream non-main branches; a fork PR gets no breaking check, so run it locally and quote the result.

## Pins before merge
- sdk: both `package.json` files pin a published build (no http/file); `check-local-deps` green — pending
- unity: `scripts/package.json`, lockfile and `AvatarShape.gen.cs` agree on a published `@next` build — pending
- godot: `PROTOCOL_FIXED_VERSION_URL` is an npm URL (`https://registry.npmjs.org/@dcl/protocol/-/protocol-1.0.0-<runId>.commit-<sha7>.tgz`), not sdk-team-cdn — pending
- bevy: vendored file = experimental-bevy content + field 14 (field list check) — pending
- test scene: pinned to a published `@dcl/sdk` per `TEST_SCENE_PIN=published` — pending

## Merge-order readiness
- [ ] protocol (PR not open; diff validated in scratch exports: buf lint OK, buf breaking OK local, git apply --check OK; `make test` to run)
- [ ] sdk
- [ ] unity
- [ ] bevy
- [ ] godot (PR or parity issue)
- [ ] test scene

Pending repins after the protocol merge: sdk (`make update-protocol`), unity (`npm install @dcl/protocol@next && npm run build-protocol`), godot (npm URL); bevy none.

## Follow-ups
- docs: `creator/sdk7/interactivity/avatars/npc-avatars.md` draft PR (`pr-docs.md`), ready at the `@dcl/sdk` release; ES copy pending.
- sdk-skills: `npcs/SKILL.md` + components reference (`pr-sdk-skills.md`).
- adr (Draft -> Living): N/A (policy: small, no ADR).
- non-gating engines / parity issues: godot `need tech test` issue on NPC locomotion inference (P1-4); Unity decision on the muted `Emote -> Movement` transitions for NPCs (P1-2); godot grow-only list drift (P1-3); bevy #1271 (AvatarEmoteCommand as play command) is unaffected by this design.
