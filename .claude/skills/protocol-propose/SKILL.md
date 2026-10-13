---
name: protocol-propose
description: Writes phases 1-2 (need, design, prior art, numbering preview) of a Decentraland protocol proposal bundle, or the one-page draft for a small feature. Invoke with /protocol-propose <idea or proposals/<slug>>; the protocol-feature skill routes here automatically.
argument-hint: "<idea | proposals/<slug>> [--size small|medium|large] [--out <dir>]"
disable-model-invocation: true
---

# Phase 1-2: need and design

Turn an idea into a shape the three engines can agree on. The output is `## 1. Need` and `## 2. Design` of `proposal.md` (template: `.claude/skills/protocol-feature/assets/proposal-template.md`), with `status: designed` and Gate log rows 1 and 2 `passed`. On the small track the two sections may merge into one page.

Paths below are relative to the protocol repo root. Read `.claude/skills/protocol-feature/references/repos/protocol.md` once before writing a shape.

## 1. Entry

- Bundle and mode come from the router's sentence or from the `/protocol-propose` arguments. If the bundle does not exist, create it from the template (slug = kebab-case title; `owner` from `gh api user --jq .login`; `policy:` block from `.claude/skills/protocol-feature/references/policy.md`).
- `bash .claude/skills/protocol-feature/scripts/proposal-gate.sh <proposal.md> 1` must print `OK`.
- Do not interrogate the user. Write the best need and design you can from the request and the repos, mark unknowns as open questions, and stop to show the result once (after section 2).

## 2. Need (section 1)

Write it in creator terms: what a scene cannot express today, who asked (issue, thread, scene) or what evidence exists, the workaround and why it is not enough, and non-goals. Fill "today's behaviour per engine" from code or docs you actually read, naming the source, and mark the rest `unverified`; phase 3 verifies it. Quote the text that documents current behaviour when it exists (docs `creator/sdk7/...` on `origin/main` of decentraland/docs; sdk-skills `*/SKILL.md` via `gh api repos/decentraland/sdk-skills/contents/<skill>/SKILL.md`) because that text becomes a follow-up when behaviour changes.

## 3. Prior art (part of section 2)

Search in this order and record every hit with a path, or write "none found" per source:

1. `git grep -n -i '<keyword>' origin/main -- proto` and the same on `origin/experimental-bevy`, `origin/protocol-squad` (bevy-only features and numbers live there).
2. `gh pr list --repo decentraland/protocol --state open --limit 100 --json number,title,headRefName` and `gh pr view <n> --repo decentraland/protocol` for anything related (an open PR can already claim the id, the field number or the idea).
3. ADRs: `git grep -n -i '<keyword>' origin/main -- content` in the adr clone (ADR-245 player components, ADR-215 animation defaults, ADR-214 pointer events are the usual neighbours).
4. docs and sdk-skills text (see section 2).
5. bevy's vendored tree `crates/dcl_component/src/proto/` and engine issues (`gh issue list --repo decentraland/<engine> --search '<keyword>'`).

## 4. Design (section 2)

- **Change**: kind, message or service, file. New component: `proto/decentraland/sdk/components/<snake>.proto`, root message `PB` + PascalCase(file), one `option (common.ecs_component_id) = N;` line, an `import public` line in `public/sdk-components.proto`. Shared enums or sub-messages go under `sdk/components/common/`, never directly in `sdk/components/` (every file there is treated as a component by the SDK and godot codegen).
- **Shape**: every new field `optional`, with a trailing comment giving meaning, units and `(default: X)`, where X reproduces today's behaviour. Proto3 `bool` cannot express "unset", so name flags so that `false` is today (`keep_emote_on_move`, not `animate_locomotion` defaulting to true). Enum zero values are the backward-compatible meaning and carry the enum's prefix (`ES_`, `AMT_`, `BM_`). Entity references are `uint32`. Extension points are `oneof` blocks starting at field 10.
- **Semantics**: each value, unset == today, interaction with existing fields (for AvatarShape: `expression_trigger_id`, tweens, AvatarShape on the PLAYER entity), who writes the component (scene vs explorer), LWW vs grow-only (grow-only needs a `timestamp` field and entries in four consumer lists), scene-local vs relayed over comms (a relayed behaviour needs an rfc4 / Pulse section and is `size: large`).
- **Alternatives**: at least two with the reason each loses; always include "engine-side change, no protocol change" and "do nothing".
- **Compatibility**: additive? any rename, retype or `optional` added to an existing field? (all three are breaking under buf WIRE_JSON; see `.claude/skills/protocol-feature/references/repos/protocol.md`). Which numbers are skipped and why.
- **Numbering preview**: run and paste, date-stamped (final numbers are set in phase 4):
  - fields: `bash .claude/skills/protocol-feature/scripts/field-numbers.sh <PBMessage>`
  - new component: `bash .claude/skills/protocol-feature/scripts/next-component-id.sh`
- **ADR**: per `policy.adr_by_size`: none | amend ADR-NNN in place | new ADR (SDK-COMPONENT template for components, ADR-318 shape otherwise). Record the decision even when it is "none".
- **Open questions**: anything phase 3 or the user must settle. Later phases mark a question resolved by appending `-> resolved in section N` rather than deleting or rewriting it, so sections 1-2 stay the record of what was asked.

## 5. Exit

- Sections 1 and 2 complete; frontmatter `status: designed`, `phase: 3`, `updated` today.
- Gate log rows `1 need` and `2 design` set to `passed` with today's date and `model`; Decision log rows for the shape, the default, the ADR decision and the policy values quoted.
- `bash .claude/skills/protocol-feature/scripts/proposal-gate.sh <proposal.md> 3` prints `OK`.
- Show section 2 to the user and print the next command: `/protocol-tech-check proposals/<slug>` (or continue in the same session on the small track and in `--draft`).

## Common mistakes

- A flag whose `false` is not today's behaviour: every deployed scene that omits it changes behaviour the day an engine ships it.
- A non-`optional` scalar on a scene-written message: the generated TypeScript type gets a required property and existing scenes stop type-checking.
- A shared enum file placed directly in `sdk/components/`: SDK and godot codegen expect every file there to carry an id and break.
- A comment line containing both `option` and `ecs_component_id`: the SDK and godot id parsers read lines, not syntax.
- Reusing a number that `main` skipped for `experimental-bevy` or `protocol-squad` (`PBAvatarShape` 13, `PBUiText` 7-8, `PBUiInput` 14-15): the wire formats diverge when the branches converge.
- Proposing a relayed behaviour (something other players must see) without a comms section: AvatarShape state is scene-local, player state is not.
