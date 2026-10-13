# ADR repo
How `decentraland/adr` is laid out, validated, numbered and reviewed, so a protocol feature can ship its ADR (new or amended) without tripping the build or colliding with another author's number.

## Contents

- [Read origin/main, not the working tree](#read-originmain-not-the-working-tree)
- [Files, slugs and templates](#files-slugs-and-templates)
- [Build validator](#build-validator)
- [Numbering: the rule and the practice](#numbering-the-rule-and-the-practice)
- [Lifecycle: Draft, Living, in-place edits](#lifecycle-draft-living-in-place-edits)
- [Shapes to copy: ADR-318 and ADR-257](#shapes-to-copy-adr-318-and-adr-257)
- [ADRs a protocol feature will cite](#adrs-a-protocol-feature-will-cite)
- [Linking conventions](#linking-conventions)
- [Git, PR and review conventions](#git-pr-and-review-conventions)
- [Commands](#commands)
- [Last verified](#last-verified)

## Read origin/main, not the working tree

The local clone's `main` sits behind `origin/main` (five commits today: ADR-291..296 explorer docs, ADR-316, a Node bump, plus a batch of `Deprecated` flips on old ADRs), and an untracked `CLAUDE.md` lives there that no other contributor has. Fetch first and read through git so a number or a citation is never chosen from stale content:

```bash
git fetch origin
git show origin/main:content/ADR-215-gltfcomponent-sdk-component.md
git ls-tree --name-only origin/main content/ | grep -oE 'ADR-[0-9]+' | sed 's/ADR-//' | sort -n | tail -1   # 316 today
```

Open proposals live on remote branches, not on main, so a feature's prior art also needs `gh pr list --repo decentraland/adr --state open` and `git show origin/<headRefName>:content/<file>`.

## Files, slugs and templates

One flat markdown file per ADR at `content/ADR-<n>-<slug>.md`. The site slug `/adr/ADR-<n>` comes from the `adr:` frontmatter (`.site-generator/index.js`, `page.slug`), not from the filename, which is why the two odd names on main (`content/ADR-125.md`, `content/ADR-102-decentraland-protocol-for-explorers copy.md`) still render. Images go under `public/resources/ADR-<n>/`.

Two templates, both with a trailing `slug:` line you must delete:

- `content/.TEMPLATE.md`, generic. Sections: `## Abstract`, `## Context, Reach & Prioritization`, `## Solution Space Exploration`, `## Specification`, `## RFC 2119 and RFC 8174`. Its frontmatter, verbatim:

```yaml
---
layout: adr
adr: 0 # replace this number for the PR or ISSUE number
title: Title of the ADR
date: 2020-02-20
status: Idea, Draft # pick one of these
type: Standards Track | Meta | RFC # pick one of these
spdx-license: CC0-1.0
authors:
  - menduz # this is your github username
# remove the following line! it exists to render the template nicely
slug: /adr/TEMPLATE
---
```

  Use `status: Draft` (`Idea` fails the build, see below) and one literal type. `layout: adr` is harmless but the generator sets it anyway.

- `content/.SDK-COMPONENT-TEMPLATE.md`, for a new component (`type: Standards Track` preset). Sections: `## Component description`, `## Serialization`, `## Semantics` (with `### Example`), `## RFC 2119 and RFC 8174`. The Serialization block is a yaml table followed by a fully commented protobuf message; existing component ADRs use `CRDT_TYPE: LastWriteWin-Element-Set` for scene-written components and `GrowOnly-Value-Set` for engine-written result components (ADR-214 lists both for PointerEvents 1062 / PointerEventsResult 1063):

```yaml
parameters:
  COMPONENT_ID: 1
  COMPONENT_NAME: core::Billboard
  CRDT_TYPE: LastWriteWin-Element-Set
```

ADR-1 (`content/ADR-1-adr-process.md`) fixes the preamble order as `adr, title, description, authors, discussion, status, last-call-deadline, type, date, withdrawal-reason, deprecated-reason`, caps `title` at 44 characters with no ADR number in it, and asks for the RFC 2119 clause at the start of `## Specification`; the templates put it in a closing section instead, and both forms are accepted. `description:` and `discussion:` are effectively unused on main.

## Build validator

`.site-generator/index.js:checkAdrStatus` is the only gate the CI enforces (`make build`), so match it exactly:

```js
const validStatuses = new Set(["Draft", "Review", "LastCall", "Final", "Stagnant", "Withdrawn", "Living", "Deprecated"])
const validTypes = new Set(["RFC", "Standards Track", "Meta"])
```

- `Idea` is in ADR-1's lifecycle but not in the set, so the template's `status: Idea, Draft` must become `Draft`.
- `LastCall` has no space, although ADR-1's prose writes `Last Call`; ADR-1 also lists a type `ADR` that does not exist.
- `spdx-license` must equal `CC0-1.0`; `Deprecated` requires a `deprecated-reason`; a page with an `rfc:` key throws `RFC are deprecated, please upgrade`.

## Numbering: the rule and the practice

ADR-1 says, verbatim: "The initial issue number or the pull request number that adds the file to the decentraland/adr **MUST** be used as the final ADR number", with editors able to override ("generally the PR number, but the decision is with the editors"). In practice authors take the next free number in sequence and justify it in the PR body, because the PR number is only known after the branch is pushed. PR #324 did exactly that for ADR-318: "Numbering: `main` reaches 316 and open PRs use 317, so 318 is the next free number; a few open PRs sit out of sequence at 323, 400 and 401." Note #325 then used its own PR number (ADR-325), so both conventions coexist.

Collisions are common because of this, so check both main and open PR heads before picking: ADR-253 (two unmerged drafts, `light-sources` and `exposing-gltf-internals`), ADR-258 (`trigger-areas` vs `ui-scaling`), ADR-280 (`binaries-creator-hub` on main vs `avatar-locomotion-control` on PR #305), ADR-285 (`updated-friend-request` on main vs `continuous-tweens`), ADR-286 (two branches), ADR-291 and ADR-292 (explorer docs on main vs `profile-names-validation` #311 and `customize-nametag-color` #315).

```bash
gh pr list --repo decentraland/adr --state open --limit 100 --json number,headRefName,title
git ls-tree --name-only origin/<headRefName> content/ | grep -oE 'ADR-[0-9]+' | sort -u   # per open PR
```

Today main tops out at 316 and open PRs claim 317, 318, 323, 325, 400 and 401, so the next in-sequence number is 319. Recompute at run time, name the number and its rationale in the PR body, and follow `ADR_NUMBER_RULE` in `.claude/skills/protocol-feature/references/policy.md`.

## Lifecycle: Draft, Living, in-place edits

- SDK feature ADRs merge as `Draft` and are flipped to `Living` once engines adopt them, by a one-line PR (ADR-255: `#288`, `status: Draft` -> `status: Living`) or in bulk (`#274` flipped ADR-133/144/200/214/215/219/245 from Draft or Review to Living).
- Small semantic changes to an existing component edit its Living ADR in place rather than opening a new ADR. Commit `3acb270` (`fix: change the default animation behaviour (#262)`) rewrote ADR-215 `### Initial state` from "All animations in a glTF instance MUST be stopped as the default state." to "...when a Animator is present in the entity, so the Animator can manually control the state. If Animator is not present, only the first animation MUST be played in loop state." Other in-place examples: ADR-245 `#261`, ADR-219 `#313`, ADR-133 `#310` (new `Explorers overriding of SDK Runtime features` section).
- Genuinely new behaviour or new fields get their own ADR (ADR-257, ADR-318), yet many shipped components have none at all: AvatarShape 1080, AvatarLocomotionSettings 1211, TriggerArea 1060, LightSource 1079, SkyboxTime 1210, InputModifier 1078, VideoPlayer 1043, AudioEvent 1105 and others appear in no ADR on `origin/main`. Treat the ADR as written alongside the protocol PR per `ADR_BY_SIZE` in `references/policy.md`, not as a hard gate, and link it from the `.proto` comment.
- `Living` means continually updated; `Final` allows only errata; `Stagnant` is six months idle in Draft/Review/LastCall; `Withdrawn` retires the number for good.

## Shapes to copy: ADR-318 and ADR-257

**ADR-318** (`content/ADR-318-audio-playback-position-reports.md` on branch `feat/adr-318-audio-playback-position`, PR #324, `type: RFC`, `status: Draft`) is the modern model for a small protocol feature that adds fields to existing components. Its headings:

```
# Abstract
## Context and problem statement
## Specification
### Protocol                 # protobuf diff naming component ids: "Three optional fields are added to `PBAudioEvent` (component id 1105)"
### Why the reports are opt-in
### Why a tick number
### Accuracy
### Renderer behaviour       # MUST-style bullets with explicit bounds, e.g. at most one report per tick, at least one per second
### Client libraries
### Scene usage
## Alternatives considered
## Backwards compatibility   # "All new fields are optional ... No component id changes."
## Implementation            # one bullet per repo: protocol, js-sdk-toolchain, unity-explorer, bevy-explorer + godot-explorer "pending"
## References
```

Reviewer guidance from #324 (mikhail-dcl requested changes, then approved): keep the specification protocol-only, so SDK code and scene usage move to the js-sdk-toolchain PR; and bound renderer behaviour numerically because, as the author's follow-up comment on the PR put it, "a survey of the three explorers found they already disagree on video", so every explorer can comply.

**ADR-257** (`content/ADR-257-avatar-rotation.md`, `Draft`, `RFC`) is the smallest shape accepted on main, one optional field on `movePlayerTo`: `# Abstract`, `# Context`, `# Proposal`, `# Conclusion`. Use it as the floor for a single-field addition when policy asks for an ADR at all.

## ADRs a protocol feature will cite

All Living on `origin/main` unless noted; cite them as `[ADR-N](/adr/ADR-N)`.

| ADR | File | Why it matters to a feature |
|---|---|---|
| 117 | `content/ADR-117-CRDT-protocol.md` | CRDT foundation: LWW-element-set per entity+component, grow-only sets for results |
| 123 | `content/ADR-123-schema-and-serialization-of-sdk-components.md` | Components are Protocol Buffers; "the source of truth for the components live in the decentraland/protocol repository"; fields are naturally optional, which is what makes additive evolution safe |
| 165 | `content/ADR-165-resolving-component-numbers.md` | Component numbers, `type: RFC`, says "The document is still not conclusive"; core ids < 2048 are actually allocated by `ecs_component_id` in the protocol repo |
| 148 | `content/ADR-148-processing-scene-messages.md` | Scene <-> renderer tick; cite for "when is this applied" and for `tick_number` in results |
| 214 | `content/ADR-214-pointer-events-sdk-component.md` | The engine-written result pattern (PointerEvents 1062 LWW + PointerEventsResult 1063 GrowOnly-Value-Set) |
| 215 | `content/ADR-215-gltfcomponent-sdk-component.md` | GltfContainer and the Animator/default-animation semantics; the in-place edit precedent |
| 219 | `content/ADR-219-static-entities.md` | RootEntity 0, PlayerEntity 1, CameraEntity 2 and which components the engine writes on them |
| 245 | `content/ADR-245-player-components.md` | Player components incl. `PBAvatarEmoteCommand`. Caveat: its bullet at ~65 reads "PBPlayerIdentityData a GOS component", a copy-paste error; PlayerIdentityData is LWW and AvatarEmoteCommand is the grow-only one. Do not propagate the label |
| 133 | `content/ADR-133-scene-runtime.md` | Scene runtime; the `#310` section on explorers overriding SDK runtime features (globalThis flag + SDK-version gating) |
| 104 | `content/ADR-104-comms-protocol.md` | `type: RFC`, `redirect_from: /rfc/RFC-4`. This is the RFC-4 that `proto/decentraland/kernel/comms/rfc4/comms.proto` names in its header ("This file maps to the definition in https://rfc.decentraland.org/rfc/RFC-4 / It is mandatory to also update that RFC when modifying this file"), so any rfc4 change edits ADR-104 in place |
| 293 | `content/ADR-293-explorer-emotes-system.md` | `Draft`, Unity-specific explorer architecture, not an SDK contract; do not use it as evidence for bevy or godot |

Nothing on main documents AvatarShape 1080, so an avatar-shape feature either gets a new ADR in the ADR-257/318 shape or a section in a related Living ADR; ADR-245 covers player entities, not NPC AvatarShape.

## Linking conventions

- Inside an ADR, reference others as `ADR-N` with an absolute rendered link, ADR-1 verbatim: "Each ADR that is referenced in an ADR **MUST** be accompanied by an absolute markdown link to the absolute rendered path i.e. `/adr/ADR-1`". Images: `/resources/ADR-N/image.png`.
- ADR-1 says external links "SHOULD NOT be included", yet recent accepted ADRs (ADR-133 `#310`, ADR-318, ADR-292) link implementation PRs and commits; reviewers accept pinned commit links over branch links.
- Protos link back to the ADR in a top-of-message comment. Merged ADR: `// https://adr.decentraland.org/adr/ADR-198` (`proto/decentraland/sdk/components/billboard.proto`) or `// The PBRaycast component and PBRaycastResult are defined in https://adr.decentraland.org/adr/ADR-200` (`raycast.proto`). Unmerged ADR: pin a blob URL so the link survives renumbering, as `trigger_area.proto` does:

```
// ADR: https://github.com/decentraland/adr/blob/2b30a5e2b4f359a7c22a68fb827db282f6e5f887/content/ADR-258-trigger-areas.md
```

  Proto-side placement rules are in `.claude/skills/protocol-feature/references/repos/protocol.md`.

## Git, PR and review conventions

- Branch per ADR-6 (`content/ADR-6-git-style-guide.md`), regex `(chore|docs|feat|fix|refactor|style|test)/[0-9a-zA-Z_-]+`; recent ADR branches are `feat/adr-318-audio-playback-position`, `feat/adr-292-customize-nametag-color`, `feat/adr-partial-deployments`, so use `feat/adr-NNN-<slug>` for a new ADR and `docs/adr-NNN-<slug>` or `fix/...` for an in-place edit.
- Titles are semantic commits that name the number; main shows `feat: ADR-289 Explorer client scenes signed fetch (#308)`, `docs: ADR-133 explorers SDK runtime logic override (#310)`, `fix: Update ADR287 emote structure (#306)`, and open PRs also use the bare `ADR-318: Audio playback position reports`. Prefer `feat: ADR-NNN <title>`.
- Body, from #324: `## Summary`, `## Why`, `## Contents`, `## Notes on two decisions` (the design calls reviewers may push back on), a `Status: Draft. Numbering: ...` line, `## Related` (protocol, SDK, unity PRs), `## Related pull requests` (test scene, sdk-skills). The skeleton to reuse is in `.claude/skills/protocol-feature/references/pr-styles.md`.
- `.github/CODEOWNERS` routes `content/*` and `public/*` to `@decentraland/adr-editors`, so that team is auto-requested; approvals in practice come from engine and SDK leads (e.g. #313 `kuruk-mm`, `aleortega`; #310 `gonpombo8`, `mikhail-dcl`; #279 `aixaCode`, `leanmendoza`), and the author merges their own PR after one or two approvals (#316, #313, #310, #309, #308, #288, #279 were all merged by their author).
- A `cloudflare-workers-and-pages` bot comments a Pages preview URL on every PR; use it to eyeball rendering instead of guessing.
- CI is `.github/workflows/checks.yml`: `make build` on every push (Node 24 since `#321`; the step is still named "Use Node.js 16.x"). Lint is `.pre-commit-config.yaml`: `codespell` v2.2.2 plus `markdownlint`/`markdownlint-fix` v0.33.0 on files matching `content/ADR-[0-9]+-.*\.md`.

## Commands

Run inside the adr clone:

```bash
make build          # what CI runs: npx static-site-renderer@^2.1.0 --srcDir . --outDir out --publicUrl https://adr.decentraland.org
make build-draft    # IS_DRAFT=true, so Draft pages are included
make run            # build-draft + npx http-server -p 8080 out, opens http://localhost:8080
pre-commit run --all-files
```

`make build` is the only check that fails a PR, so run it before pushing; the pre-commit hooks are a courtesy the editors expect but CI does not enforce.

## Last verified

2026-10-10 against `decentraland/adr` `origin/main` at `3fce5057436512cb4d98928d588278320fc37851` (`chore: update Node.js to 24 (#321)`), branch `origin/feat/adr-318-audio-playback-position` for ADR-318, and `decentraland/protocol` `origin/main` at `d7ddc10` for the proto comments.
