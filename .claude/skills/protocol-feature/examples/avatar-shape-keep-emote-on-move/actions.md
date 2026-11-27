# Actions: Keep an AvatarShape emote while the scene moves it (avatar-shape-keep-emote-on-move)

Mode: plan (draft, dry run) · Protocol source while PRs are open: `<tarball URL from the "Test this pull request" comment on the protocol PR; shape https://sdk-team-cdn.decentraland.org/@dcl/protocol/branch//dcl-protocol-1.0.0-<runId>.commit-<sha7>.tgz, the double slash is real>` · After the protocol merge: `@dcl/protocol@next` (or the exact `1.0.0-<runId>.commit-<sha7>`).

Blocks are in merge order. Every block is a brief: nothing here was run. Steps that need a confirmation in execute mode are marked `[confirm]`. Paths are relative to each repo root; read facts from the fetched branch (`origin/main`, unity `origin/dev`) because the local clones are on feature branches.

## 0. Protocol (decentraland/protocol)
- Branch: `feat/avatar-shape-keep-emote-on-move` from `origin/main` (d7ddc10)
- Files: `proto/decentraland/sdk/components/avatar_shape.proto` (diff in `protocol.diff`: doc comment + `optional bool keep_emote_on_move = 14;` with the `// 13 is force_render on experimental-bevy` comment). `public/sdk-components.proto` already imports the file: no change.
- Commands: `make install && make buf-lint && make buf-breaking && make test`; `make list-components-ids` (1080 once)
- Gate: all green (pre-checked in scratch exports: buf lint OK, buf breaking OK against a local export of origin/main, `git apply --check` OK)
- PR: title `feat: add keep_emote_on_move to AvatarShape`; body `pr-protocol.md` `[confirm: gh pr create --repo decentraland/protocol --base main --body-file pr-protocol.md]`
- After CI: copy the tarball URL from the "Test this pull request" comment into `links.protocol_tarball` and into the SDK, unity and godot briefs below. `decentraland-bot` will post a P0/P1/P2 review; answer every P0/P1 before asking humans.

## 1. js-sdk-toolchain
- Branch: `feat/avatar-shape-keep-emote-on-move` from `origin/main` (60e3717)
- Protocol source: `npm i --save-exact "<tarball>"` in the repo root and in `packages/@dcl/sdk-commands/`; after the protocol merge `make update-protocol` (`@next`). Note: main pins `1.0.0-34643020503.commit-6402953`, four commits behind protocol main, so the repin also pulls `font_src` (#489) and friends; say so in the body.
- Files:
  - `package.json`, `package-lock.json`, `packages/@dcl/sdk-commands/package.json`, `packages/@dcl/sdk-commands/package-lock.json` (pin)
  - `test/ecs/components/AvatarShape.spec.ts`: add `keepEmoteOnMove: false` to the first literal (~17-21) and `keepEmoteOnMove: true` to the second (~32-36); `testComponentSerialization` round-trips both
  - `packages/@dcl/playground-assets/etc/playground-assets.api.md` (regenerated): `+    keepEmoteOnMove?: boolean | undefined;` inside `export interface PBAvatarShape`
  - `test/snapshots/**/*.crdt` goldens (regenerated; bundle sizes change)
  - No hand-written surface: no `extended/AvatarShape.ts` on main, not grow-only, not a UI prop
- Commands: `make install && make build && make test`; snapshots: `UPDATE_SNAPSHOTS=true node_modules/.bin/jest --runTestsByPath test/snapshots.spec.ts` then rerun without the env var; `grep -rn "ERR!" test/snapshots/` must be empty `[confirm: overwriting goldens]`; `node_modules/.bin/jest --colors --forceExit --testPathPatterns='test/ecs/components/AvatarShape'`
- Gate: `make build && make test && make lint` (CI also runs `make lint-packages`; `check-local-deps` blocks merge while the pin is a tarball URL)
- PR: `pr-sdk.md` `[confirm]`; title `feat(ecs): add keepEmoteOnMove to AvatarShape`

## 2. unity-explorer
- Branch: `feat/avatar-shape-keep-emote-on-move` from `origin/dev` (41a9e92)
- Protocol source: `cd scripts && npm install "<tarball>" && npm run build-protocol` (or `make upgrade-protocol-by-url URL=<tarball>`); after the merge `cd scripts && npm install @dcl/protocol@next && npm run build-protocol`. Not `make upgrade-protocol` (installs `@experimental`).
- Files:
  - `scripts/package.json`, `scripts/package-lock.json`, regenerated `Explorer/Assets/Protocol/DecentralandProtocol/AvatarShape.gen.cs` (`HasKeepEmoteOnMove` / `KeepEmoteOnMove`); no new `.gen.cs`, so no new `.meta`
  - `Explorer/Assets/DCL/Character/CharacterMotion/Systems/SDKAvatarShapesMotionSystem.cs`: `UpdateMotion` query gains `in PBAvatarShape pbAvatarShape` (replacing `[All(typeof(PBAvatarShape))]`) and `in CharacterEmoteComponent emote` (confirm the global twin created in `AvatarShapeHandlerSystem.cs` ~79 carries it; otherwise use `view.GetAnimatorCurrentStateTag(AnimatorEmoteLayers.BASE_LAYER_INDEX)` against `AnimationHashes.EMOTE` / `EMOTE_LOOP`); `UpdateAnimations` sketch:
    ```csharp
    bool keepEmote = pbAvatarShape is { HasKeepEmoteOnMove: true, KeepEmoteOnMove: true } && emote.IsPlayingEmote;
    float movementBlendValue = 0;
    if (!keepEmote && distanceToTarget >= DISTANCE_EPSILON) { ... as today ... }
    ```
    Resolve at read time, never write the default back into the PB (#9902 presence pitfall). `UpdatePosition` / `UpdateRotation` untouched (the NPC still translates and turns).
  - `Explorer/Assets/DCL/Character/CharacterMotion/Tests/SDKAvatarShapesMotionSystemShould.cs` (EditMode, `UnitySystemTestBase<SDKAvatarShapesMotionSystem>`, next to `ApplyDragShould.cs`; the folder already has `CharacterMotion.Tests.asmref`): flag set + emote playing -> `MovementBlendValue == 0`; flag set + no emote -> blend from speed; flag unset -> blend from speed.
- Baseline to observe first (human): on `dev` the `Emote` / `Emote Loop` -> `Movement` transitions on `MovementBlend > 0.1` are muted in `CharacterAnimator.controller`, so a moved NPC may already keep its emote and slide. If so, the PR body must say that `true` makes the behaviour explicit and that `false` keeps the current (muted) behaviour, and link the team decision on whether to unmute for NPCs (P1 in `review.md`).
- Gate: `cd scripts && npm run build-protocol`; Unity compile, `make test-editmode TEST_FILTER=SDKAvatarShapesMotionSystemShould` and the play test are a human step (`metaforge explorer run <PR>` at `sdk7testscenes.dcl.eth` `4,25`)
- Hand-off: none (small track); `feature-description-unity.md` not written
- PR: `pr-unity.md` `[confirm]`; title `feat: sdk | AvatarShape keepEmoteOnMove`

## 3. bevy-explorer
- Branch: `feat/avatar-shape-keep-emote-on-move` from `origin/main` (ad56994)
- Protocol source: do NOT copy main's `avatar_shape.proto` over the vendored one (it would drop `repeated string force_render = 13`, which bevy compiles against). Hand-edit `crates/dcl_component/src/proto/decentraland/sdk/components/avatar_shape.proto`: add the doc-comment paragraph and `optional bool keep_emote_on_move = 14;` after `force_render = 13`. Say in the PR: "vendored proto = `experimental-bevy` content plus field 14 from decentraland/protocol#N".
- Files:
  - the vendored proto (above); no `build.rs` / `SceneComponentId` change (existing component)
  - `crates/avatar/src/lib.rs` ~263 `impl From<&UserProfile> for AvatarShape`: add `keep_emote_on_move: None,` (E0063 otherwise); the ~462 literal uses `..clone()` and is safe; re-check with `git grep -n 'PbAvatarShape {' origin/main -- crates | grep -v dcl_component/src/proto`
  - `crates/avatar/src/animate.rs:animate` (~468): add `Option<&AvatarShape>` and `Has<PrimaryUser>` to the `avatars` query tuple, then
    ```rust
    let keep_emote_on_move = !is_primary
        && maybe_shape.is_some_and(|s| s.0.keep_emote_on_move.unwrap_or(false));
    let velocity_cancels = maybe_foreign.is_none()
        && scene_anim.is_none()
        && active_emote.source != ActiveEmoteSource::SceneMovementAnim
        && !keep_emote_on_move;
    ```
    The kept `requested_emote` claims the avatar, so the velocity-selected walk/run (~660+) is not applied until the emote finishes or the command changes. Fallback if the query change is unwelcome: `crates/avatar/src/npc_dynamics.rs:update_npc_velocity` ~49 reports `Vec3::ZERO` for flagged NPCs (coarser: idles after the emote too).
  - Headless: no change (`AvatarCorePlugin` only, no animation)
- Verification before opening (to run): `just native-debug --realm http://127.0.0.1:8000 --preview --position 4,25`; console `/set_component <entity> AvatarShape {"expressionTriggerId":"dance","keepEmoteOnMove":true}` then move the entity via the scene; `/inspect_component <entity> AvatarShape` shows the camelCase key; `/debug_dump_avatar`
- Gate: `cargo fmt --all -- --check && cargo clippy --locked -- -D warnings && cargo test --all` (`taplo fmt --check --diff` untouched)
- PR: `pr-bevy.md` `[confirm]`; title `Keep an AvatarShape emote playing while the scene moves it`

## 4. godot-explorer
- Branch: `feat/avatar-shape-keep-emote-on-move` from `origin/main` (cada2d9)
- Protocol source: set `PROTOCOL_FIXED_VERSION_URL` in `src/install_dependency.rs` to the PR tarball (CDN URL) while the protocol PR is open; before merge, to `https://registry.npmjs.org/@dcl/protocol/-/protocol-1.0.0-<runId>.commit-<sha7>.tgz` of the `next` build that contains the merge. Then `rm -rf lib/src/dcl/components/proto && cargo run -- install --no-templates && cargo run -- build`.
- Side effects of the bump (pin `0ff6038` is 15 commits behind main): `avatar_nametag` (1221), `explorer_ui_events_result` (1220), `explorer_item_purchase_result` (1222), `font_src` fields and `PBAvatarEmoteCommand.state` arrive; `lib/build.rs:patched_avatar_emote_command_proto` / `patched_rfc4_comms_proto` become no-ops (keep `EmoteState` at file scope); new exhaustive-literal breaks: `git grep -n 'Pb[A-Za-z]* {' lib/src` after the install and fix with `..Default::default()` (`#[allow(clippy::needless_update)]`). Recommended: land the bump as its own `chore: bump @dcl/protocol pin` PR first (`No QA needed — no behavior change`), then this feature PR on top.
- Files:
  - `src/install_dependency.rs` (pin)
  - `lib/src/scene_runner/components/avatar_shape.rs:update_avatar_shape` (~153-200, the `avatar_shape_config` dictionary): `avatar_shape_config.set("keep_emote_on_move", new_value.keep_emote_on_move.unwrap_or(false));` next to `expression_trigger_timestamp`; itest in a non-`cfg(test)` `mod test` with `PbAvatarShape { keep_emote_on_move: Some(true), ..Default::default() }` via `SceneCrdtStateProtoComponents::get_avatar_shape_mut(&mut crdt_state).put(...)`
  - `godot/src/decentraland_components/avatar/avatar_anim_helpers.gd` (`class_name AvatarAnimHelpers`): `static func keep_emote_on_move(avatar, config: Dictionary) -> bool` (reads `config.get("keep_emote_on_move", false)`), because `avatar.gd` sits at 1885 lines against the 1900-line `.gdlintrc` cap
  - `godot/src/decentraland_components/avatar/avatar.gd:async_update_avatar` (~528): store `keep_emote_on_move`; `_process` ~1463: `emote_controller.process(self_idle or keep_emote_on_move)` so the flag holds once locomotion inference exists. Today nothing sets walk/jog/run for an AvatarShape (`dcl_avatar.rs` `ExternalController` ~244 / ~576), so there is no behaviour change on this PR.
  - Logging in the per-entity path: `tracing::debug!` only (Sentry quota; `REVIEW.md` Tier 2 #14)
- Parity issue to file (`gh issue create -R decentraland/godot-explorer`, labels `enhancement`, `mobile`, `feature parity`, `need tech test`; Problem / Scope / Deliverables / References, no implementation direction): "AvatarShape NPCs moved by Transform/Tween play no walk/run animation; confirm on device and decide whether to infer locomotion like Unity/bevy; `keepEmoteOnMove=false` depends on it" `[confirm: gh issue create]`. Under `MERGE_GATE=all-accounted` this issue alone accounts for godot if the plumbing PR is deferred.
- Gate: `cd lib && cargo fmt --all && cargo clippy -- -D warnings`; `cargo run -- build`; `cargo run -- run --itest`; `gdformat godot/ && gdlint godot/`
- PR: `pr-godot.md` `[confirm]`; mobile builds via the `build` label `[confirm]`; title `feat: AvatarShape keep_emote_on_move`

## 5. sdk7-test-scenes
- Folder `scenes/4,25-avatar-shape-keep-emote` (4,19-4,24 taken on origin/main 06b52ff; 4,25 free by `git ls-tree`); copy the layout of `scenes/4,19-avatar-shape-movement/` (`.dclignore`, `.gitignore`, `README.md`, `images/scene-thumbnail.png`, `package.json`, `scene.json` with `worldConfiguration.name: sdk7testscenes.dcl.eth`, `src/index.ts`, `tsconfig.json`)
- `src/index.ts` sketch: two NPCs **A** (no flag) and **B** (`keepEmoteOnMove: true`) created with the 4,19 `CreateAvatarShape` helper, 3 m apart; click cubes: **Play emote** (`expressionTriggerId = 'dance'`, `expressionTriggerTimestamp++` on both), **Move (Transform)** (both `Transform.getMutable(e).position` jump 10 m, alternating), **Move (Tween)** (`Tween.create` `Mode.Move` 6000 ms on both), **Replay while moving**; on-screen `TextShape` labels "A: default" / "B: keepEmoteOnMove"
- `npm install` at the repo root then `npm run check-parcels` (expects `✅ No collisions found`); in the scene `npm install` + `npm run build` + `npx tsc --noEmit`
- Pin: the SDK PR's `@dcl/sdk` and `@dcl/js-runtime` tarballs while open; repin to a published `@dcl/sdk` (or `@next`) before the scene PR merges (`TEST_SCENE_PIN=published`) and say so in the body
- Gate: `npm run build` in the scene; CI check `Deploy scenes/4,25-avatar-shape-keep-emote`
- PR: `pr-test-scene.md` `[confirm]`; title `feat: AvatarShape keepEmoteOnMove test scene at 4,25`

## 6. docs / sdk-skills / adr
- docs (decentraland/docs, base `main`, draft PR): `creator/sdk7/interactivity/avatars/npc-avatars.md` — under `## Animations` add `### Keep an animation while moving` (snippet with `keepEmoteOnMove: true`, what happens when the emote ends) and the version hint `**📔 Note**: \`keepEmoteOnMove\` requires \`@dcl/sdk\` version <release> or newer.`; no new page, so `SUMMARY.md` / `avatars/README.md` unchanged; ES copy (`creator-esp/sdk7/interactivity/npc-avatars.md`) pending; `ai-sdk-context/sdk7-complete-reference.md` lists component fields and drifts separately. Keep draft until an `@dcl/sdk` release exposes the field (the weekly `docswriter/sync-*` skips unreleased protocol work). PR: `pr-docs.md` `[confirm: gh pr create --repo decentraland/docs --base main --draft]`
- sdk-skills (decentraland/sdk-skills, not cloned; `gh api` reads): `npcs/SKILL.md` ~120 (add the caveat after "the avatar plays its walk animation along the tween") and ~204 (4,19 line, add the 4,25 scene), `sdk-scenes/references/components-reference.md` (AvatarShape row); `.sync-state.json` untouched. PR: `pr-sdk-skills.md` `[confirm]`; title `feat(npcs): teach AvatarShape keepEmoteOnMove`
- adr: N/A (policy `ADR_BY_SIZE` small: none)

## Merge order checklist
- [ ] protocol merged -> `@next` published
- [ ] sdk repinned to the published build (both package.json files; `check-local-deps` green)
- [ ] unity repinned (`scripts/package.json`, lockfile, `.gen.cs` regenerated on the same build)
- [ ] godot pin is an npm URL, not sdk-team-cdn
- [ ] bevy vendored file = `experimental-bevy` content + field 14 (field list compared; byte-equality with main not expected while `force_render` is off-main)
- [ ] sdk + engines merged (or godot parity issue filed)
- [ ] test scene merged on a published SDK
- [ ] docs (draft -> ready at the SDK release) / sdk-skills follow-ups filed; adr N/A
