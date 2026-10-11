# Subsystem -> path table per engine

Where each protocol feature area is implemented in js-sdk-toolchain, unity-explorer, bevy-explorer and godot-explorer, so a tech-check names the hook file per engine instead of guessing.

## Contents

- [Path table](#path-table)
- [Cross-engine mismatches](#cross-engine-mismatches)
- [How to use](#how-to-use)
- [Last verified](#last-verified)

## Path table

Branches: js-sdk-toolchain `origin/main`, unity-explorer `origin/dev`, bevy-explorer `origin/main`, godot-explorer `origin/main`. Every path below was listed on that branch on the date in the footer; line numbers are written `~N` because they move.

| Area | js-sdk-toolchain | unity-explorer | bevy-explorer | godot-explorer |
|---|---|---|---|---|
| Avatar locomotion vs emotes (AvatarShape 1080) | no `extended/AvatarShape.ts` on main (only on `origin/experimental-bevy`, for `forceRender`); `test/ecs/components/AvatarShape.spec.ts` (add the key to both literals); rest is codegen | `Explorer/Assets/DCL/SDKComponents/AvatarShape/Systems/AvatarShapeHandlerSystem.cs` (scene -> global twin, `loop: false`); `Explorer/Assets/DCL/SDKComponents/AvatarShape/Systems/UpdateAvatarShapeInterpolateMovementSystem.cs`; `Explorer/Assets/DCL/Character/CharacterMotion/Systems/SDKAvatarShapesMotionSystem.cs:UpdateAnimations` (sets `MovementBlend`); `Explorer/Assets/DCL/AvatarRendering/AvatarShape/Assets/Animator/CharacterAnimator.controller` (`Emote` and `Emote Loop` each own a `-> Movement` transition on `MovementBlend > 0.1`, both muted on `dev`); `Explorer/Assets/DCL/AvatarRendering/Emotes/Systems/Play/CharacterEmoteSystem.cs:CancelEmotes`; plugin `Explorer/Assets/DCL/PluginSystem/World/AvatarShapePlugin.cs` | `crates/avatar/src/lib.rs` (`add_crdt_lww_component::<PbAvatarShape, AvatarShape>` with `ComponentPosition::Any` ~160; exhaustive `impl From<&UserProfile> for AvatarShape` ~261; `expression_trigger_id` -> `EmoteCommand { r#loop: false, mask: FullBody }` ~816); `crates/avatar/src/npc_dynamics.rs:update_npc_velocity`; `crates/avatar/src/animate.rs:animate` (`velocity_cancels` ~625); `crates/avatar/src/emote_report.rs` | `lib/src/scene_runner/components/avatar_shape.rs:update_avatar_shape`; `lib/src/godot_classes/dcl_avatar.rs` (default `movement_type: AvatarMovementType::ExternalController` ~244; walk/jog/run never set for AvatarShape); `godot/src/decentraland_components/avatar/avatar.gd:_process` (1885 lines against `.gdlintrc` `max-file-lines: 1900`); `godot/src/decentraland_components/avatar/avatar_emote_controller.gd:process(idle)`; `godot/src/decentraland_components/avatar/avatar_anim_helpers.gd:locomotion_conditions` (put new avatar logic here) |
| Emote commands / masks (AvatarEmoteCommand 1088, `AvatarMask`) | `'AvatarEmoteCommand'` in `GROWN_ONLY_COMPONENTS` (`scripts/protocol-buffer-generation/generateIndex.ts`); enum from protocol `proto/decentraland/sdk/components/common/avatar_mask.proto` | `Explorer/Assets/DCL/Multiplayer/SDK/Systems/SceneWorld/WriteAvatarEmoteCommandSystem.cs` (`AppendMessage<PBAvatarEmoteCommand, ...>`); `Explorer/Assets/DCL/Multiplayer/SDK/Systems/GlobalWorld/AvatarEmoteCommandPropagationSystem.cs`; write-only | `crates/avatar/src/animate.rs:handle_trigger_emotes` (`RpcCall::TriggerEmote`, `RpcCall::StopEmote`); `crates/avatar/src/emote_report.rs` (`scene.update_crdt(SceneComponentId::AVATAR_EMOTE_COMMAND, CrdtType::GO_ANY, ...)`); `crates/common/src/structs.rs:EmoteCommand`; write-only | `lib/src/scene_runner/components/avatar_shape.rs:update_avatar_shape_emote_command` (reads dirty GOS `get_avatar_emote_command` as a play command); `lib/src/avatars/avatar_scene.rs`, `lib/src/avatars/scene_emote.rs`, `lib/src/avatars/emote_mask.rs` (`-1` = full body sentinel); `lib/build.rs:patched_avatar_emote_command_proto` (build-time patch for fields the pin lacks) |
| UI (UiTransform, UiText, UiInput, UiDropdown, UiBackground, UiInputBinding) | `packages/@dcl/react-ecs/src/components/types.ts:EntityPropTypes`; `packages/@dcl/react-ecs/src/react-ecs.ts:EntityComponents`; `packages/@dcl/react-ecs/src/reconciler/index.ts:getComponentId`; `packages/@dcl/react-ecs/src/reconciler/utils.ts:entityComponent`; hand-written `packages/@dcl/react-ecs/src/components/Label/types.ts:UiLabelProps` and `packages/@dcl/react-ecs/src/components/uiTransform/types.ts:UiTransformProps`; `Input/types.ts` and `Dropdown/types.ts` extend `Omit<PB...>`; specs `test/react-ecs/*.spec.tsx` | `Explorer/Assets/DCL/SDKComponents/SceneUI/Systems/{UITransform,UIText,UIInput,UIDropdown,UIBackground,UIPointerEvents,UICanvasInformation}/` plus `Explorer/Assets/DCL/SDKComponents/SceneUI/Systems/UIFixPbPointerEventsSystem.cs` | `crates/scene_runner/src/update_world/scene_ui/mod.rs` (`add_crdt_lww_component` for `PbUiTransform`, `PbUiBackground`, `PbUiText`, `PbUiInput`, `PbUiDropdown`, `PbUiCanvas` ~429-449); `crates/scene_runner/src/update_world/scene_ui/{ui_text,ui_input,ui_dropdown,ui_background,ui_pointer}.rs`; `crates/scene_runner/src/update_world/fonts.rs:SceneFontsPlugin` | Rust only: `lib/src/scene_runner/components/ui/{scene_ui,ui_transform,ui_text,ui_input,ui_dropdown,ui_background,ui_scroll,ui_input_binding,style}.rs` (`update_ui_<name>`, `update_scene_ui`); `godot/src/ui/` is the explorer HUD, not SDK UI; `godot/src/decentraland_components/ui/` does not exist |
| Pointer events / results (PointerEvents, PointerEventsResult) | `packages/@dcl/ecs/src/systems/events.ts:EventSystemOptions` (`maxCameraDistance` precedent) | `Explorer/Assets/DCL/Interaction/Systems/{ProcessPointerEventsSystem,WritePointerEventResultsSystem,PlayerOriginatedRaycastSystem,PlayerOriginatedProximitySystem}.cs`; `Explorer/Assets/DCL/Interaction/PlayerOriginated/Utility/InteractionInputUtils.cs` (`HasMaxDistance`, `HasMaxCameraDistance` resolved at read time) | `crates/scene_runner/src/update_world/pointer_events.rs` (`add_crdt_lww_component::<PbPointerEvents, PointerEvents>` ~52); `crates/scene_runner/src/update_scene/pointer_results.rs` (`MonotonicTimestamp<PbPointerEventsResult>`); inspector `reg!(PbPointerEventsResult, ..., ro)` in `crates/scene_inspector/src/manual_registry.rs` | `lib/src/scene_runner/components/pointer_events.rs:update_scene_pointer_events` and `:pointer_events_system` (push `scene.pointer_events_result`); flushed by `lib/src/scene_runner/update_scene.rs` arm `SceneUpdateState::ComputeCrdtState` (`get_pointer_events_result_mut`) |
| GLTF / Animator (GltfContainer, Animator, MeshCollider, loading state) | `packages/@dcl/ecs/src/components/extended/{Animator,MeshCollider,MeshRenderer}.ts`; `packages/@dcl/ecs/src/systems/assetLoad.ts:createAssetLoadLoadingStateSystem` | `Explorer/Assets/DCL/Infrastructure/ECS/Unity/GLTFContainer/{Systems,Components,Asset}/` (`Systems/WriteGltfContainerLoadingStateSystem.cs` uses `PutMessage`); `Explorer/Assets/DCL/PluginSystem/World/{GltfContainerPlugin,AnimatorPlugin,AssetsCollidersPlugin}.cs`; `Explorer/Assets/DCL/SDKComponents/Animator/{Components,Systems,Tests}/` (`Systems/LegacyAnimationPlayerSystem.cs` is the non-Mecanim path) | `crates/scene_runner/src/update_world/gltf_container.rs` (`PbGltfContainer`, `PbGltfNode`, `PbGltfNodeModifiers`); `crates/scene_runner/src/update_world/animation.rs` (`PbAnimator`); `crates/scene_runner/src/update_world/mesh_collider.rs` (`PbMeshCollider`) | `lib/src/scene_runner/components/{gltf_container,animator,mesh_collider}.rs` (`update_<name>`); `lib/src/scene_runner/components/gltf_node_modifiers/`; `godot/src/decentraland_components/{gltf_container,gltf_loading_coordinator}.gd` |
| Audio / video (AudioSource, AudioStream, VideoPlayer, AudioAnalysis, AudioEvent, VideoEvent) | `packages/@dcl/ecs/src/components/extended/{AudioSource,AudioStream,AudioAnalysis}.ts`; `packages/@dcl/ecs/src/systems/audioEvents.ts:createAudioEventsSystem`; `packages/@dcl/ecs/src/systems/videoEvents.ts:createVideoEventsSystem` | `Explorer/Assets/DCL/SDKComponents/AudioSources/Systems/` (`AudioEventsSystem.cs` `AppendMessage<PBAudioEvent, ...>`); `Explorer/Assets/DCL/SDKComponents/MediaStream/Systems/` (`VideoEventsSystem.cs` `AppendMessage<PBVideoEvent, ...>`); `Explorer/Assets/DCL/SDKComponents/AudioAnalysis/AudioAnalysisSystem.cs` | `crates/av/src/lib.rs` (`add_crdt_lww_component` for `PbAudioStream`, `PbVideoPlayer` ~387-391; event writes with `CrdtType::GO_ANY`); `crates/av/src/audio_source.rs` (`add_crdt_lww_component::<PbAudioSource, AudioSource>`); `crates/av/src/{video_player,video_stream}.rs`; no `audio_analysis.proto` in the vendored tree | `lib/src/scene_runner/components/{audio_source,audio_stream,video_player,audio_analysis}.rs` (`update_<name>`); `godot/src/decentraland_components/{audio_source,av_player,video_player}.gd` |
| Restricted actions / kernel APIs (`kernel/apis/*.proto`) | `scripts/rpc-api-generation/index.ts` -> gitignored `packages/@dcl/js-runtime/apis.d.ts` via `make compile_apis` (Makefile `PBS_TS` rule over `node_modules/@dcl/protocol/proto/decentraland/kernel/apis/*.proto`; end to end unverified, label unmapped); hand-written `~system/*` callers in `packages/@dcl/sdk/src/{index,observables,platform/index}.ts` | 4 layers: `Explorer/Assets/StreamingAssets/Js/Modules/RestrictedActions.js` -> `Explorer/Assets/DCL/Infrastructure/SceneRuntime/Apis/Modules/RestrictedActionsApi/{RestrictedActionsAPIWrapper,IRestrictedActionsAPI}.cs` -> `Explorer/Assets/DCL/Infrastructure/CrdtEcsBridge/JsModulesImplementation/RestrictedActions/RestrictedActionsAPIImplementation.cs` (+ `Tests/`); registered in `Explorer/Assets/DCL/Infrastructure/SceneRuntime/ISceneRuntime.cs` by `sceneRuntime.Register("UnityRestrictedActionsApi", ...)` | 4 places + `RpcCall`: `crates/dcl/src/js/modules/RestrictedActions.js` -> `crates/dcl/src/js/restricted_actions.rs` -> `crates/dcl_deno/src/js/op_wrappers/restricted_actions.rs` (`ops()`) and `crates/dcl_wasm/src/inner/op_wrappers/restricted_actions.rs` -> `crates/common/src/rpc/mod.rs:RpcCall` -> consumer (`crates/restricted_actions/src/`, `crates/avatar/src/animate.rs:handle_trigger_emotes`); `kernel/apis/*.proto` vendored but absent from `crates/dcl_component/build.rs` | 5 hops: `lib/src/dcl/js/js_modules/RestrictedActions.js` (sentinels `?? NaN`, `?? -1`, `?? ''`) -> `lib/src/dcl/js/restricted_actions.rs` (`#[op2]`, `ops()`) -> `lib/src/dcl/scene_apis.rs:RpcCall` -> `lib/src/scene_runner/rpc_calls/mod.rs:process_rpcs` -> `lib/src/scene_runner/rpc_calls/handle_restricted_actions.rs` (`_player_is_inside_scene`); `kernel/apis` absent from `lib/build.rs` |
| Result / grow-only components (engine-written) | `GROWN_ONLY_COMPONENTS` in `scripts/protocol-buffer-generation/generateIndex.ts` (8 entries on main, ending with `ExplorerUiEventsResult`, `ExplorerItemPurchaseResult`; the proto needs `timestamp`); guard with an `addValue` spec | `.AsProtobufResult()` in `Explorer/Assets/DCL/Infrastructure/Global/ComponentsContainer.cs` (engine-written, no `IDirtyMarker`); grow-only writers call `ecsToCRDTWriter.AppendMessage<PBX, ...>`, LWW results call `PutMessage` | `RendererSceneContext::update_crdt(id, CrdtType::GO_ANY, entity, &pb)` in `crates/scene_runner/src/renderer_context.rs` ~365 plus `reg!(PbX, SceneComponentId::X, CrdtType::GO_ANY, ro)` in `crates/scene_inspector/src/manual_registry.rs`; `add_crdt_go_component` (`crates/scene_runner/src/update_world/mod.rs`) is defined but has no call site on main | `GROW_ONLY_SET_COMPONENTS: [&str; 6]` in `lib/build.rs` (everything else registers LWW; lacks `ExplorerUiEventsResult` and `ExplorerItemPurchaseResult`); values written from `lib/src/scene_runner/update_scene.rs` `ComputeCrdtState` |
| Comms (rfc4 LiveKit, v3 archipelago, pulse) | not consumed directly | `Explorer/Assets/DCL/Multiplayer/Movement/` (`Encoder/`, `Systems/PulseMultiplayerBus*.cs`, `Systems/LiveKitMovementMessageBus.cs`); `Explorer/Assets/DCL/Multiplayer/Emotes/LiveKitEmotesMessageBus.cs`; `Explorer/Assets/DCL/Multiplayer/Profiles/`; `Explorer/Assets/DCL/Multiplayer/Connections/{Pulse,Archipelago}/`; `Explorer/Assets/DCL/Multiplayer/SDK/Systems/{GlobalWorld,SceneWorld}/` | `crates/comms/src/global_crdt.rs:update_crdt` ~405; `crates/comms/src/livekit/`; `crates/comms/src/pulse/{plugin,transport,framing}.rs`; `crates/comms/src/movement_compressed.rs`; `crates/comms/src/archipelago.rs` | `lib/src/comms/communication_manager.rs:send_rfc4`; `lib/src/comms/adapter/{livekit,message_processor,movement_compressed,archipelago}.rs`; `lib/src/comms/pulse/{transport,decoder,pulse_room}.rs`; `lib/build.rs:patched_rfc4_comms_proto`; path-level only: v1 treats comms as tech-check only, implementation unmapped |

## Cross-engine mismatches

Surface these in the tech matrix whenever the feature touches the area; each one changes a verdict or a semantics paragraph.

### Avatar locomotion vs emotes

- Unity: `SDKAvatarShapesMotionSystem.cs:UpdateAnimations` drives `MovementBlend` from the NPC's position delta (Tween-driven moves too), but on `origin/dev` the `Emote` and `Emote Loop` states' `-> Movement` transitions on `MovementBlend > 0.1` both carry `m_Mute: 1` (verified 2026-10-10 by parsing `CharacterAnimator.controller`), so the code suggests a moved NPC keeps its emote and slides; the live exits are `EmoteStop`, `EmoteRefresh` and the `EmoteLoop`-false exit-time transitions. Treat the baseline as `uncertain` until observed; any flag still belongs in `UpdateAnimations` (keep `MovementBlend` at 0 while an emote plays), not in `AvatarShapeHandlerSystem.cs`.
- Bevy cancels through `crates/avatar/src/animate.rs` `velocity_cancels` (true for every non-foreign avatar), with velocity from `npc_dynamics.rs:update_npc_velocity`.
- Godot never infers NPC locomotion: `dcl_avatar.rs` defaults to `ExternalController` and nothing sets walk/jog/run for an AvatarShape, so moved NPCs stay idle and keep their emote today. Code-only inference: the godot row stays `uncertain` until an L2 observation (see `.claude/skills/protocol-feature/references/repos/verification.md`).
- `AvatarEmoteCommand` is write-only in Unity (`WriteAvatarEmoteCommandSystem.cs`) and Bevy (`emote_report.rs`) but read as a play command in Godot (`avatar_shape.rs:update_avatar_shape_emote_command`, godot-explorer #2690).
- AvatarShape on the PLAYER entity is honoured in Bevy (`ComponentPosition::Any`, bevy-explorer #1242); define the semantics of any new flag for that case.
- Scene emotes are `loop: false` in Unity (`AvatarShapeHandlerSystem.cs`) and Bevy (`EmoteCommand { r#loop: false }`); Godot masked emotes survive movement (`avatar_emote_controller.gd:process`).
- Headless Bevy (`NoRenderApp`) runs only `AvatarCorePlugin`, so no animation runs there.
- Unity legacy-animation emotes (`emoteReference.legacy`) bypass Mecanim, so local-dev GLB emotes behave differently from the controller path.
- Next free `PBAvatarShape` field number is 14: main ends at `show_only_wearables = 12`, `origin/experimental-bevy` and bevy's vendored copy add `repeated string force_render = 13`.

### Emote commands / masks

- Godot patches `avatar_emote_command.proto` at build time (`lib/build.rs:patched_avatar_emote_command_proto`) because pin `0ff6038` lacks `EmoteState`; a pin bump past that commit turns the patch into a no-op, keep the enum at file scope.
- Optional mask crosses the Godot op boundary as `-1` (`lib/src/avatars/emote_mask.rs`), because `#[op2]` params cannot be `Option`.

### UI

- SDK `UiLabelProps` and `UiTransformProps` are hand-written, so new `PBUiText` / `PBUiTransform` fields are not typed until declared there; `UiInputProps` / `UiDropdownProps` pick fields up through `Omit<PB...>`.
- Bevy registers `PbUiCanvas` from the bevy-only `ui_canvas.proto` (also bevy-only: `ui_scroll_result.proto`, id 1202 on `origin/experimental-bevy`); neither is on protocol main.
- Godot scene UI has no GDScript side; `godot/src/ui/` is the HUD.

### Pointer events / results

- Unity resolves presence defaults at read time (`InteractionInputUtils.cs` `HasX ? X : default`) and never writes them back into the PB; `max_player_distance` (field 6) is the deprecated alias of `max_distance` (protocol #470).
- Bevy stamps results with `MonotonicTimestamp<PbPointerEventsResult>`; Godot batches `scene.pointer_events_result` and flushes once per tick in `ComputeCrdtState`.

### GLTF / Animator

- Bevy registers `PbGltfNode` from the bevy-only `gltf_node.proto`; Unity and Godot only have `gltf_node_modifiers`.
- Unity has two animation players (`AnimationPlayerSystem.cs`, `LegacyAnimationPlayerSystem.cs`); animation defaults follow ADR-215.

### Audio / video

- `audio_analysis.proto` is protocol-only: implemented in Unity (`AudioAnalysisSystem.cs`) and Godot (`audio_analysis.rs`), absent from bevy's vendored tree.
- Bevy registers `PbAudioSource` in `crates/av/src/audio_source.rs`, not in `crates/av/src/lib.rs` with the other two.

### Restricted actions / kernel APIs

- Hop counts differ (Unity 4 layers, Bevy 4 places + `RpcCall` variant, Godot 5 hops) and none is generated from `kernel/apis/*.proto`; Bevy and Godot vendor those protos without compiling them. SDK-side generation (`make compile_apis`) is unmapped end to end, so say so in the matrix.

### Result / grow-only components

- Four lists must agree: SDK `GROWN_ONLY_COMPONENTS` (8), Godot `GROW_ONLY_SET_COMPONENTS` (6), Unity `AppendMessage` writers, Bevy `CrdtType::GO_ANY` writes. Pre-existing drift (`ExplorerUiEventsResult`, `ExplorerItemPurchaseResult` missing in Godot) is reported as P1 in review even when unrelated to the feature.
- Bevy's `add_crdt_go_component` helper exists but nothing calls it; the live grow-only path is `update_crdt(..., CrdtType::GO_ANY, ...)`.

### Comms

- `rfc4/comms.proto` carries a header that requires updating RFC-4 (ADR-104) in the same change; see `.claude/skills/protocol-feature/references/repos/adr.md`. No engine recipe exists for comms in v1.

## How to use

1. Fetch, then confirm the symbol on the fetched branch before you cite it, because working trees are stale or on feature branches:

   ```bash
   git -C <repo> fetch origin
   git -C <repo> grep -n '<symbol>' origin/<branch> -- <path>
   git -C <repo> ls-tree --name-only origin/<branch> <dir>/
   git -C <repo> show origin/<branch>:<path> | sed -n '<start>,<end>p'
   ```

   `<branch>` is `dev` for unity-explorer and `main` for the other three.

2. Cite `path:function` or `path:symbol` in the tech matrix and the proposal. Line numbers rot: `velocity_cancels` moved from ~623 to ~625 between the exploration map and this file. When a line number is the only handle, write `~N`.

3. A row with no path for an engine means the hook is unknown, so that engine's verdict is `uncertain`, never `feasible` or `already-supported`. Name the file or scene that would resolve it and, for Godot, the `need tech test` issue.

4. A path in this table is not support. Run `bash .claude/skills/protocol-feature/scripts/engine-support.sh <PbName> [--field <snake>]` (L0 schema status and the L1 consumer grep per engine, generated directories excluded), or by hand `git -C <repo> grep -n '<PbName>' origin/<branch> -- <dir>` and check the registration hits listed in `.claude/skills/protocol-feature/references/process.md`; zero consumers with the schema present is `SCHEMA-ONLY`.

5. State which protocol branch the engine receives the change from (bevy vendored tree tracks `origin/experimental-bevy`; godot pin commit `0ff6038` lags main; unity tracks `@next`; SDK pins an exact version). Per-engine pin and registration recipes live in `.claude/skills/protocol-feature/references/repos/{sdk,unity,bevy,godot}.md`; do not duplicate them here.

## Last verified

2026-10-10 against js-sdk-toolchain `origin/main` 60e3717f, unity-explorer `origin/dev` 41a9e92e9f, bevy-explorer `origin/main` ad569947, godot-explorer `origin/main` cada2d93da, protocol `feat/protocol-feature-skills` d7ddc10 (same as `origin/main`).
