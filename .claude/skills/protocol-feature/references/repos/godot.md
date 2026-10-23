# godot-explorer
How the mobile explorer (`decentraland/godot-explorer`: Rust GDExtension in `lib/`, GDScript in `godot/`) consumes `@dcl/protocol`, where a protocol feature has to be wired, and how to test and ship it in that repo's conventions.

## Contents
1. Where the protocol comes from (pin, install, wipe rule, URL shapes)
2. What `lib/build.rs` generates and what it does not
3. Grow-only components
4. Wiring a new SDK component (seven hand-written touches)
5. Adding a field to an existing component
6. Restricted actions and other RPCs (five hops)
7. Avatar animation and AvatarShape
8. Gates, tests and manual runs
9. PR, review, workflow and issue conventions
10. Last verified

Read the fetched branch, not the working tree: the local clone often sits on a feature branch, so use `git show origin/main:<path>` and `git grep <pattern> origin/main -- <dir>`.

## 1. Where the protocol comes from

godot-explorer has no npm dependency and no submodule for the protocol. The xtask `cargo run -- install` downloads one tarball whose URL is pinned in `src/install_dependency.rs`:

```rust
const PROTOCOL_FIXED_VERSION_URL: Option<&str> = Some(
    "https://registry.npmjs.org/@dcl/protocol/-/protocol-1.0.0-30827383791.commit-0ff6038.tgz",
);
const PROTOCOL_NPM_DIST_TAG: &str = "next";
```

- `get_protocol_url()` returns the pin; with `None` it fetches `https://registry.npmjs.org/@dcl/protocol/next` and takes `dist.tarball`. The pin exists because tracking `next` re-resolved on every CI run and an upstream publish (PBBillboard.target_entity) broke the billboard itest mid-RC, so bumps are deliberate (comment above the const).
- `install_dcl_protocol()` streams the tarball and copies only entries under `package/proto` into `lib/src/dcl/components/proto/` (gitignored via `lib/src/dcl/components/.gitignore`, so the vendored protos are never committed). It creates or overwrites files and deletes nothing, so moving to an older pin leaves newer `.proto` files behind that `build.rs` still compiles and registers locally while CI never sees them. Wipe before switching pins:

```bash
rm -rf lib/src/dcl/components/proto
cargo run -- install --no-templates   # protoc, Godot and the protos, no export templates (what .github/workflows/clippy.yml runs)
cargo run -- build
```

- Two URL shapes go in the pin. The per-PR CDN build that protocol's `.github/workflows/build-and-publish.yml` posts in the "# Test this pull request" comment (the double slash is real; precedent 9284c38d44):
  `https://sdk-team-cdn.decentraland.org/@dcl/protocol/branch//dcl-protocol-1.0.0-<RUN_ID>.commit-<SHA7>.tgz`
  and the published build once the protocol PR is on `main` -> `@next` (precedent 94d964d3fa):
  `https://registry.npmjs.org/@dcl/protocol/-/protocol-1.0.0-<RUN_ID>.commit-<SHA7>.tgz`
  Pin the CDN URL while the protocol PR is open and repin to the npm URL of the `next` build that contains the merge before the godot PR merges (`docs/PROTOCOL_DEV_WORKFLOW.md` Flow A step 6), because a CDN pin ties `main` to an unmerged branch.
- Pin commit 0ff6038 lags protocol `main` (d7ddc10): `avatar_nametag`, `explorer_item_purchase_result` and `explorer_ui_events_result` are absent and `text_shape` / `ui_text` / `ui_input` / `ui_dropdown` lack `font_src`. Any feature already on protocol `main` needs a pin bump in godot before it compiles, so the godot PR for a protocol feature carries the bump plus whatever struct-literal fixes it causes (section 5).
- `lib/build.rs` patches two protos at build time for fields the pin lacks: `patched_rfc4_comms_proto` (PlayerEmote `is_stopping = 4` .. `mask = 11`, Chat `forwarded_from = 3`) and `patched_avatar_emote_command_proto` (file-scope `enum EmoteState` plus `optional EmoteState state = 5`). Both are guarded by `source.contains(...)` checks and become no-ops once the pin ships the fields; protocol `main` already has them (PlayerEmote `reserved 5 to 10`, and nothing under `lib/src` reads those fields), so a bump past `main` compiles without touching the patches. Keep `EmoteState` at file scope, since prost maps it to `sdk::components::EmoteState` and import sites depend on that path.

## 2. What `lib/build.rs` generates and what it does not

- Component scan: `fs::read_dir(COMPONENT_BASE_DIR)` with `COMPONENT_BASE_DIR = "src/dcl/components/proto/decentraland/sdk/components/"`. Every `*.proto` directly in that directory is a component; `common/` is not scanned.
- `get_component_id` keeps the lines that contain both `ecs_component_id` and `option`. More than one such line (a comment counts) fails with "There are more than one match with `ecs_component_id` and `option`"; none fails with "`ecs_component_id` is missing". Write exactly one `option (common.ecs_component_id) = N;` line per file and keep the phrase out of comments.
- Names derive from the FILE name, not the message: `snake_name` = file stem, `pascal_name = snake_to_pascal(snake_name)`. `touch_screen_controls.proto` -> `SceneComponentId::TOUCH_SCREEN_CONTROLS`, `PbTouchScreenControls`, `SceneCrdtStateProtoComponents::get_touch_screen_controls` / `get_touch_screen_controls_mut`. A file stem that does not PascalCase into the message name (minus `PB`) fails the generated `impl DclProtoComponent for sdk::components::Pb{}`.
- Generated into `OUT_DIR` and `include!`d: `components_enum.gen.rs` (ids, included by `lib/src/dcl/components/mod.rs` next to the hand-written `TRANSFORM = 1` and `INTERNAL_PLAYER_DATA = 101`), `crdt_impl.gen.rs` (LWW/GOS registration), `dclcomponent.proto.impl.gen.rs`, `deserialize_component.gen.rs` (scene-inspector JSON decoder), plus prost's `decentraland.sdk.components.rs` under `pub mod sdk { pub mod components { ... } }` in `lib/src/dcl/components/proto_components.rs`. prost-build 0.11: proto3 `optional` -> `Option<T>`, enums are `i32`.
- Also compiled, by explicit push in `build.rs:main`: `kernel/comms/rfc5/ws_comms.proto`, the patched `kernel/comms/rfc4/comms.proto`, `kernel/comms/v3/archipelago.proto`, `common/options.proto`, `pulse/pulse_{shared,client,server}.proto`, `sdk/development/local_development.proto`, `social_service/errors.proto`, `social_service/v2/social_service_v2.proto`.
- Not compiled: `kernel/apis/*.proto` (restricted actions and the other scene APIs). RPC changes are hand-wired (section 6).
- `REVIEW.md` §5 "Proto regeneration" still speaks of bumping a `decentraland-protocol` submodule; the pin URL replaced it. Treat that paragraph as stale.

## 3. Grow-only components

`lib/build.rs`, current list on `origin/main`:

```rust
const GROW_ONLY_SET_COMPONENTS: [&str; 6] = [
    "PointerEventsResult",
    "VideoEvent",
    "AvatarEmoteCommand",
    "AudioEvent",
    "TriggerAreaResult",
    "AssetLoadLoadingState",
];
```

Everything else registers as `.insert_lww_component::<proto_components::sdk::components::Pb{}>(SceneComponentId({}))`; a listed name registers with `.insert_gos_component`. Add a renderer-appended result or event component here by PascalCase, otherwise it registers LWW and the scene never reads the appended values (the `AudioEvent` comment says exactly that). Pre-existing drift: the SDK's `GROWN_ONLY_COMPONENTS` carries `ExplorerUiEventsResult` and `ExplorerItemPurchaseResult`, this list has neither (the pin predates both). Report such drift as P1 in review even when unrelated to the feature, and compare the four lists (SDK, godot, unity `AsProtobufResult`, bevy `add_crdt_go_component`) whenever a grow-only component is involved.

## 4. Wiring a new SDK component (seven hand-written touches)

Ids, CRDT registration and accessors are generated; behaviour is not. Precedents: ParticleSystem 422f03ef14 (#2588, six files) and TouchScreenControls 652c690103 (#2330).

1. System: `lib/src/scene_runner/components/<name>.rs` with `pub fn update_<name>(scene: &mut Scene, crdt_state: &mut SceneCrdtState, current_parcel_scene_id: &SceneId)` (drop the third parameter when the system never asks whether the player stands in this parcel).
2. `pub mod <name>;` in `lib/src/scene_runner/components/mod.rs`.
3. `lib/src/scene_runner/scene.rs`: add a `SceneUpdateState::<Name>` variant and splice it into `next()`, which is the per-frame order, e.g. `Self::AudioSource => Self::ParticleSystem, Self::ParticleSystem => Self::AvatarAttach,`.
4. `lib/src/scene_runner/update_scene.rs`: `S::<Name> => "<Name>",` in `state_name`, the `use` import, and the arm
   ```rust
   SceneUpdateState::<Name> => {
       update_<name>(scene, crdt_state, current_parcel_scene_id);
       false
   }
   ```
5. Per-entity state: a `HashMap<SceneEntityId, _>` field on `Scene`, initialised in both constructors (`Scene::new` ~372 and `Scene::unsafe_default` ~459), drained in the scene drop path (`self.particle_systems.drain()` ~642) and removed in `lib/src/scene_runner/deleted_entities.rs:update_deleted_entities` (`scene.particle_systems.remove(deleted_entity);`), because the entity can die before the node does.
6. Optional presence hooks in `lib/src/scene_runner/scene_manager.rs` (3529 lines): `particle_system::reconcile_user_presence(scene, false|true)` on leave/enter, `scene_killed`, `on_avatar_shape_emote_finished`.
7. GDScript side: a script plus scene under `godot/src/decentraland_components/` (`<name>.gd`, `<name>.tscn`) driven through `node.call(...)` / `call_deferred(...)` with Dictionaries, or a `DclGlobal` field in `lib/src/godot_classes/dcl_global.rs` for ROOT-entity settings. Scene UI is Rust-only under `lib/src/scene_runner/components/ui/{scene_ui,ui_transform,ui_text,ui_input,ui_dropdown,ui_background,ui_scroll,ui_input_binding,style}.rs`; `godot/src/ui/` is the explorer HUD, not SDK UI.

Dirty-check idiom (`lib/src/scene_runner/components/avatar_shape.rs:update_avatar_shape`):

```rust
if let Some(dirty) = scene.current_dirty.lww_components.get(&SceneComponentId::AVATAR_SHAPE) {
    for entity in dirty {
        let value = SceneCrdtStateProtoComponents::get_avatar_shape(crdt_state).get(entity);
        // ...
    }
}
```

Grow-only components read `scene.current_dirty.gos_components` (`avatar_shape.rs:update_avatar_shape_emote_command`). ROOT-entity components read `component.get(&SceneEntityId::ROOT)` and gate `SceneType::Parcel` on `scene.scene_id == *current_parcel_scene_id` (`touch_screen_controls.rs:update_touch_screen_controls`) so a neighbouring parcel cannot drive global state.

Automated test per component: `#[godot::test::itest] fn test_x(scene_context: &TestContext)` inside a non-`cfg(test)` `mod test`, building state with `Scene::unsafe_default()` and `SceneCrdtStateProtoComponents::get_<name>_mut(&mut crdt_state).put(entity, Some(Pb<Name> { ..., ..Default::default() }))` (`lib/src/scene_runner/components/billboard.rs`). Scene tests only cover the fixed coordinate list in `src/main.rs:coverage_with_itest`, so an itest is the realistic automated check for a new component.

## 5. Adding a field to an existing component

Precedent 9284c38d44 (#2079, `AMT_HIDE_NAMETAGS`, four files): bump `PROTOCOL_FIXED_VERSION_URL`; read the new value in the Rust system or godot_class (`lib/src/godot_classes/dcl_avatar_modifier_area_3d.rs` enum `HideNameTags = 2`); act on it in GDScript (`avatar.gd`); fix every exhaustive struct literal of the changed message (`screen_inset_area: None` on `PbUiCanvasInformation` in `scene_manager.rs:create_ui_canvas_information`).

A new field breaks every `Pb<Name> { ... }` literal with E0063. Use the fix from 39a8d2b458 so the next bump is free:

```rust
#[allow(clippy::needless_update)]
PbBillboard {
    billboard_mode: Some(3),
    ..Default::default()
}
```

After each bump run `git grep -n "Pb<Name> {" lib/src`. prost ignores unknown wire fields and decodes an absent `optional` as `None`, so resolve the default at read time and keep it equal to today's behaviour; deployed scenes are immutable and a changed default is a Tier-1 contract break (section 9).

## 6. Restricted actions and other RPCs (five hops)

`kernel/apis` protos are not compiled, so every RPC is hand-wired. Precedents: stopEmote 119eb4e3ba (#2931), triggerEmote mask 14733a9d08 (#2690), teleportTo realm (protocol#477, comment in `restricted_actions.rs:op_teleport_to`).

1. JS shim `lib/src/dcl/js/js_modules/RestrictedActions.js`, served for `~system/RestrictedActions` by the module resolver in `lib/src/dcl/js/mod.rs`:
   `module.exports.stopEmote = async function () { return await Deno.core.ops.op_stop_emote(); };`
2. Deno op in `lib/src/dcl/js/restricted_actions.rs`, added to `pub fn ops() -> Vec<OpDecl>`:
   ```rust
   #[op2(fast)]
   fn op_stop_emote(op_state: Rc<RefCell<OpState>>) {
       op_state.borrow_mut().borrow_mut::<Vec<RpcCall>>().push(RpcCall::StopEmote);
   }
   ```
   Ops that answer the scene use `#[op2(async)]` with `tokio::sync::oneshot::channel::<Result<(), String>>()` and a `response: sx.into()` field (`op_teleport_to`, `op_open_external_url`).
3. Variant in `lib/src/dcl/scene_apis.rs:RpcCall` (`StopEmote`, `TriggerEmote { emote_id, mask: i64 }`, `TeleportTo { world_coordinates: Option<[i32; 2]>, realm: Option<String>, response }`).
4. Dispatch arm in `lib/src/scene_runner/rpc_calls/mod.rs:process_rpcs`: `RpcCall::StopEmote => stop_emote(scene, current_parcel_scene_id),`.
5. Handler in `lib/src/scene_runner/rpc_calls/handle_restricted_actions.rs`, which calls GDScript (`get_avatar_node(scene).call("stop_emote_from_scene", ...)`, `modal_manager.call("async_show_external_link_modal", ...)`).

Optional params cross the op boundary as sentinels because `#[op2]` params cannot be `Option`: `body.mask ?? -1` with `#[smi] mask: i32` (-1 = full body), `?? NaN` for the movePlayerTo vectors, `coords != null` plus `body.realm ?? ''` for teleportTo. Handlers gate on `_player_is_inside_scene(scene, current_parcel_scene_id)` (Parcel scenes: `scene.scene_id == current_parcel_scene_id`; Global scenes pass unconditionally, which is why masked-emote stops need an owner check in GDScript) and log refusals as `tracing::warn!("stopEmote failed: Primary Player is outside the scene")`.

## 7. Avatar animation and AvatarShape

- `godot/src/decentraland_components/avatar/avatar.gd:_process` (~1433) computes `self_idle = is_grounded && !jog && !walk && !run && !rise && !fall`, calls `emote_controller.process(self_idle)`, then writes `parameters/Locomotion/conditions/{idle,emote,nemote,emix,nemix,run,jog,walk,rise,fall,land,nfall}` on the AnimationTree; walk/jog/run come from `AvatarAnimHelpers.locomotion_conditions(walk, jog, run, is_grounded)`.
- `avatar_emote_controller.gd:process(idle)` cancels single and mixed emotes when `not idle and not in_grace_period` (`_emit_emote_finished(true)`); masked (upper-body) emotes are tracked only to their natural end and survive movement.
- The flags live on the Rust base class `lib/src/godot_classes/dcl_avatar.rs`: `init` defaults `movement_type: AvatarMovementType::ExternalController`, `walk/jog/run: false`, `is_grounded: true` (~244-258); `classify_locomotion` (walk `< 4.0` m/s above an idle floor of `0.5`, run `>= 6.5`) only runs for `LerpTwoPoints` avatars fed by `set_target_position` or the comms wire.
- AvatarShape NPCs: `lib/src/scene_runner/components/avatar_shape.rs:update_avatar_shape` instantiates `res://src/decentraland_components/avatar/avatar.tscn`, sets `skip_process = true` and `is_avatar_shape = true`, names the node `AvatarShape` and defers `async_update_avatar(wire, name, avatar_shape_config)`. Nothing sets walk/jog/run for it, so an AvatarShape moved by Transform or Tween keeps `ExternalController`, stays idle, plays no locomotion and keeps its emote. That is a code-level (L1) baseline only; nobody has observed it at runtime, so report `uncertain, likely current behaviour, runtime pending` and file a `need tech test` issue rather than `already-supported`. `update_avatar_shape_emote_command` reads `AvatarEmoteCommand` as a play command, which Unity and Bevy treat as write-only; see `.claude/skills/protocol-feature/references/subsystems.md` for the cross-engine list.
- `avatar.gd` is 1885 lines against the root `.gdlintrc` caps (`max-file-lines: 1900`, `max-public-methods: 45`; `global.gd`, `explorer.gd` and `modal_manager.gd` sit at the cap too; a second `godot/gdlintrc` carries an older 1500, CI runs `gdlint godot/` from the root). Raising a cap inside a feature PR is a hold (`REVIEW.md` Tier 3 #20), so put new animation logic in `avatar_anim_helpers.gd` (`class_name AvatarAnimHelpers`, static helpers) or a new helper file. `avatar_emote_controller.gd` (1307 lines) and `scene_manager.rs` (3529) are large as well.

## 8. Gates, tests and manual runs

Run from the repo root unless noted:

```bash
cargo run -- install --no-templates     # protoc, Godot and the pinned protos
cargo run -- build                      # host build of the GDExtension
cargo run -- run --itest                # Rust integration tests, headless --test-runner; passes on "test-exiting with code 0"
cargo run -- run --stest                # scene tests on the pinned scene-explorer-tests realm; passes on "All test of all scene passed"
cargo run -- test-gdscript              # headless GDScript tests under godot/src/test/
cargo run -- check-gdscript             # every .gd parses
cargo run -- full-tests [--skip-visual] [--update-snapshots] [--report] [--continue-on-failure]
cd lib && cargo fmt --all && cargo clippy -- -D warnings
gdformat godot/ && gdlint godot/        # dcl-regenesislabs fork: pip3 install git+https://github.com/dcl-regenesislabs/godot-gdscript-toolkit.git
node --test lib/src/dcl/js/js_modules/ws.test.cjs
```

CI mirrors these in `.github/workflows/static_checks.yml` (`gdformat -d godot/`, `gdlint godot/`, rustfmt, the ws test) and `clippy.yml` (`cargo run -- install --no-templates`, `cargo clippy -- -D warnings`). `--stest` serves `@dcl/scene-explorer-tests@1.0.0-20240430222335.commit-2b82e41` at `http://localhost:7666/scene-explorer-tests` (`.github/workflows/coverage.yml`); that package is frozen in 2024, so a new component gets coverage only through an itest or a phone run.

Manual run against a local SDK preview (flags parsed in `lib/src/godot_classes/dcl_cli.rs`; `--dcl-help` lists them; `cargo run -- run` uses the iOS phone layout and `-- --emulate-android` switches it):

```bash
cargo run -- run -- --preview --realm http://localhost:8000 --location 4,25 --skip-lobby
```

Other flags: `--guest-profile`, `--scene-test`, `--scene-inspector`, `--fake-deeplink`. On phones use a deeplink: `lib/src/deep_link.rs` accepts `https://mobile.dclexplorer.com/open?realm=...&position=X,Y` (also `location=`, `dclenv=`) and the native `decentraland://` scheme; test plans use the https form so QA taps one link.

Mobile QA: every PR uploads a signed Android APK to `https://mobile-artifacts.dclregenesislabs.xyz/android/<branch>/<sha>/decentraland.godot.client.apk` (`.github/workflows/android_builds.yml`); iOS TestFlight is opt-in through `gh pr edit <N> -R decentraland/godot-explorer --add-label build` (alias `build-ios`) and reported in the sticky "📱 Mobile build pipeline" comment. QA runs the Test plan by hand on real phones, so device setup never appears in the steps.

## 9. PR, review, workflow and issue conventions

PR (`godot-explorer/.claude/skills/pr-description/SKILL.md`, enforced by `REVIEW.md` §4): branch off `main`, conventional-commit title, print the body before creating:

```bash
gh pr create -R decentraland/godot-explorer --base main \
  --title "<feat|fix|chore|refactor>: <summary>" --body-file <scratchpad>/pr-body.md
```

```markdown
## What
<1-3 sentences, plain language; what is different after this merges>

## Why
<1-3 sentences, including what the change deliberately does NOT do>
Heads-up posted in #ext-foundation — <what shared surface it touches>   (only when another team or the SDK is affected)

Closes #<issue>

## Details
<details><summary>Expand</summary>
<root cause, approach, trade-offs; omit the section when What/Why say it all>
</details>

## Test plan
### Case 1 — <name>
**Setup:** <only when the required state is non-obvious>
**Steps:**
1. Open the link above   (https://mobile.dclexplorer.com/open?realm=...&position=...)
2. <one user action per line, concrete on-screen names>
- [ ] **Expected:** <observable without reading code>
- [ ] **Regression — <shared surface>:** <still works>
```

The Expected and Regression lines are the checkboxes (no bare `- [ ]`, no tables); a PR with no behaviour change writes `No QA needed — no behavior change`; the author owns the text at AG-3 to AG-5 (rewritten and explainable). A protocol-feature PR carries the pin bump and its literal fixes, and repins from the CDN tarball to the `@next` build before merge.

Review (`REVIEW.md`): pre-flight = branch up to date with `main`, What/Why present, iOS build for platform-sensitive diffs (`plugins/dcl-godot-ios/**`, `lib/src/comms/`, `lib/src/av/`, deeplinks). Tier 1 #2 "Decentraland SDK contract breaks ... component IDs, protocol field numbers ... existing scenes in production must keep working" blocks; §1 makes the Unity Foundation Client the parity ground truth. Tier 2 #14 log levels: `tracing::error!` / `push_error` / `printerr` open Sentry issues, `tracing::warn!` ships at lower severity, `info!` / `debug!` / `trace!` and `print` do not, so per-entity or per-frame code in component systems logs with `debug!`. Findings use `🔴` blocker / `🟡` suggestion / `nit` and end with `Approving` / `Requesting changes` / `Commenting`. `CODEOWNERS` is `* @decentraland/rgl-mobile-team`, so a human mobile-team review is required on every PR.

Cross-repo flow: `docs/PROTOCOL_DEV_WORKFLOW.md` Flow A is the default (protocol PR on `main` -> SDK PR and godot PR on the per-PR tarball -> validate end to end -> merge protocol -> repin both to `@next` -> merge godot, then SDK -> release the SDK); Flow B through `protocol-squad` is legacy. The document covers protocol, js-sdk-toolchain and godot only, so link to it for the godot leg and take the other engines from `.claude/skills/protocol-feature/references/repos/unity.md` and `.claude/skills/protocol-feature/references/repos/bevy.md`.

Issues (`godot-explorer/.claude/skills/godot-issue-writer/SKILL.md`): Problem / Scope / Deliverables / References, no implementation direction (no class, file or API names), labels = kind (`enhancement` | `bug`) + platform (`mobile` default) + domain + process. Use `need definition` while the behaviour is not pinned down and `need tech test` when "feasibility unknown until an engineer probes the engine", which is the label for a pending runtime (L2) check. Board: org project 43 "DAO Explorers", Status `planning`.

## 10. Last verified
2026-10-10 against godot-explorer `origin/main` cada2d93da (the local clone's working tree was on `fix/emote-interop-2986`) and protocol `origin/main` d7ddc10.
