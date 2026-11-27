---
name: protocol-define
description: Phase 4 of a Decentraland protocol proposal: the exact .proto diff with component ids and field numbers checked across every branch, open PR and engine copy, buf lint/breaking/test, the public index line and the protocol PR body. Invoke with /protocol-define proposals/<slug>; protocol-feature routes here automatically.
argument-hint: "proposals/<slug> [--target main|experimental-bevy] [--execute]"
disable-model-invocation: true
---

# Phase 4: definition

Numbers become permanent here. A component id or field number that reaches `main` can never be reused, a released field can never be renamed, retyped or made `optional` (buf 1.8.0 reports all three as breaking against GitHub `main`), and `make check-component-id` sees only the local tree (#464 had to move 1221 to 1222 after a collision). The output is `protocol.diff`, `pr-protocol.md` and `## 4. Definition` with every source that was checked.

Paths are relative to the protocol repo root. Read `.claude/skills/protocol-feature/references/repos/protocol.md` before writing the diff.

## 1. Entry

- `bash .claude/skills/protocol-feature/scripts/proposal-gate.sh <proposal.md> 4` prints `OK`.
- Target branch is `main` unless `policy.allow_experimental_bevy_first` is `yes` and the user asked for `experimental-bevy`; then twin PRs with identical numbers are required (#487 / #489) and the proposal says so.

## 2. Numbers

- Fields: `bash .claude/skills/protocol-feature/scripts/field-numbers.sh <PBMessage>` and take `NEXT_SAFE_FIELD`. It unions `origin/main`, `origin/experimental-bevy`, `origin/protocol-squad`, `origin/experimental`, every open PR touching the file, bevy's vendored copy, godot's extracted copy and the commits the unity and sdk pins resolve to.
- New component: `bash .claude/skills/protocol-feature/scripts/next-component-id.sh` and take `NEXT_SAFE_ID`; confirm with `--check <id>`. Ids on `main` end at 1222, open PRs claim 1223-1225, `experimental-bevy` / `protocol-squad` hold 1200-1208, 1500, 1501, 1503; regenerate, do not trust these numbers.
- Record the skipped numbers and their owners. Per `policy.reserve_bevy_numbers`: `comment` writes `// <n> is <field> on experimental-bevy` next to the new field; `reserved` writes `reserved <n>;`; `none` only notes it in the PR body. Paste the scripts' rationale line into the PR body (#489 precedent: "field numbers match the ones already carried on experimental-bevy").
- Run `make check-component-id ID=<n>` too and label it "local tree only".

## 3. Write the diff

- New field: `optional <type> <lower_snake> = <n>; // <meaning, units> (default: <x>)` appended after the last field of the message, with the `(default: <x>)` in the trailing comment on the field's own line like every other field in the file (longer explanations go in comment lines above it); the message doc comment gains any new semantics (entity validity, writer, LWW vs grow-only, locality, no-op platforms), in the style of `pointer_events.proto` and `avatar_nametag.proto`.
- New component: header order from `avatar_nametag.proto` (`syntax`, `package decentraland.sdk.components;`, imports incl. `decentraland/sdk/components/common/id.proto`, `option (common.ecs_component_id) = N;`), root message `PB` + PascalCase(file name), exactly one line containing both `option` and `ecs_component_id`, plus `import public "decentraland/sdk/components/<snake>.proto";` in `public/sdk-components.proto`. Grow-only result components carry `uint32 timestamp` and echo the request id (`explorer_ui_events_result.proto`).
- New RPC: `message <Rpc>Request {}` / `<Rpc>Response`, `rpc <Rpc>(<Rpc>Request) returns (<Rpc>Response) {}` with a comment, in `service RestrictedActionsService` (#444); a new API file also needs `import public` in `public/sdk-apis.proto`.
- Deprecation: keep the old field, add `// @deprecated use X instead (same semantics)` (#470), never renumber; removed numbers become `reserved N;`.
- rfc4 (`proto/decentraland/kernel/comms/rfc4/comms.proto`) edits require an ADR-104 (RFC-4) update in the same rollout.
- Plan mode: write the unified diff to `protocol.diff`, produced against a scratch export in a temporary directory (`D=$(mktemp -d) && git archive origin/main proto | tar -x -C "$D"`), never next to the bundle and never in the working tree; `buf lint` / `buf breaking --against <another export of origin/main>` and `git apply --check` run there too. Execute mode: branch `feat/<slug>` from `origin/main`, apply, and continue.

## 4. Validate

`make install && make buf-lint && make buf-breaking && make test` (`buf-breaking` needs network; `validate.yml` runs it only on pushes to upstream non-main branches, so a fork PR gets no breaking check), `make list-components-ids`, `make check-component-id ID=<n>`. Plan mode lists the commands as "to run"; execute mode runs them and records results in section 4. Also confirm by eye: every new field is `optional`, every enum's first value is 0, no comment line contains both `option` and `ecs_component_id`.

## 5. ADR

Per `policy.adr_by_size`. Medium: Draft ADR from `content/.SDK-COMPONENT-TEMPLATE.md` (yaml `COMPONENT_ID`, `COMPONENT_NAME: core::<Name>`, `CRDT_TYPE: LastWriteWin-Element-Set | GrowOnly-Value-Set`, commented protobuf, Semantics) written alongside the protocol PR; large: before this phase; otherwise record "none (policy)". Number = the next free after `origin/main` and open PRs, or the ADR PR's own number (both are in use: #324 -> ADR-318, #325 -> ADR-325); state the rationale in the ADR PR body; status `Draft`, type `Standards Track` for components, `spdx-license: CC0-1.0`; link it from the `.proto` comment (`https://adr.decentraland.org/adr/ADR-N`, or a pinned blob URL while unmerged). An ADR exists only when `content/ADR-N-*.md` is on adr `origin/main`; a number that lives only in an open adr PR is cited as that PR, never as `/adr/ADR-N`. Details in `.claude/skills/protocol-feature/references/repos/adr.md`.

## 6. PR body and branch

`pr-protocol.md` from `.claude/skills/protocol-feature/assets/protocol-pr-body.md`: plain-language lead paragraph, per-field semantics and defaults with "unset changes nothing", `## Field numbering` naming the branches, PRs and engine copies checked and the numbers skipped, `## How to test` (`make buf-lint && make test`, `make list-components-ids`), `## Implementation` with one link line per repo (`pending` placeholders), `## Related` (test scene, docs, sdk-skills, ADR). Title `feat: <thing> (id NNNN)` for components or `feat: add <field> to <Message>`; branch `feat/<slug>`. Execute mode: print the body in full, then ask once before `gh pr create --repo decentraland/protocol --base main`. After CI runs, copy the tarball URL from the "Test this pull request" comment (`https://sdk-team-cdn.decentraland.org/@dcl/protocol/branch//dcl-protocol-1.0.0-<runId>.commit-<sha7>.tgz`, the double slash is real) into `links.protocol_tarball`.

## 7. Exit

- `protocol.diff`, `pr-protocol.md`, section 4 complete with the sources checked and the validation results (or "to run"); `status: defined`, `phase: 5`, Gate log row 4, Decision log rows for the numbers, the skip handling and the ADR.
- `bash .claude/skills/protocol-feature/scripts/proposal-gate.sh <proposal.md> 5` prints `OK`.
- Print the next command: `/protocol-implement proposals/<slug>`.

## Common mistakes

- Taking the next number from the local tree or from `main` alone (open PRs #460, #488, #476, #412 claim field numbers today, not only ids).
- Adding `optional` to an existing field to "make it consistent": breaking.
- Renaming a field before checking whether the PR already merged: free before merge, breaking after.
- A new component file without the `package` line or without the `import public` index line (19 older components are missing from the index; add it anyway).
- Writing the diff into the working tree in plan mode.
