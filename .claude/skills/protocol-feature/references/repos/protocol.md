# protocol repo conventions
How `decentraland/protocol` lays out, numbers, validates, publishes and reviews schema changes, so a feature lands on `main` without breaking the engines that consume it.

## Contents
1. [Layout and the canonical component header](#1-layout-and-the-canonical-component-header)
2. [The components directory is a codegen glob](#2-the-components-directory-is-a-codegen-glob)
3. [Component ids](#3-component-ids)
4. [Field numbers main deliberately skips](#4-field-numbers-main-deliberately-skips)
5. [Field and message conventions](#5-field-and-message-conventions)
6. [Deprecation and compatibility](#6-deprecation-and-compatibility)
7. [Validation and CI](#7-validation-and-ci)
8. [Public index files](#8-public-index-files)
9. [Publishing and tarball URLs](#9-publishing-and-tarball-urls)
10. [Branches](#10-branches)
11. [PR shape and reviewers](#11-pr-shape-and-reviewers)
12. [Restricted actions (kernel/apis)](#12-restricted-actions-kernelapis)
13. [Comms and the repo CLAUDE.md](#13-comms-and-the-repo-claudemd)

## 1. Layout and the canonical component header

- One `.proto` per SDK component in `proto/decentraland/sdk/components/<snake_name>.proto`, package `decentraland.sdk.components`. File names are snake_case (`FILE_LOWER_SNAKE_CASE` lint); the `proto/decentraland/sdk/components/README.md` template is stale on two points: it says PascalCase file names and omits the `package` line, which `(common.ecs_component_id)` and the `PACKAGE_DIRECTORY_MATCH` lint both need.
- The id option lives in `proto/decentraland/sdk/components/common/id.proto` (package `decentraland.sdk.components.common`), not in `proto/decentraland/common/sdk/`, which only holds `user_data.proto`:

```protobuf
extend google.protobuf.FileOptions {
  optional int32 ecs_component_id = 50000;
}
```

- Copy the header of `proto/decentraland/sdk/components/avatar_nametag.proto` (#474, id 1221), the most recent well-documented component:

```protobuf
syntax = "proto3";

package decentraland.sdk.components;

import "decentraland/common/colors.proto";
import "decentraland/sdk/components/common/id.proto";

option (common.ecs_component_id) = 1221;

// <what it does, which entities it is valid on, who writes it, local vs relayed>
message PBAvatarNametag {
  string label = 1;
  optional decentraland.common.Color3 label_color = 2;      // (default: the client's native nametag text color)
}
```

- The root message is `PB` + PascalCase(file stem), because js-sdk-toolchain imports `PB${componentPascalName}` from `./pb/decentraland/sdk/components/${componentFile}.gen` (`scripts/protocol-buffer-generation/generateIndex.ts`) and godot derives `Pb<Pascal>` with `snake_to_pascal` in `lib/build.rs:get_component_id_and_name`.
- Shared value types live in `proto/decentraland/common/` (`vectors.proto`, `colors.proto`, `texture.proto`, `border_rect.proto`, `floats.proto`); the README says these "will never change".

## 2. The components directory is a codegen glob

- Every `.proto` directly in `sdk/components/` is a component: js-sdk-toolchain lists the directory with `getFilePathsSync(definitionsPath, false)` filtered to `.proto` (`scripts/protocol-buffer-generation/index.ts`) and godot reads `COMPONENT_BASE_DIR = "src/dcl/components/proto/decentraland/sdk/components/"` with `fs::read_dir` (`lib/build.rs`). A shared enum or message file without an id placed there breaks both builds.
- Shared enums and sub-messages go in `proto/decentraland/sdk/components/common/` (package `decentraland.sdk.components.common`, no id): `avatar_mask.proto`, `camera_transition.proto`, `camera_type.proto`, `explorer_ui.proto`, `input_action.proto`, `loading_state.proto`, `media_state.proto`, `raycast_hit.proto`, `texts.proto`. That is also the only place where a type shared by a `~system/*` API and a component gets one TS identity (#455 moved the ExplorerUi enum there; `TriggerEmoteRequest.mask` reuses `common.AvatarMask`).
- Both id parsers are line based: `getComponentId` in js-sdk-toolchain `scripts/protocol-buffer-generation/generateProtocolBuffer.ts` and `get_component_id` in godot `lib/build.rs` keep the lines that contain both `ecs_component_id` and `option` and throw `There are more than one match with `ecs_component_id` and `option`` or ``ecs_component_id` is missing.`. Write exactly one such line per file and keep both words out of comments.

## 3. Component ids

- On `main` (`bash scripts/list-components-ids.sh`, 64 ids): 1017-1106 with gaps, then 1209-1222 contiguous; max is 1222 (`explorer_item_purchase_result`).
- Claimed off-main as of 2026-10-10 (`git grep` over every `origin/*` branch): 1200-1208, 1500, 1501, 1503, plus 1223-1225 on the open-PR heads listed below; 1502 is unused on every branch, so write the set, not a range. 1200-1203 and 1206-1208 sit on `experimental-bevy` and `protocol-squad`; 1204 `light` and 1205 `spotlight` only on `origin/make-force-render-optional`; 1100 `ui_scroll_result` on `origin/chore/scroll-result-id-align`.
- Open PRs claim ids before they reach any branch grep of `main`: 1223 `skybox` (#495, `feat/reflection-map`), 1224 `player_voice_state` and 1225 `voice_chat_modifier_area` (#499, `feat/nearby-voice-sdk`). Next safe id today: **1226**. Re-derive it every run.
- `make check-component-id ID=1226` (prints `id 1226 is free` or `id 1226 is taken`) and `make list-components-ids` only run `find . -name "*.proto"` over the local tree, which is how #464 shipped 1221 twice until `decentraland-bot` flagged it. Run the cross-branch loop and the open-PR list as well:

```bash
git fetch origin
for b in $(git branch -r | grep -v HEAD); do git grep -h -o 'ecs_component_id) = [0-9]*' $b -- proto 2>/dev/null; done | sed 's/.*= //' | sort -n | uniq | tail
gh pr list --repo decentraland/protocol --state open --json number,title,headRefName
```

## 4. Field numbers main deliberately skips

Gaps are not written as `reserved` on `main`; they exist only in PR bodies (#489: "The field numbers match the ones already carried on `experimental-bevy`, so the wire format is identical on both branches"). Verified today with `git show origin/<branch>:proto/...`:

| Message (file) | Number(s) | Meaning | Branch owning it |
|---|---|---|---|
| `PBAvatarShape` (`avatar_shape.proto`) | 13 | `repeated string force_render` | experimental-bevy, protocol-squad |
| `PBUiText` (`ui_text.proto`) | 7, 8 | `outline_width`, `outline_color` | protocol-squad only (#472 dropped UiText outline); main took `font_src = 9` |
| `PBUiInput` (`ui_input.proto`) | 14, 15 | `multi_line`, `clear_on_submit` | experimental-bevy, protocol-squad; main took `font_src = 16` |
| `PBAvatarModifierArea` (`avatar_modifier_area.proto`) | 4 / 5 | `movement_settings` / `use_collider_range` | 4 protocol-squad only; 5 both |
| `PBAvatarEquippedData` (`avatar_equipped_data.proto`) | 3 | `repeated string force_render` | experimental-bevy, protocol-squad |
| `PBAvatarBase` (`avatar_base.proto`) | 6 | `optional bool talking` | experimental-bevy (#493 merged there 2026-09-23) |
| `PBMeshCollider` oneof `mesh` (`mesh_collider.proto`) | 6 | `GltfMesh gltf` | experimental-bevy, protocol-squad |
| `PointerEventType` (`common/input_action.proto`) | 6, 7, 8 | `PET_DRAG_LOCKED`, `PET_DRAG`, `PET_DRAG_END` | experimental-bevy, protocol-squad |
| `PointerType` (`primary_pointer_info.proto`) | 2, 3, 4 | `POT_PAD`, `POT_TOUCH`, `POT_WAND` | experimental-bevy, protocol-squad |

The `experimental` branch keeps main's numbers everywhere and only adds `enum AvatarEmoteMask { AEM_FULL_BODY = 0; AEM_UPPER_BODY = 1; }` to `avatar_shape.proto`; it is deprecated by #485/#492. Before adding a field, compare the file across branches and open PR heads (`gh pr diff <n>`):

```bash
for b in origin/main origin/experimental-bevy origin/protocol-squad origin/experimental; do echo "== $b"; git show $b:proto/decentraland/sdk/components/<file>.proto | grep -nE '= [0-9]+;'; done
```

## 5. Field and message conventions

- Declare every NEW field on an existing component `optional` (every 2026 addition does: `font_src`, `realm`, `mask`, `state`, `max_camera_distance`), because ts-proto emits a non-optional proto3 scalar as a required TS property and scene object literals passed to `Component.create()` stop type-checking. Do not add `optional` to a field that already exists on `main` (section 6).
- Name a new `bool` so that `false`/absent keeps today's behaviour; proto3 cannot tell `false` from unset without `optional`.
- End each field with a trailing comment giving meaning, units and default, e.g. `optional float walk_speed = 1; // Maximum speed when walking (in meters per second)` (`avatar_locomotion_settings.proto`) and `optional string font_src = 9; // a ttf font file in the scene content or a Google Fonts family name; `font` is the fallback (default: unset)` (`ui_text.proto`).
- The message doc comment states: which entities it is valid on (`engine.PlayerEntity`, another player's entity, any entity with an AvatarShape, the scene root), who writes it (scene or explorer), LWW vs grow-only, local-only vs relayed, what an engine without support does, and the fallback for invalid values (`avatar_nametag.proto` covers all of these).
- Enum values carry a prefix derived from the enum name (`AMT_`, `ES_`, `CL_`, `BM_`, `PET_`, `POT_`, `TW_`, `TAMT_`) since the `ENUM_VALUE_PREFIX` lint is off but the protobuf enum-value namespace is per package. The zero value is the backward-compatible meaning: `avatar_emote_command.proto` documents `ES_STARTED = 0` as "the zero value and is used for backward compatibility". Bit-flag enums use powers of two read through a `uint32` mask (`ColliderLayer` + `collision_mask` in `mesh_collider.proto`).
- Entity references are `uint32` (`billboard.proto:target_entity`, `virtual_camera.proto:look_at_entity`, `main_camera.proto:virtual_camera_entity`); asset paths are `string src` resolved through the scene content map.
- Extension points are `oneof` blocks numbered from 10: `OpenExplorerUiRequest { oneof params { ItemPurchaseParams item_purchase = 10; } }` in `restricted_actions.proto`, `oneof event { UiOpened opened = 10; UiClosed closed = 11; }` in `explorer_ui_events_result.proto`. Outcome variants are empty messages in a oneof rather than an enum so per-status data can be added later (#464).
- Explorer-written result components are grow-only on the scene root with a `uint32 timestamp` scene tick and a `request_id` echo (`explorer_ui_events_result.proto`); grow-only is not declared in proto, each consumer hardcodes the list (see the sibling repo files).

## 6. Deprecation and compatibility

- Keep the old field and mark it: `optional float max_player_distance = 6; // @deprecated use `max_distance` instead (same semantics)` (`pointer_events.proto`, #470). For an RPC put `// @deprecated, use TeleportTo with `realm` ...` above it (`restricted_actions.proto:ChangeRealm`). A removed number becomes `reserved 1; // deprecated `name` prop` (`animator.proto`) or `reserved 5 to 10;` plus `reserved "is_repeating", ...` (`rfc4/comms.proto:PlayerEmote`). `// @experimental` marks an unstable field (`animator.proto:weight`).
- `proto/buf.yaml` sets `breaking: use: [WIRE_JSON]`, so names matter, not only numbers. Results of `buf breaking` 1.8.0 against GitHub `main`, run 2026-10-10:
  - adding `optional` to an EXISTING field is reported as breaking ("moved from outside to inside a oneof");
  - renaming a field is reported as breaking (`json_name` and `name` both change);
  - adding a NEW `optional` field 14 to `PBAvatarShape` passes breaking and lint.
- Renames are free while the PR is open and nothing has shipped (`decentraland-bot` on #464: proto field names are not on the wire); after `main`, add a new field and deprecate the old one.

## 7. Validation and CI

Local sequence (buf 1.8.0 is pinned by `BUF_VERSION` in the `Makefile` and downloaded into `node_modules/.bin/buf`):

```bash
make install && make buf-lint && make buf-breaking && make test
```

- `buf-lint` = `./node_modules/.bin/buf lint proto/`; `buf-breaking` = `./node_modules/.bin/buf breaking proto/ --against 'https://github.com/decentraland/protocol.git#subdir=proto'`, so it needs network and always compares with GitHub `main`, never with your base branch; `test` = `buf-lint` then `bash scripts/test.sh`, which runs protoc (TS via `protoc-gen-dcl_ts_proto` + `--csharp_out`) over every `public/*.proto` and then `tsc -p tsconfig.json`.
- `.github/workflows/validate.yml` (`validate-compatibility`) triggers on `push` with `branches-ignore: main`: `make install`, `make buf-breaking`, `make buf-lint`, `make test`, `./scripts/check-proto-compabitility.sh` (buf breaking again). Pushes to a fork do not run it, so a fork PR gets no breaking check.
- `.github/workflows/build-and-publish.yml` (`build-deploy`) runs on `pull_request`, pushes to `main`/`experimental`, `workflow_dispatch` and releases: `make install`, `make buf-build`, `make test` (lint included, breaking not), then `decentraland/oddish-action` publishes to npm + S3 and `notify_deployment` posts the "Test this pull request" comment.
- `.github/` has no PR template.

## 8. Public index files

- `public/sdk-components.proto` is an `import public` index compiled by `make test` and shipped as `out-ts`/`out-js`; add one line per new component: `import public "decentraland/sdk/components/<file>.proto";`. 19 older components are missing today (`avatar_locomotion_settings`, `light_source`, `trigger_area`, `virtual_camera`, ...); the SDK does not read this file, but add the line anyway as #474 and #426 did.
- `public/sdk-apis.proto` indexes the `proto/decentraland/kernel/apis/*.proto` files exposed to scenes; a new kernel/apis file needs a line there.
- `public/` is not linted (README style guideline 4). `package.json` `files` ships `proto/decentraland`, `out-ts`, `out-js`, `public`, `protoc-gen-bitwise/*.js` and `protoc-gen-bitwise/runtime`, so a proto absent from `public/*` gets no generated TS in the tarball (#454 fixed that for `pulse_clusters`).

## 9. Publishing and tarball URLs

- Every merge to `main` publishes `@dcl/protocol@next`; versions look like `1.0.0-<GitHub runId>.commit-<sha7>`. `npm view @dcl/protocol dist-tags` on 2026-10-10:

```
latest: '1.0.0-2569677750.commit-6ce832a'          # stale, do not use
ci: '1.0.0-21650527315.commit-b658867'
'protocol-squad': '1.0.0-25751414897.commit-a9f7d81'
experimental: '1.0.0-34848312390.commit-ca008c2'
next: '1.0.0-37324405267.commit-d7ddc10'           # main HEAD
'experimental-bevy': '1.0.0-35899496093.commit-329ba0e'
```

- Each PR gets a bot comment with a tarball that consumers can `npm install` during development (the `branch//` double slash is literal, copy it as is):

```
# Test this pull request
- The `@dcl/protocol` package can be tested in scenes by running
   npm install "https://sdk-team-cdn.decentraland.org/@dcl/protocol/branch//dcl-protocol-1.0.0-37323326836.commit-50ce3d7.tgz"
```

- The published form of the same version is `https://registry.npmjs.org/@dcl/protocol/-/protocol-1.0.0-<runId>.commit-<sha7>.tgz` (godot pins that shape). Consumer pins and repin commands are in `.claude/skills/protocol-feature/references/repos/{sdk,unity,bevy,godot}.md`.

## 10. Branches

- `main`: the only target for new features; publishes `@next`.
- `experimental`: still in `build-and-publish.yml` (`BRANCH_TAG` gives it the `experimental` dist-tag) but deprecated: #485 "Bringing missing things from Experimental to move forward with deprecating that package", #492 "Unity-Explorer now uses `@next`/`main` so we no longer need this overcomplex approach". Do not target it.
- `experimental-bevy`: PR #472 "[do not merge] experimental-bevy: protocol-squad features rebuilt on main", one additive commit per feature so each can be proposed to `main` on its own; published as `@dcl/protocol@experimental-bevy` for the matching js-sdk-toolchain and bevy-explorer branches. A bevy-first feature lands as twin PRs with identical numbers: #487 (`feat/font-src` into `experimental-bevy`) then #489 (`feat/font-src-main` into `main`).
- `protocol-squad`: legacy integration branch (PR #202, dist-tag `protocol-squad`), superseded by `experimental-bevy`; #472 deliberately left behind `UiText` outline and `AvatarMovementSettings` on `AvatarModifierArea`, which is why those numbers stay skipped on `main` without ever landing.

## 11. PR shape and reviewers

- Branch `feat/<kebab>` (`feat/font-src-main`, `feat/avatar-nametag-main`, `feat/restricted-action-stop-emote`); conventional title `feat: ...` / `fix: ...` / `chore: ...`, sometimes with the id (`feat: AvatarNametag component (id 1221)`); squash merge so the subject ends in `(#NNN)`. The diff is 1-4 proto files plus the index line (#489: four files, +1 line each).
- Body, as in #489/#474/#499: a lead paragraph that says what and why; per-field semantics and defaults with the compatibility statement ("Unset changes nothing, so existing scenes are unaffected"); `## Field numbering` naming every gap and which branch owns it; how to test (#499: "`make buf-lint && make test`; `make list-components-ids` shows 1224 and 1225 unique (1223 is claimed by #495)"); `## Implementation` or `## Related PRs` links to unity-explorer, bevy-explorer, js-sdk-toolchain and, for creator-visible features, sdk7-test-scenes, docs and sdk-skills (#495 links all five). Recent PRs do not cite ADRs; older protos link them (`billboard.proto` -> ADR-198).
- Reviewers seen on 2026 feature PRs: popuz, kuruk-mm, cyaiox, robtfm, pravusjif, davidejensen, EibrielInv, plus `decentraland-bot`, an AI reviewer that posts `## Review: PR #N — <title>` with `### P0 — Blocker`, `### P1 — Should fix before merge`, `### P2 — Minor / Nice-to-have` and re-review rounds; it caught the 1221 collision on #464. Resolve P0/P1 before asking humans.
- README merge order still applies: do not merge the protocol PR before the engine implementation is ready; merge protocol first, then repin the consumer PRs from the tarball to `@next` and merge them.

## 12. Restricted actions (kernel/apis)

- Scene APIs are RPC services in `proto/decentraland/kernel/apis/*.proto`; restricted actions are `service RestrictedActionsService` in `restricted_actions.proto`. The #444 recipe (`feat: restricted action stopEmote()`, +5 lines):

```protobuf
message StopEmoteRequest { }

service RestrictedActionsService {
  // StopEmote will stop the current emote
  rpc StopEmote(StopEmoteRequest) returns (SuccessResponse) {}
}
```

- Reuse `SuccessResponse`/`EmptyResponse` or add a dedicated `<Rpc>Response`; name messages `<Rpc>Request`/`<Rpc>Response` even though the `RPC_REQUEST_STANDARD_NAME` lint rules are disabled. New request fields are `optional` (`TeleportToRequest.realm = 2`, #477), verdicts are enums, params use a oneof from 10 (section 5). A new API file also needs its `import public` line in `public/sdk-apis.proto`.

## 13. Comms and the repo CLAUDE.md

- `proto/decentraland/kernel/comms/rfc4/comms.proto` (LiveKit `Packet` oneof) opens with "It is mandatory to also update that RFC when modifying this file": RFC-4 is `content/ADR-104-comms-protocol.md` in the adr repo (status Living, type RFC, `redirect_from: /rfc/RFC-4`), edited in place; see `.claude/skills/protocol-feature/references/repos/adr.md`. `v3/` is archipelago and `proto/decentraland/pulse/*` is the authoritative-server protocol (`pulse_client.proto` ClientMessage, `pulse_server.proto` ServerMessage).
- The repo `CLAUDE.md` describes only the Pulse/MMO stack and the `protoc-gen-bitwise` C# plugin. The `quantized`, `quantized_power` and `bit_packed` options (`proto/decentraland/common/options.proto`) are used only in `proto/decentraland/pulse/*.proto` and `common/quantization_example.proto`; SDK components use plain `float` and never these options, so ignore `CLAUDE.md` for `sdk/components` and `kernel/apis` work.

## Last verified
2026-10-10 against `origin/main` d7ddc10 (`d7ddc105fe14480f053ae4ad5bcefc375054dd67`); branch facts from `origin/experimental-bevy`, `origin/protocol-squad`, `origin/experimental`; PR facts via `gh pr view`.
