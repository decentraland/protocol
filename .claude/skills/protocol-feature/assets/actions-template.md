# Actions: <title> (<slug>)

Mode: plan | execute · Protocol source while PRs are open: `<tarball URL or local link>` · After the protocol merge: `@dcl/protocol@next` (or the exact `1.0.0-<runId>.commit-<sha7>`).

Blocks are in merge order. In plan mode every block is a brief; in execute mode a block is done only when its gate passed. Steps that need a confirmation are marked `[confirm]`.

## 0. Protocol (decentraland/protocol)
- Branch: `feat/<slug>` from `origin/main`
- Files: `proto/decentraland/...` (diff in `protocol.diff`), `public/<index>.proto`
- Commands: `make install && make buf-lint && make buf-breaking && make test`; `make list-components-ids`
- Gate: all green
- PR: title `feat: ...`; body `pr-protocol.md` `[confirm: gh pr create]`
- After CI: copy the tarball URL from the "Test this pull request" comment into `links.protocol_tarball`

## 1. js-sdk-toolchain
- Branch: `feat/<slug>` from `origin/main`
- Protocol source: `npm i --save-exact "<tarball>"` in the repo root and in `packages/@dcl/sdk-commands/`; after the protocol merge `make update-protocol`
- Files: `test/ecs/components/<Name>.spec.ts`, `packages/@dcl/playground-assets/etc/playground-assets.api.md` (regenerated), `test/snapshots/**/*.crdt` (regenerated), plus hand-written surfaces when needed (`extended/<Name>.ts`, `components/index.ts`, `components/types.ts`, `ecs/src/index.ts`, react-ecs files, `GROWN_ONLY_COMPONENTS`)
- Commands: `make install && make build && make test`; snapshots: `UPDATE_SNAPSHOTS=true npx jest --runTestsByPath test/snapshots.spec.ts` then rerun without the env var; `grep -rn "ERR!" test/snapshots/` must be empty `[confirm: overwriting goldens]`
- Gate: `make build && make test && make lint`
- PR: `pr-sdk.md` `[confirm]`

## 2. unity-explorer
- Branch: `feat/<slug>` from `origin/dev`
- Protocol source: `cd scripts && npm install "<tarball>" && npm run build-protocol`; after the merge `npm install @dcl/protocol@next && npm run build-protocol`
- Files: `scripts/package.json` + lockfile, regenerated `Explorer/Assets/Protocol/DecentralandProtocol/*.gen.cs`, the system(s) that read the field, EditMode test; new component: `IDirtyMarker.cs`, `ComponentsContainer.cs`, feature folder, plugin, container registration
- Gate: `npm run build-protocol` (Unity compile and tests are a human step: `make test-editmode`, `metaforge explorer run <PR>`)
- Hand-off for medium/large: `feature-description-unity.md` in this bundle -> copy to the unity repo root and run `claude --agent dcl-sdk-feature-architect --permission-mode plan`
- PR: `pr-unity.md` `[confirm]`

## 3. bevy-explorer
- Branch: `feat/<slug>` from `origin/main`
- Protocol source: copy only the touched `.proto` file(s) from the protocol branch the vendored tree follows into `crates/dcl_component/src/proto/...`; say which branch in the PR
- Files: vendored proto, consumer (`crates/...`), exhaustive struct literals (`grep -rn 'Pb<Name> {' crates`), new component: `build.rs` stem, `SceneComponentId` const, `impl DclProtoComponent`, registration
- Gate: `cargo fmt --all -- --check && cargo clippy --locked -- -D warnings && cargo test --all`
- PR: `pr-bevy.md` `[confirm]`

## 4. godot-explorer
- Branch: `feat/<slug>` from `origin/main`
- Protocol source: set `PROTOCOL_FIXED_VERSION_URL` in `src/install_dependency.rs` to the tarball (after the merge: the published npm URL), wipe `lib/src/dcl/components/proto/`, `cargo run -- install --no-templates`
- Files: the Rust system under `lib/src/scene_runner/components/`, GDScript under `godot/src/decentraland_components/`, exhaustive literals (`grep -rn 'Pb<Name> {' lib/src`), new component: the 7 wiring steps
- Gate: `cd lib && cargo fmt --all && cargo clippy -- -D warnings`; `cargo run -- build`; `cargo run -- run --itest`; `gdformat godot/ && gdlint godot/`
- PR: `pr-godot.md` `[confirm]`; mobile builds via the `build` label `[confirm]`

## 5. sdk7-test-scenes
- Folder `scenes/<x>,<y>-<slug>`; `npm install` at the root, `npm run check-parcels`; pin the SDK PR tarballs while open, a published SDK before merge
- Gate: `npm run build` in the scene
- PR: `pr-test-scene.md` `[confirm]`

## 6. docs / sdk-skills / adr
- docs: page under `creator/sdk7/...` + `creator/SUMMARY.md` + version hint; PR stays draft until an `@dcl/sdk` release
- sdk-skills: the skill text that describes today's behaviour
- adr: Draft -> Living once adopted
- Each may be `N/A: <reason>`

## Merge order checklist
- [ ] protocol merged -> `@next` published
- [ ] sdk repinned to the published build (both package.json files)
- [ ] unity repinned (`scripts/package.json`, lockfile, `.gen.cs` regenerated)
- [ ] godot pin is an npm URL, not sdk-team-cdn
- [ ] bevy vendored file byte-equals the merged proto
- [ ] sdk + engines merged
- [ ] test scene merged on a published SDK
- [ ] docs / sdk-skills / adr follow-ups filed or N/A
