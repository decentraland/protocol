# Engine and sibling PR body templates

> Drafting rule: a body written in plan mode describes what will be true when the PR opens. Every verification line stays an unticked `- [ ]` with "to run" until that command appears in this session's transcript, and a heads-up is written as "to post" until someone posted it. Claiming a build, a device run or a Slack message that did not happen is the one thing reviewers in every repo treat as a rewrite request.


Fill-in bodies for the js-sdk-toolchain, unity-explorer, bevy-explorer, godot-explorer, sdk7-test-scenes, docs and adr PRs of one protocol feature, each in that repo's own house style (rules and precedents in `.claude/skills/protocol-feature/references/pr-styles.md`).

## Contents

- [How to use](#how-to-use)
- [js-sdk-toolchain](#js-sdk-toolchain)
- [unity-explorer](#unity-explorer)
- [bevy-explorer](#bevy-explorer)
- [godot-explorer](#godot-explorer)
- [sdk7-test-scenes](#sdk7-test-scenes)
- [docs](#docs)
- [adr](#adr)

## How to use

Copy one fenced block into `pr-<repo>.md` in the bundle, replace every `<...>`, delete the `<!-- -->` guidance and any line that does not apply, print the body in full, then open the PR with the command given under each block. Link siblings as `owner/repo#N` and write "pending" where a PR is not open yet; edit the body once it is. The `🤖 Generated with [Claude Code](https://claude.com/claude-code)` trailer is optional on SDK, unity and bevy, and never used on godot or adr.

## js-sdk-toolchain

Title `feat(ecs): add <Name> component` or `feat: add <field> to <Component>`; branch `feat/<slug>`; base `main`. `REVIEW.md` §2 wants What/why, How to test and Proof; `check-local-deps` blocks merge while the protocol pin is a tarball URL.

````markdown
<What a scene can now do>, backed by <`field` / `Component`> from the protocol. <Why: the gap it closes>.

Depends on decentraland/protocol#<N> — **do not merge before it**.

## What changes

- `@dcl/protocol` pinned to the PR tarball in `package.json` and `packages/@dcl/sdk-commands/package.json` (`npm i --save-exact "<tarball url>"` in both).
- <`test/ecs/components/<Name>.spec.ts`: new | `<key>` added to every literal>; regenerated `packages/@dcl/playground-assets/etc/playground-assets.api.md`, <12> CRDT snapshots, lockfiles.
- <Hand-written surface touched, if any: `packages/@dcl/ecs/src/systems/events.ts`, react-ecs wrapper, `GROWN_ONLY_COMPONENTS` in `scripts/protocol-buffer-generation/generateIndex.ts` with an `addValue` guard test>.

## How to test

```bash
make build && npx jest --testPathPatterns 'test/ecs/components/<Name>'
UPDATE_SNAPSHOTS=true npx jest --runTestsByPath test/snapshots.spec.ts && npx jest --runTestsByPath test/snapshots.spec.ts
grep -rn "ERR!" test/snapshots/   # must print nothing
make lint && make test
```

## Proof

Test scene decentraland/sdk7-test-scenes#<N> (`scenes/<x>,<y>-<slug>`) installs this PR's `@dcl/sdk` and `@dcl/js-runtime` tarballs from the bot comment; <what the scene shows before and after>.

## Before merging

- [ ] decentraland/protocol#<N> merged
- [ ] `@dcl/protocol` repinned from the PR tarball to the published version (`make update-protocol`), lockfiles refreshed, snapshots and `api.md` regenerated

Related: decentraland/unity-explorer#<N> · decentraland/bevy-explorer#<N> · decentraland/godot-explorer#<N> · docs decentraland/docs#<N> (pending)
````

Open with `gh pr create --repo decentraland/js-sdk-toolchain --base main --title "feat(ecs): <title>" --body-file pr-sdk.md`.

## unity-explorer

Title `feat: sdk | <thing>` (lowercase prefix, validated by `semantic / title-matches-convention`); branch `feat/<slug>` off `dev`; base `dev`. All three template sections must be filled; QA runs `## Test Instructions` verbatim.

````markdown
# Pull Request Description

## What does this PR change?

Implements decentraland/protocol#<N> for `<PBMessage>`: <what a scene can now do, 1-3 sentences>. <Default and no-op: unset keeps today's behaviour>.

Not included: <scope left out>.

- `scripts/package.json` pins `@dcl/protocol` to <the PR tarball | `1.0.0-<runId>.commit-<sha7>`>; `*.gen.cs` regenerated with `npm run build-protocol`; repin to `@next` once the protocol PR merges.
- <system or component touched, in words, one bullet each>; EditMode test `<Path>/Tests/<Name>Should.cs` covers <cases>.

Test scene: decentraland/sdk7-test-scenes#<N> (`scenes/<x>,<y>-<slug>`). SDK side: decentraland/js-sdk-toolchain#<N>. Bevy: decentraland/bevy-explorer#<N>. Godot: decentraland/godot-explorer#<N>.

## Test Instructions

**Steps (standard run)**:
```bash
metaforge explorer run XXXX  # ← replace with this PR number
```

Launch with `--dclenv zone --realm sdk7testscenes.dcl.eth --position <x>,<y>` (already on zone: `/goto sdk7testscenes.dcl.eth/<x>,<y>`). MetaMask users: select SEPOLIA.

### QA TEST STEPS

Use the build from this PR to enter the ZONE/SEPOLIA world `sdk7testscenes.dcl.eth` at position `<x>,<y>` and confirm that <one observable sentence QA can mark pass/fail>.

| Click / do | Expected |
| --- | --- |
| <on-screen control or action> | <what QA sees> |
| <regression: the old path> | <unchanged behaviour> |

(the test scene can also be run locally: https://github.com/decentraland/sdk7-test-scenes/tree/main/scenes/<x>,<y>-<slug>)

## Quality Checklist
- [ ] Changes have been tested locally <!-- tick only after running them -->
- [ ] Documentation has been updated (if required)
- [ ] Performance impact has been considered
- [ ] For SDK features: Test scene is included (link it once it exists)
````

Open with `gh pr create --repo decentraland/unity-explorer --base dev --title "feat: sdk | <thing>" --body-file pr-unity.md`; the repo's `unity-explorer/.claude/skills/github-workflow/SKILL.md` refuses a PR with empty template sections.

## bevy-explorer

Title: an imperative sentence (`Add <field> to <Message>`), optional `fix(scope):` prefix; branch `feat/<slug>`; base `main`. Prose body, no template; always name the protocol PR and which protocol branch the vendored proto now matches.

````markdown
## Problem

<What scenes cannot do, or what is wrong today, in the engine's terms. Cite the issue or the parity gap.>

## Fix

Follow decentraland/protocol#<N>: <field-by-field behaviour in one paragraph, including the default and the unset case>. <Registration or system touched, in words.>

Vendored proto updated to match <`main` | `experimental-bevy`> (`crates/dcl_component/src/proto/decentraland/sdk/components/<file>.proto`). <What is untouched: "The <other path> is untouched.">

Verification (to run before opening; write what was observed, not what is expected): `<native | wasm>` build with the test scene, <one sentence per case once observed>. Test scene: <https://github.com/decentraland/sdk7-test-scenes/tree/main/scenes/<x>,<y>-<slug> | scene repo url>. Console check without an SDK build: `/set_component <entity> <PascalName> <json>` then `/inspect_component`. SDK: decentraland/js-sdk-toolchain#<N>. Unity: decentraland/unity-explorer#<N>. Godot: decentraland/godot-explorer#<N>.
````

Open with `gh pr create --repo decentraland/bevy-explorer --base main --title "<Imperative sentence>" --body-file pr-bevy.md`.

## godot-explorer

Title `feat: <summary>`; branch `feat/<slug>`; base `main`. Shape fixed by `REVIEW.md` §4 and `godot-explorer/.claude/skills/pr-description/SKILL.md` §2.1; every Expected/Regression line is a checkbox, deeplinks are `https://mobile.dclexplorer.com/open?...`, no tables.

````markdown
## What
<What is different after this merges for the creator or player. 1-3 sentences, plain language, at most two identifiers.>

## Why
<The request, the parity gap (name the Unity reference PR), the protocol PR: decentraland/protocol#<N>. 1-3 sentences. What it deliberately does NOT do.>

- [ ] Heads-up to post in #ext-foundation before merge — <what it changes for the SDK or another team> <!-- only when another team is affected; change to "Heads-up posted" after posting -->

Closes #<issue>

## Details
<details>
<summary>Expand</summary>

- `src/install_dependency.rs`: `PROTOCOL_FIXED_VERSION_URL` bumped to <tarball | npm url>; <struct literals fixed with `..Default::default()`>.
- `lib/src/scene_runner/components/<name>.rs`: <what it reads and hands to GDScript>.
- `godot/src/decentraland_components/<file>.gd`: <what it does on screen>.
- [ ] To verify before opening: `cd lib && cargo fmt --all && cargo clippy -- -D warnings`; `cargo run -- run --itest`; <device run> (tick each only after it ran).

</details>

## Test plan

**Setup:** on the phone, open [this link](https://mobile.dclexplorer.com/open?realm=sdk7testscenes.dcl.eth&position=<x>,<y>) (`https://mobile.dclexplorer.com/open?realm=sdk7testscenes.dcl.eth&position=<x>,<y>`). <What the scene shows and how to interact.>

**1. <Case name>**
1. Open the link above.
2. Tap **<on-screen control>**.
   - [ ] **Expected:** <observable result QA can mark pass/fail without reading code>.

**2. <Default / unset case>**
1. Open the link above, then <user action>.
   - [ ] **Expected:** <today's behaviour, unchanged>.

**Regression:** <old path that shares code>.
- [ ] **Regression — <what>:** <still behaves as before>.
````

For a pin bump or tooling-only PR replace the Test plan body with `No QA needed — no behavior change`. Open with `gh pr create -R decentraland/godot-explorer --base main --title "feat: <summary>" --body-file pr-godot.md`.

## sdk7-test-scenes

Title `feat: <feature> test scene at <x>,<y>`; branch `feat/<slug>`; base `main`. The scene's `package.json` pins the SDK PR's `@dcl/sdk` and `@dcl/js-runtime` tarballs while the feature is unreleased; say what replaces them before merge.

````markdown
## What this adds

A <feature> test scene at **<x>,<y>** (`scenes/<x>,<y>-<slug>`). It shows <samples or controls> so QA can check <the feature> on every explorer. <Each guided check logs its steps / shows an on-screen instruction.>

## QA: open the scene

**Use the Explorer build from decentraland/unity-explorer#<N>** (godot: decentraland/godot-explorer#<N>; bevy: decentraland/bevy-explorer#<N>). A released client may not support this feature yet.

After the **Deploy scenes/<x>,<y>-<slug>** check succeeds, connect that build with:

```text
--dclenv zone --realm sdk7testscenes.dcl.eth --position <x>,<y>
```

[Jump-in link](https://decentraland.zone/jump/?dclenv=zone&realm=sdk7testscenes.dcl.eth&position=<x>,<y>). If using MetaMask, use SEPOLIA.

## QA: what to check

| Control | Expected result |
| --- | --- |
| **<button or action>** | <what QA sees> |
| **<unset / default case>** | <today's behaviour> |
| Leave and re-enter the scene | still works; for failures, report the control and a screenshot |

## Validation and dependencies

- Passed: `npm install`, `npm run build`, `npx tsc --noEmit`, root `npm run check-parcels` (`✅ No collisions found`), and `git diff --check`.
- SDK pinned to the decentraland/js-sdk-toolchain#<N> tarballs; protocol decentraland/protocol#<N>. Replace this temporary bridge with a published SDK before merging.
- Merge the protocol/Explorer feature before this scene.
````

Open with `gh pr create --repo decentraland/sdk7-test-scenes --base main --title "feat: <feature> test scene at <x>,<y>" --body-file pr-test-scene.md`.

## docs

Title `docs: <Feature> (<Components>)`; branch reuses the protocol slug; base `main`; open as a draft and keep it draft until an `@dcl/sdk` release exposes the feature.

````markdown
Adds a **<Page title>** page under <Section> for <the feature>:

- `<Component>`: <one line a creator understands>.
- `<Component or field>`: <one line>.

Draft until the <components | field> ship in an `@dcl/sdk` release. Sources: decentraland/protocol#<N>, decentraland/js-sdk-toolchain#<N>, decentraland/unity-explorer#<N> (<pending>), test scene `<x>,<y>-<slug>` in sdk7-test-scenes.

Before merge: replace "an `@dcl/sdk` release newer than <current>" in the version hint with the actual release version.
````

Open with `gh pr create --repo decentraland/docs --base main --draft --title "docs: <Feature> (<Components>)" --body-file pr-docs.md`; the page goes in `creator/sdk7/<area>/<page>.md`, the nav entry in the `SUMMARY.md` that lists its sibling pages (#228 edited the root one; `creator/.gitbook.yaml` names `creator/SUMMARY.md`).

## adr

Title `feat: ADR-<NNN> <title>` (or `ADR-<NNN>: <title>`); branch `feat/adr-<NNN>-<slug>`; base `main`; the ADR file is `content/ADR-<NNN>-<slug>.md` with `status: Draft`.

````markdown
## Summary

Proposes <the protocol change in one sentence: fields, component, ids>. <How a scene opts in or reads it.>

## Why

<The gap, with the measurement when there is one, and why the existing components cannot express it.>

## Contents

- Problem statement; protocol fields, defaults, and why they are opt-in
- Renderer behaviour bounds all three explorers can meet; alternatives considered; backwards compatibility

Status: Draft. Numbering: `main` reaches <M> and open PRs use <M+1..>, so <NNN> is the next free number<; open PRs out of sequence: <list>>.

## Related

- Protocol change: https://github.com/decentraland/protocol/pull/<N>
- SDK change: https://github.com/decentraland/js-sdk-toolchain/pull/<N>
- Unity explorer change: https://github.com/decentraland/unity-explorer/pull/<N> (bevy / godot: https://github.com/decentraland/bevy-explorer/pull/<N> · https://github.com/decentraland/godot-explorer/pull/<N>)

## Related pull requests

- Test scene: https://github.com/decentraland/sdk7-test-scenes/pull/<N> · SDK skills: https://github.com/decentraland/sdk-skills/pull/<N>
````

Open with `gh pr create --repo decentraland/adr --base main --title "feat: ADR-<NNN> <title>" --body-file pr-adr.md`; `cloudflare-workers-and-pages[bot]` then posts the preview to link from the protocol PR.

## Last verified

2026-10-10 against js-sdk-toolchain origin/main `60e3717` (jest 30, `make update-protocol`, `GROWN_ONLY_COMPONENTS`, `check-local-deps`), unity-explorer origin/dev `41a9e92` (`.github/PULL_REQUEST_TEMPLATE.md`, `scripts/package.json`), bevy-explorer origin/main `ad56994` (`/set_component`, `/inspect_component`, vendored proto path), godot-explorer origin/main `cada2d9` (`REVIEW.md` §4, pr-description skill, `PROTOCOL_FIXED_VERSION_URL`), sdk7-test-scenes origin/main `06b52ff` (`deploy-worlds.yml`, `check-parcels`), docs origin/main `9729496`, adr origin/main `3fce505`; precedent PRs #1511, #1600, #9902, #1158, #3031, #100, #228, #324 read with `gh pr view`.
