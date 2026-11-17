---
name: protocol-review
description: Phase 6 of a Decentraland protocol proposal, or a standalone cross-layer review of any protocol PR: checks ids, field numbers, optional-ness, grow-only parity, defaults, consumer pins, merge order and PR-body house style against js-sdk-toolchain, unity-explorer, bevy-explorer and godot-explorer. Invoke with /protocol-review <PR number | proposals/<slug>>; protocol-feature routes here automatically.
argument-hint: "[proposals/<slug> | protocol PR number] [--strict] [--post]"
disable-model-invocation: true
---

# Phase 6: review

Read-only. Findings are graded P0 (blocks merge), P1 (fix before merge), P2 (minor), the vocabulary `decentraland-bot` uses on protocol PRs. `--post` is execute-only and asks once per comment before `gh pr comment`.

Paths are relative to each repo's root. Read `.claude/skills/protocol-feature/references/pr-styles.md` for each repo's body rules and `references/repos/<engine>.md` for pins and registration lists.

## 1. Collect

- Bundle from the router or the arguments; a bare PR number creates a review-only stub bundle at phase 6.
- `gh pr view <n> --repo decentraland/protocol --json title,body,baseRefName,headRefName,files,reviews,comments` and `gh pr diff <n>`; follow every linked PR (`decentraland/<repo>#<n>`) the same way. Read the bundle's `links:`.
- `bash .claude/skills/protocol-feature/scripts/field-numbers.sh <PBMessage>` and `scripts/next-component-id.sh --check <id>` for every message and id the diff touches; `scripts/consumer-pins.sh --commit <protocol head sha>`; `scripts/engine-support.sh <PbName>` for each new field or component.

## 2. Protocol checks

- Numbers: every new field number and id is `NEXT_SAFE` or higher across branches, open PRs and engine copies; skipped numbers are explained in the PR body (`## Field numbering`) and handled per `policy.reserve_bevy_numbers`.
- Shape: new fields `optional`; no existing field renamed, retyped or made `optional`; enum first value 0 with the prefix; exactly one `option`+`ecs_component_id` line per component file; new component in `public/sdk-components.proto` (new API in `public/sdk-apis.proto`); defaults documented in trailing comments; message doc comment states entities, writer, LWW vs grow-only, locality.
- CI: `validate-compatibility` ran (it only runs on pushes to upstream non-main branches; a fork PR has no breaking check, so run `make buf-breaking` locally); `build-deploy` green and the "Test this pull request" comment present.
- rfc4 edits come with an ADR-104 (RFC-4) change; comms messages beyond that are out of v1 scope and get a note, not a verdict.

## 3. Alignment matrix (fill `.claude/skills/protocol-feature/assets/review-report-template.md`)

- Fields and numbers: proto == unity `Explorer/Assets/Protocol/DecentralandProtocol/<Name>.gen.cs` == bevy vendored `crates/dcl_component/src/proto/...` (byte-equal to the merged proto) == godot pin commit contains the proto == sdk `playground-assets.api.md` shows the property.
- Ids: `option` value == unity `ComponentID.gen.cs` == bevy `SceneComponentId` const == godot generated enum (from the file name).
- Grow-only parity across the four lists: sdk `scripts/protocol-buffer-generation/generateIndex.ts` `GROWN_ONLY_COMPONENTS`, godot `lib/build.rs` `GROW_ONLY_SET_COMPONENTS`, bevy `reg!(..., ro)` / `update_crdt` (its `add_crdt_go_component` has no call sites), unity `AsProtobufResult()`. Pre-existing drift (`ExplorerUiEventsResult` and `ExplorerItemPurchaseResult` missing in godot) is reported as P1 even when unrelated, because a new result component inherits it.
- Defaults: proto comments == engine code == SDK helpers; the behaviour in section 3 of the proposal == what each engine PR implements (divergences are P1 with paths).
- Registration present in every engine PR (unity `ComponentsContainer.cs`, bevy `add_crdt_*`, godot `update_<name>`); consumers exist outside generated directories.

## 4. Pins and merge order

- sdk: both `package.json` files pin a published version (no `http`, `file`, `git`); unity: `scripts/package.json`, `package-lock.json` and the regenerated `.gen.cs` agree on a published `@next` build; godot: `PROTOCOL_FIXED_VERSION_URL` is an npm URL, not sdk-team-cdn; bevy: vendored file matches the merged proto; test scene: pinned per `policy.test_scene_pin`.
- Merge gate per `policy.merge_gate`: for each engine, an implementation PR linked, or a parity-gap issue filed; the SDK PR present. Before writing that none exists, search each engine (`gh pr list --repo decentraland/<engine> --search '<component>' --state all`, `gh issue list --repo decentraland/<engine> --search '<component>' --state all`) and cite the search. Missing = P0 under `all-accounted`.
- Merge-order checklist from `actions.md`; list the pending repins by repo.

## 5. PR-body audit

Each PR against its repo's rules in `pr-styles.md` (protocol: lead paragraph, per-field defaults, field numbering, how to test, implementation links; godot: What / Why / Test plan with `- [ ] **Expected:**` boxes, Unity parity; unity: template sections and QA TEST STEPS on `sdk7testscenes.dcl.eth`; sdk: what/why, how to test, proof, repin checklist; bevy: Problem / Fix / verification scene). A body that narrates the diff or hides a ride-along behaviour change is P1.

## 6. Output

`review.md` from the template: matrix, findings with path or PR evidence, pins, merge-order readiness, follow-ups (docs page, sdk-skills text, ADR Draft -> Living, parity issues for non-gating engines). Bundle: `status: in-review`, Gate log row 6 `passed` only when there is no P0; `status: done` when the user confirms the protocol merge and the repins. Standalone review: the stub keeps the report. `--post` in execute mode: one `gh pr comment` per finding group, each confirmed.

## Common mistakes

- Reviewing the protocol diff alone: the failures are in the consumers (unregistered component, wrong list, stale pin).
- Trusting `make check-component-id` or the local tree for collisions.
- Approving an engine PR still pinned to the PR tarball.
- Accepting "implemented in Unity" as the merge gate when policy says every engine is accounted for.
- Reporting style nits as P0, or a wire break as P2.
