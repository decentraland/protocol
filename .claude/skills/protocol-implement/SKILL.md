---
name: protocol-implement
description: Phase 5 of a Decentraland protocol proposal: per-repo implementation briefs in merge order for js-sdk-toolchain, unity-explorer, bevy-explorer, godot-explorer, the sdk7 test scene, docs and sdk-skills, with pins, build gates and PR bodies; execute mode applies the edits. Invoke with /protocol-implement proposals/<slug>; protocol-feature routes here automatically.
argument-hint: "proposals/<slug> [--repos sdk,unity,bevy,godot,test-scene,docs,sdk-skills] [--tarball <url>|@next] [--execute]"
disable-model-invocation: true
---

# Phase 5: implementation

One brief per consumer, in merge order, each with the protocol source it pins, the files it touches, the gate it must pass and the PR body it will carry. Plan mode writes `actions.md` and `pr-<repo>.md`; execute mode applies each brief in its repo and stops before every git or GitHub write.

Why the order: the SDK's `check-local-deps` CI job rejects http/file pins on PRs to `main`, unity and godot build from published tarballs, and a protocol change merged before any consumer validated it is permanent. So: protocol PR -> consumers on the PR tarball -> protocol merge publishes `@next` -> repin -> merge consumers -> test scene -> docs / sdk-skills.

Paths are relative to each repo's root. Read the engine's `.claude/skills/protocol-feature/references/repos/<engine>.md` while writing its brief; copy the skeletons from `.claude/skills/protocol-feature/assets/actions-template.md` and `.claude/skills/protocol-feature/assets/engine-pr-bodies.md`.

## 1. Entry

- `bash .claude/skills/protocol-feature/scripts/proposal-gate.sh <proposal.md> 5` prints `OK`.
- Inputs: sections 2-4 of the proposal, `policy.merge_gate` and `policy.rollout_includes`, and the protocol source: `links.protocol_tarball` while the protocol PR is open, `@next` (or the exact `1.0.0-<runId>.commit-<sha7>`) after it merged, or a local link (`npm install ../protocol`) for a quick loop. `bash .claude/skills/protocol-feature/scripts/consumer-pins.sh` shows what each consumer pins today.
- `--repos` limits the briefs; everything else is written as `N/A: <reason>` in section 5.

## 2. Briefs

**js-sdk-toolchain** — pin in root `package.json` and `packages/@dcl/sdk-commands/package.json` (`npm i --save-exact "<tarball>"` in both; after the merge `make update-protocol`); `make install && make build` regenerates `packages/@dcl/ecs/src/components/generated/` (gitignored, never hand-edited); add the field to every literal in `test/ecs/components/<Name>.spec.ts` or write the spec for a new component; regenerate `packages/@dcl/playground-assets/etc/playground-assets.api.md` (committed) and every `test/snapshots/**/*.crdt` golden (`UPDATE_SNAPSHOTS=true npx jest --runTestsByPath test/snapshots.spec.ts`, rerun without the env var, `grep -rn "ERR!" test/snapshots/` must be empty); hand-written surfaces only when the field reaches one (`systems/events.ts`, react-ecs `Label/types.ts`, `uiTransform/`, extended helpers with their 4-file wiring, `GROWN_ONLY_COMPONENTS` for result components with an `addValue` test). Gate: `make build && make test && make lint`.

**unity-explorer** — `cd scripts && npm install "<tarball>" && npm run build-protocol` (regenerates committed `Explorer/Assets/Protocol/DecentralandProtocol/*.gen.cs`; new files need Editor-created `.meta`); small field: the system that reads it plus an EditMode test (#3487, #9902 precedents); new component: `IDirtyMarker.cs` partial, `ComponentsContainer.cs` registration (`AsProtobufComponent()` / `AsProtobufResult()`), feature folder under `Explorer/Assets/DCL/SDKComponents/<Feature>/`, plugin registered in `StaticContainer.ECSWorldPlugins` or `DynamicWorldContainer` when comms are needed. Resolve proto3 defaults at read time (`HasX ? X : default`), never write them back. Gate: `npm run build-protocol`; Unity compile and tests are a human step. Medium/large: hand off through `feature-description-unity.md` (see the router, section 7).

**bevy-explorer** — copy only the touched `.proto` file(s) into `crates/dcl_component/src/proto/...` from the protocol branch the vendored tree follows (state which in the PR); fix exhaustive literals (`grep -rn 'Pb<Name> {' crates`, e.g. `From<&UserProfile> for AvatarShape`); new component: `build.rs` stem, `SceneComponentId` const in `crates/dcl_component/src/lib.rs`, `impl DclProtoComponent`, `add_crdt_lww_component::<PbX, X>(SceneComponentId::X, ComponentPosition::...)` (forgetting it silently ignores scene data); engine-written results use `RendererSceneContext::update_crdt` plus `reg!(..., ro)` in `crates/scene_inspector/src/manual_registry.rs` (`add_crdt_go_component` exists but has no call sites); restricted action: JS module, `crates/dcl/src/js/restricted_actions.rs`, dcl_deno `#[op2]` + `ops()`, dcl_wasm wrapper, `RpcCall` variant, consumer. Gate: `cargo fmt --all -- --check && cargo clippy --locked -- -D warnings && cargo test --all`.

**godot-explorer** — set `PROTOCOL_FIXED_VERSION_URL` in `src/install_dependency.rs` (tarball while open; published npm URL after), wipe `lib/src/dcl/components/proto/`, `cargo run -- install --no-templates`; fix exhaustive literals (`..Default::default()`); small field: read it in the Rust system or godot class, act in GDScript; new component: `lib/src/scene_runner/components/<name>.rs` `update_<name>`, `components/mod.rs`, `SceneUpdateState` + `next()` in `scene.rs`, `state_name` + match arm in `update_scene.rs`, per-entity maps in both `Scene` constructors and `deleted_entities.rs`, GDScript under `godot/src/decentraland_components/`; grow-only: `GROW_ONLY_SET_COMPONENTS` in `lib/build.rs`; restricted action: JS shim, `#[op2]` with sentinels for optionals, `RpcCall`, `process_rpcs`, handler with `_player_is_inside_scene`. New avatar logic goes to `avatar_anim_helpers.gd` (`avatar.gd` is at the gdlint line cap). Gate: `cd lib && cargo fmt --all && cargo clippy -- -D warnings`, `cargo run -- build`, `cargo run -- run --itest`, `gdformat godot/ && gdlint godot/`.

**sdk7-test-scenes** — `scenes/<x>,<y>-<slug>` (no workspaces; `npm install` at the root then `npm run check-parcels`), `scene.json` `worldConfiguration.name: sdk7testscenes.dcl.eth`, SDK PR tarballs while open and a published SDK before merge (`policy.test_scene_pin`). Gate: `npm run build` in the scene.

**docs / sdk-skills / adr** — docs page under `creator/sdk7/...` on `origin/main` paths plus `creator/SUMMARY.md` and the version hint, PR kept draft until an `@dcl/sdk` release; the sdk-skills text that described today's behaviour; ADR Draft -> Living after adoption. Each `N/A: <reason>` when policy allows.

Grow-only result components list the four registration points explicitly: SDK `GROWN_ONLY_COMPONENTS`, godot `GROW_ONLY_SET_COMPONENTS`, unity `AsProtobufResult()`, bevy `update_crdt` + `reg!(..., ro)` in `manual_registry.rs`; they are already out of sync (`ExplorerUiEventsResult` and `ExplorerItemPurchaseResult` are in the SDK list but missing in godot) and a new one inherits the drift unless named.

## 3. Repin lifecycle (after the protocol merge)

sdk `make update-protocol`; unity `cd scripts && npm install @dcl/protocol@next && npm run build-protocol`; godot `PROTOCOL_FIXED_VERSION_URL` to `https://registry.npmjs.org/@dcl/protocol/-/protocol-1.0.0-<runId>.commit-<sha7>.tgz`, wipe, reinstall; bevy nothing (the copied file is already the merged one; confirm byte-equality). `scripts/consumer-pins.sh --commit <sha>` answers "does this consumer's pin contain the merged commit".

## 4. Plan vs execute

- Plan: `actions.md` with one block per repo in merge order (path, branch, protocol source, files with diff sketches, commands, gate, PR title and body file) and `pr-<repo>.md` in each repo's house style (`.claude/skills/protocol-feature/references/pr-styles.md`); `feature-description-unity.md` in the bundle when the Unity part is medium or large. Nothing outside the bundle changes, and no PR body claims a gate, a device run or a heads-up that did not happen: those lines stay `- [ ]` "to run" / "to post".
- Execute: per repo, branch `feat/<slug>` from the fetched default branch on a clean checkout, apply the brief, run the gate, then stop before each `git commit`, `git push`, `gh pr create` (body printed in full), snapshot overwrite or pin bump the user did not name. Per `policy.execute_delegation`, one subagent per repo with its brief; Unity medium/large through the architect agent.

## 5. Exit

- Section 5 table filled (branch, source, files, gate, PR, state), `links.*_pr` filled as PRs open; `status: implementing`, `phase: 6`, Gate log row 5, Decision log rows for the protocol source and any `N/A`.
- `bash .claude/skills/protocol-feature/scripts/proposal-gate.sh <proposal.md> 6` prints `OK`.
- Print the next command: `/protocol-review proposals/<slug>`.

## Common mistakes

- Syncing bevy's whole vendored tree: it follows `experimental-bevy`, so a blind sync from `main` deletes bevy-only features.
- Leaving a tarball pin in `packages/@dcl/sdk-commands/package.json`: the SDK PR cannot merge.
- Running `make update-snapshots` as a reflex, or committing a snapshot that contains `ERR!`.
- A new `.gen.cs` without its `.meta`, or a hand-edited generated file.
- A per-frame `tracing::error!` / `push_error` in godot (Sentry quota) where `debug!` belongs.
- Forgetting one of the four grow-only lists, or the bevy `add_crdt_*` registration (no compile error, scene data silently dropped).
