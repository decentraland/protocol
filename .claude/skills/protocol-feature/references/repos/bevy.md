# bevy-explorer

How a protocol change lands in decentraland/bevy-explorer (Rust, Bevy 0.16; one engine shipped as a web client, a native client and a headless scene server): where the vendored protos live, how a component or field reaches the ECS, how a restricted action is wired, the avatar animation path, the gates, the manual checks and the PR style.

## Contents

- [Clone, branch and agent docs](#clone-branch-and-agent-docs)
- [Where the protocol lives](#where-the-protocol-lives)
- [Codegen: build.rs and prost](#codegen-buildrs-and-prost)
- [Ids and the DclProtoComponent impl](#ids-and-the-dclprotocomponent-impl)
- [Scene-written components: registration](#scene-written-components-registration)
- [Engine-written components](#engine-written-components)
- [Adding a field to an existing component](#adding-a-field-to-an-existing-component)
- [Restricted actions and scene RPCs](#restricted-actions-and-scene-rpcs)
- [Avatar animation path (AvatarShape work)](#avatar-animation-path-avatarshape-work)
- [Gates and CI](#gates-and-ci)
- [Manual verification](#manual-verification)
- [PR conventions](#pr-conventions)
- [Last verified](#last-verified)

## Clone, branch and agent docs

- The local clone lags GitHub (local `main` at b4b018cb, origin/main at ad569947), so run `git fetch origin` and read with `git show origin/main:<path>` / `git grep <pat> origin/main -- crates` before quoting anything; the working tree may be on a feature branch. Default branch `main`; workspace `members = ["crates/*", "local-harness/presence/harness-util"]`.
- Root `CLAUDE.md` is an eight-line directory map (added by #1446); `react-web/AGENTS.md` covers the React HUD only; `docs/` has three headless-server design notes. Nothing documents the protocol workflow, so this file is the process. No PR template: `.github/` holds `dependabot.yml` and workflows only.

## Where the protocol lives

Protos are copied by hand into `crates/dcl_component/src/proto/`; there is no submodule, npm pin or build-time fetch. `crates/dcl_component/src/readme..md` (two dots, sic) says verbatim:

```
.proto files are copied from https://github.com/decentraland/protocol/tree/main/proto
TODO: make this automatic with a build step
```

The readme is aspirational: the tree is a hand-maintained union, not a snapshot of any one branch. Diff of `crates/dcl_component/src/proto/decentraland/sdk/components/` (bevy origin/main ad569947) against protocol origin/main d7ddc10 and origin/experimental-bevy 329ba0e, per area:

| Area | Result |
|---|---|
| Most components (animator, audio_event, audio_source, avatar_attach, avatar_emote_command, avatar_locomotion_settings, billboard, camera_mode, gltf_container, gltf_node_modifiers, input_modifier, main_camera, nft_shape, particle_system, physics_*, player_identity_data, pointer_events_result, pointer_lock, raycast_result, skybox_time, trigger_area*, tween*, ui_background, ui_*_result, video_event, virtual_camera, visibility_component, most common/*) | byte-identical to both branches |
| ui_input, mesh_collider, mesh_renderer, material, ui_transform, raycast, primary_pointer_info, avatar_equipped_data, explorer_ui_events_result, gltf_container_loading_state, common/explorer_ui, common/input_action, ui_scroll_result, gltf_node_state | identical to experimental-bevy (bar comment/import-order drift), differ from main |
| avatar_shape | experimental-bevy content (`repeated string force_render = 13;`, so the next free tag is 14) minus a comment; main stops at `show_only_wearables = 12` |
| avatar_base | identical to main; experimental-bevy adds `optional bool talking = 6` (protocol #493) that bevy has not copied |
| engine_info, ui_text, camera_mode_area, avatar_modifier_area | ahead of both branches: `double total_runtime_f64 = 5` (open protocol PR #476); `outline_width = 7` / `outline_color = 8` (protocol-squad) plus `font_src = 9`; `cinematic_settings = 3` + `CinematicSettings`; protocol-squad `movement_settings = 4` and experimental-bevy `use_collider_range = 5` |
| audio_stream, video_player, ui_canvas_information | behind both main and experimental-bevy (spatial 4-6, spatial 7-9, `screen_inset_area = 5` missing) |
| asset_load, text_shape, ui_dropdown, pointer_events, realm_info, light_source, texture_camera, global_light | comment, BOM or whitespace drift only; diff the file before copying over it |
| bevy-only vs main: avatar_movement, avatar_movement_info, camera_layer(s), global_light, gltf_node(_state), texture_camera, ui_canvas, ui_scroll_result | all exist on experimental-bevy and match it bar comment/CRLF drift |
| main-only, never copied: audio_analysis, avatar_nametag, explorer_item_purchase_result, touch_screen_controls, ui_input_binding | absent from bevy (no `SceneComponentId`, no build.rs stem) |

Rules that follow from this:

- Copy only the touched `.proto` file(s) in the feature PR, never resync the tree, because a blind sync would drop bevy-only fields and files that the engine compiles against.
- Say in the PR which protocol branch or PR the file came from ("Vendored proto updated to match", "protocol #487, SDK on `experimental-bevy`"), because the tree records no provenance.
- Pick field numbers against main, experimental-bevy, protocol-squad, open protocol PRs and this tree, because bevy already carries numbers that main skips (ui_text 7-8, avatar_shape 13, engine_info 5).
- The SDK channel bevy's bridge scene tracks is `@dcl/sdk@experimental-bevy` (`react-web/bridge-scene/package.json`, `upgrade-sdk` script).
- `decentraland/kernel/apis/*.proto` are vendored but never compiled (see Restricted actions).

## Codegen: build.rs and prost

`crates/dcl_component/build.rs:gen_sdk_components` runs prost-build 0.11.8 (`prost = "0.11.8"`, `prost-build = "0.11.8"` in `Cargo.toml`) over a hard-coded stem list:

```rust
let components = [
    "asset_load",
    ...
    "avatar_shape",
    ...
    "explorer_ui_events_result",
];
// each stem -> src/proto/decentraland/sdk/components/{component}.proto
config.compile_protos(&sources, &["src/proto/"])?;
```

- A new component file must be appended to `components`; a new field on an existing component needs no build.rs change.
- Only the listed sources get `cargo:rerun-if-changed`, so editing an imported-but-unlisted file (for example `common/*.proto`) may not rebuild; run `cargo clean -p dcl_component` when generated code looks stale.
- `.decentraland.sdk.components` types get `#[derive(serde::Serialize, serde::Deserialize)]` with `#[serde(rename_all = "camelCase")]`, so console and inspector JSON uses camelCase keys (`expressionTriggerId`).
- The build also emits a FileDescriptorSet, `component_schemas.json` (inspector schemas) and `pulse_quant.rs`.
- Generated types are included by `crates/dcl_component/src/proto_components.rs` (`include!(concat!(env!("OUT_DIR"), "/decentraland.sdk.components.rs"))`) under `dcl_component::proto_components::sdk::components::Pb<Name>` (prost renames `PBAvatarShape` to `PbAvatarShape`).
- protoc must be >= 3.15: `.github/workflows/ci.yml` notes that Ubuntu's apt protoc 3.12 rejects proto3 `optional` and uses arduino/setup-protoc instead; locally `brew install protobuf` (`readme.md` Prerequisites).

## Ids and the DclProtoComponent impl

The engine never reads `option (common.ecs_component_id)`. Ids are hand-written consts in `crates/dcl_component/src/lib.rs:SceneComponentId`:

```rust
pub const AVATAR_SHAPE: SceneComponentId = SceneComponentId(1080);
pub const TEXT_SHAPE: SceneComponentId = SceneComponentId(1030);
pub const EXPLORER_UI_EVENTS_RESULT: SceneComponentId = SceneComponentId(1220);
```

Off-main ids the file already claims: 1200-1203, 1206-1208, 1500, 1501, 1503. Every compiled component also needs one line in `crates/dcl_component/src/proto_components.rs`:

```rust
impl DclProtoComponent for sdk::components::PbAvatarShape {}
```

That impl is what gives the type `FromDclReader`; #658 had to add it for `PbAvatarLocomotionSettings`.

## Scene-written components: registration

`crates/scene_runner/src/update_world/mod.rs:AddCrdtInterfaceExt` has the two registration calls:

```rust
fn add_crdt_lww_component<D: FromDclReader + Debug + prost::Message + Default + Serialize + DeserializeOwned,
                          C: Component + TryFrom<D>>(&mut self, id: SceneComponentId, position: ComponentPosition)
    where <C as TryFrom<D>>::Error: Display;
fn add_crdt_go_component<D: ..., C: Component<Mutability = Mutable> + DerefMut<Target = VecDeque<D>> + Default>(
    &mut self, id: SceneComponentId, position: ComponentPosition);
```

`ComponentPosition` is `RootOnly | EntityOnly | Any` (`crates/dcl_component/src/crdt_type.rs`, with `CrdtType::LWW_ROOT/LWW_ENT/LWW_ANY/GO_ENT/GO_ANY`). The lww call registers the CRDT interface, the `ComponentNameRegistry` entry the inspector uses (name = type name minus `Pb`, via `derive_component_name`), the `process_crdt_lww_updates::<D, C>` system that inserts `C` through `TryFrom<D>`, and a tracker; it asserts `"duplicate registration for {id:?}"`. Canonical small example, `crates/scene_runner/src/update_world/text_shape.rs:TextShapePlugin`:

```rust
app.add_crdt_lww_component::<PbTextShape, TextShape>(
    SceneComponentId::TEXT_SHAPE,
    ComponentPosition::EntityOnly,
);

#[derive(Component, Clone, PartialEq)]
pub struct TextShape(pub PbTextShape);

impl From<PbTextShape> for TextShape {
    fn from(value: PbTextShape) -> Self { Self(value) }
}
```

Forgetting the registration compiles and silently ignores scene data: #658 ("register AvatarLocomotionSettings as CRDT component") fixed exactly that, with the struct, `From` impl and consumer system already in place. New-component checklist (#1235 precedent): proto file, build.rs stem, `SceneComponentId` const, `impl DclProtoComponent`, wrapper component + `From<Pb>`, registration in a plugin; render-only plugins are added inside `if !headless` in `update_world/mod.rs:SceneOutputPlugin`.

## Engine-written components

Results the engine writes back to scenes do not go through `add_crdt_*`. Write with `crates/scene_runner/src/renderer_context.rs:RendererSceneContext::update_crdt` (or `update_crdt_if_different`):

```rust
pub fn update_crdt(&mut self, component_id: SceneComponentId, crdt_type: CrdtType, id: SceneEntityId, data: &impl ToDclWriter)
```

(player-scoped data uses `crates/comms/src/global_crdt.rs:GlobalCrdtState::update_crdt`), and name the component for the inspector in `crates/scene_inspector/src/manual_registry.rs:register_engine_components`:

```rust
reg!(
    PbRaycastResult,
    SceneComponentId::RAYCAST_RESULT,
    CrdtType::LWW_ENT,
    ro
);
```

`ro` registers inspect only; `rw` also registers write/default closures. Grow-only sets that scenes append to use `add_crdt_go_component` instead.

## Adding a field to an existing component

- Copy the one proto file; no build.rs or id change. Precedents: #962 (`avatar_locomotion_settings.proto` + `crates/user_input/src/avatar_movement.rs`, 2 files), #1158 (`pointer_events.proto` + `crates/scene_runner/src/update_scene/pointer_results.rs`), #1263 (`font_src` on four protos + `fonts.rs`, `text_shape.rs`, `scene_ui/ui_{text,input,dropdown}.rs`).
- Every exhaustive prost struct literal then fails with E0063 (missing field). Known spots: `crates/avatar/src/lib.rs:From<&UserProfile> for AvatarShape` (lists every `PbAvatarShape` field; the second literal in `select_avatar` uses `..scene_avatar_shape.0.clone()` and is safe) and `crates/user_input/src/avatar_movement.rs:FromConfig for AvatarLocomotionSettings`. Find them with:

```bash
git grep -n 'PbAvatarShape {' origin/main -- crates | grep -v dcl_component/src/proto
```

- prost ignores unknown fields, so an engine without the new field keeps parsing and nothing warns that support is missing; the reading system is the only evidence of support.

## Restricted actions and scene RPCs

RPC behaviour is hand-written, not generated: the vendored `crates/dcl_component/src/proto/decentraland/kernel/apis/restricted_actions.proto` is not in build.rs and does not even list `StopEmote`. A new op touches four places plus an `RpcCall` variant and a consumer (#1227 `stopEmote`, #1235 `openExplorerUi`):

1. `crates/dcl/src/js/modules/RestrictedActions.js` (the `~system/RestrictedActions` module, `include_str!`'d by `crates/dcl_deno/src/js/mod.rs` and `crates/dcl_wasm/src/inner/mod.rs:builtin_module`):

```js
module.exports.stopEmote = async function (body) {
    Deno.core.ops.op_stop_emote()
    return { success: true }
}
```

2. `crates/dcl/src/js/restricted_actions.rs`, runtime-agnostic body pushing onto `RpcCalls`:

```rust
pub fn op_stop_emote(op_state: &mut impl State) -> Result<(), anyhow::Error> {
    debug!("op_stop_emote");
    op_state.borrow_mut::<RpcCalls>().push(RpcCall::StopEmote)
}
```

3. `crates/dcl_deno/src/js/op_wrappers/restricted_actions.rs`: `#[op2(fast)] fn op_stop_emote(op_state: &mut OpState) -> Result<(), anyhow::Error> { dcl::js::restricted_actions::op_stop_emote(op_state) }` plus `op_stop_emote(),` in that file's `ops()` vec, because a missing entry breaks native only.
4. `crates/dcl_wasm/src/inner/op_wrappers/restricted_actions.rs`: `#[wasm_bindgen] pub fn op_stop_emote(op_state: &WorkerContext) -> Result<(), WasmError>` calling the same shared fn; `deploy/web/engine/sandbox_worker.js` exposes every wasm export whose name starts with `op_` automatically.
5. `crates/common/src/rpc/mod.rs:RpcCall`: add the variant (`StopEmote` is a unit variant; the scene comes from the event's `RpcOrigin::Scene { entity: scene, .. }`).
6. Consumer system: `crates/restricted_actions/src/{lib,teleport,explorer_ui,agent_commands}.rs` for movement/UI, or the owning crate (`crates/avatar/src/animate.rs:handle_trigger_emotes` for emotes, gated by `perms.check(PermissionType::PlayEmote, ...)` + `drain_success`).

## Avatar animation path (AvatarShape work)

- `AvatarShape` (1080) is registered in `crates/avatar/src/lib.rs:AvatarPlugin` with `ComponentPosition::Any`, so scenes may also put it on the PLAYER entity to override the player's look (issue #1242); define a new field's semantics for that case too.
- NPC velocity: `crates/avatar/src/npc_dynamics.rs:update_npc_velocity` (filter `With<AvatarShape>, Without<ForeignPlayer>, Without<PrimaryUser>`) inserts `AvatarDynamicState { velocity: (current_translation - prev_translation) / scene.last_update_dt, ground_height: 0.0, .. }`, so NPCs never jump or fall.
- Locomotion and emote cancel: `crates/avatar/src/animate.rs:animate` damps that velocity, then clears a playing emote when `velocity_cancels && damped_velocity_len * 0.9 > playing_min_vel`, with

```rust
let velocity_cancels = maybe_foreign.is_none()
    && scene_anim.is_none()
    && active_emote.source != ActiveEmoteSource::SceneMovementAnim;
```

so the local player and every scene NPC cancel on motion while foreign players keep emoting (Unity parity, per the comment above it). Locomotion pick: `|v| > 0.1` moving; `<= 2.6` m/s `URN_WALK` (speed `/ 1.5`), else `URN_RUN` (speed `/ 4.5`); otherwise `URN_IDLE`; jump/fall only when `ground_height > 0.2`.
- Scene emote: `PbAvatarShape.expression_trigger_id` resolves in `crates/avatar/src/lib.rs` (scene content map gives `urn:decentraland:off-chain:scene-emote:{scene_hash}-{emote_hash}-false`) to `EmoteCommand { urn, r#loop: false, timestamp: expression_trigger_timestamp, mask: EmoteMask::FullBody }` (`crates/common/src/structs.rs:EmoteCommand`); looping only comes from the collectible's `default_repeat`. `AvatarEmoteCommand` is written by `crates/avatar/src/emote_report.rs` and never read as a command.
- A "keep emote while moving" flag therefore gates either `update_npc_velocity` (report zero) or the `velocity_cancels` and walk/run branches in `animate`; the next free `PBAvatarShape` tag is 14.
- Headless: `src/headless/app.rs` inserts `NoRenderApp` (`crates/common/src/structs.rs`) and adds only `AvatarCorePlugin` (`PlayerMovementPlugin`, `EmoteReportPlugin`, `update_avatar_info`). `AvatarShape` registration, `NpcMovementPlugin` and `AvatarAnimationPlugin` live in the client-only `AvatarPlugin`, and `SceneOutputPlugin` skips `SceneUiPlugin`, `TextShapePlugin`, `PointerEventsPlugin` and friends under `NoRenderApp`. Headless breakage compiles clean and panics at runtime, which is why CI runs a smoke job.

## Gates and CI

Local, matching `.github/workflows/ci.yml` and `readme.md` Testing:

```bash
cargo fmt --all -- --check
cargo clippy --locked -- -D warnings
cargo test --all
taplo fmt --check --diff
```

CI Test Suite: `cargo build --package dcl_deno_ipc --release --locked` then `cargo test --all --release --locked -- --test-threads=1`. Headless Smoke:

```bash
cargo build --release --locked -p dcl_deno_ipc
cargo build --release --locked --bin headless --no-default-features --features headless,livekit
./target/release/headless --realm https://decentraland.github.io/scene-explorer-tests/scene-explorer-tests --location 52,-52 --server-mode --preview --timeout 90
```

Test Scenes job (only when `Cargo.lock`, `Cargo.toml`, `**/Cargo.toml` or `.cargo/config.toml` change, and `continue-on-error: true`, so feature PRs get no automated scene coverage):

```bash
xvfb-run -s "-screen 0 320x240x24" cargo run --release --locked -- --realm https://decentraland.github.io/scene-explorer-tests/scene-explorer-tests --test_scenes "52,-52;52,-54;52,-56;52,-58;52,-60;52,-62;52,-64;52,-66;52,-68;54,-52;54,-54;54,-56;54,-58;54,-60" --no_fog --distance 1 --scene_log_to_console
```

Scene-runner tests compare `.dot` graphs in `crates/scene_runner/src/test/expected/` through `check_or_write!`; `cargo test -p scene_runner --features gen-tests` overwrites them (feature `gen-tests = []` in `crates/scene_runner/Cargo.toml`), so commit regenerated snapshots deliberately.

## Manual verification

Run a local SDK7 scene against the native client (flags from `crates/system_api_types/src/launch_options.rs`; `just native-debug` builds `dcl_deno_ipc` and `decentra-bevy-cef` first):

```bash
just native-debug --realm http://127.0.0.1:8000 --preview --position 4,25
```

Web: `just wasm` builds the engine wasm and serves `react-web`. In the in-game console (`crates/scene_inspector/src/{write,read}_commands.rs`, PascalCase names from `/component_names`, camelCase JSON keys):

```
/set_component <entity|root|player|camera> AvatarShape {"expressionTriggerId":"wave"}
/inspect_component <entity> AvatarShape
/entity_components <entity>
/component_schema [AvatarShape]
/debug_dump_avatar          # preview mode only (add_preview_console_command)
```

These exercise a vendored field before any SDK release. `/emote <urn|slot> [--loop] [--upper_body]` (`crates/avatar/src/animate.rs`) plays an emote on the local player.

## PR conventions

- Branches `feat/<slug>` or `fix/<slug>` (`feat/web-fonts`, `feat/max-camera-distance`, `fix/avatar-locomotion-settings-registration`; bare slugs also occur).
- Squash-merged with the title `<Imperative sentence> (#N)`, e.g. `Add font_src to TextShape, UiText, UiInput and UiDropdown (#1263)`, occasionally prefixed `feat: ...` (#1227) or `fix(pointer): ...` (#1158).
- Body: a lead paragraph that states what and why and cites the protocol side, then `## Problem` / `## Fix` (#1158) or feature sections plus `## Deliberately not done` (#1227), a `Test scene: <repo url>` line, `Closes #N`, and the trailer `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Verbatim phrasings to reuse: "Follow decentraland/protocol#470 ... Vendored proto updated to match." and "(protocol #487, SDK on `experimental-bevy`)".
- The protocol PR lands first or in parallel; the bevy PR copies the proto and references it. robtfm authors most engine work (128 of the last 200 commits).

## Last verified

2026-10-10 against bevy-explorer origin/main ad569947f1062ab119fc04b9531f1bc1b86379fa (#1469), protocol origin/main d7ddc10 and origin/experimental-bevy 329ba0e. Sibling files: `.claude/skills/protocol-feature/references/repos/unity.md`, `.claude/skills/protocol-feature/references/repos/godot.md`, `.claude/skills/protocol-feature/references/repos/protocol.md`.
