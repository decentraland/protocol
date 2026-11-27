# Policy parameters

The team decisions the phase skills apply. Each parameter has a value in force; quote the value you used in the proposal's Decision log so old bundles stay auditable after a policy edit.

## Contents
- [How to read this file](#how-to-read-this-file)
- [Parameters](#parameters)
- [Changing a value](#changing-a-value)

## How to read this file

Every phase skill reads the `Value` column at run time and copies the values into the proposal frontmatter `policy:` block when the bundle is created. A phase skill never hardcodes a policy; when a parameter and a skill body disagree, this file wins.

## Parameters

| Parameter | Value | Allowed | Why this value |
|---|---|---|---|
| `MERGE_GATE` | `all-accounted` | `unity` (README rule, #474) · `unity+bevy` (#489) · `all-accounted` · `all` | Before the protocol PR merges, unity-explorer, bevy-explorer and godot-explorer each have a linked implementation PR **or** a filed parity-gap issue, and the js-sdk-toolchain PR exists. Deployed scenes are immutable, so a field nobody implements is a permanent promise. `all` (three implementation PRs that build) is used for `size: large`. |
| `ADR_BY_SIZE` | `small: none · medium: alongside · large: before` | `none` · `large-only` · `medium: alongside, large: before` · `all` | Small additive fields ship without an ADR today (#489, #470). A new component or RPC gets a Draft ADR from `content/.SDK-COMPONENT-TEMPLATE.md` written alongside the protocol PR (ADR-318 shape). Comms, new API files, breaking or semantics changes need the ADR before definition so three engines can agree on bounds first. |
| `PROPOSAL_DIR` | `proposals/` | any repo-relative dir · `.claude/proposals/` · untracked | Bundles are tracked in decentraland/protocol next to the schema they change. Simulations stay local unless kept as examples; a real feature commits its bundle in the protocol PR. `--out <dir>` or `PROTOCOL_FEATURE_OUT` overrides it per run (evals use this). |
| `RESERVE_BEVY_NUMBERS` | `comment` | `none` (PR-body note only, #489) · `comment` · `reserved` | Numbers used on `experimental-bevy` / `protocol-squad` are recorded as a comment on the next free line of the message (`// 13 is force_render on experimental-bevy`) so the next author sees the skip without reading PR bodies, and without `reserved` lines that buf treats as permanent. |
| `ALLOW_EXPERIMENTAL_BEVY_FIRST` | `no` | `no` · `yes` | Features target `main`. Prior-art and collision checks always include `origin/experimental-bevy`; when a maintainer lands on that branch first anyway, the twin PRs (#487 / #489) must carry identical numbers, and the define skill says so. |
| `ROLLOUT_INCLUDES` | `test-scene, docs, sdk-skills` | subset of `test-scene, docs, sdk-skills, scene-explorer-tests` | A sdk7-test-scenes scene, a decentraland/docs page (draft until an `@dcl/sdk` release) and a decentraland/sdk-skills update are checklist rows on every proposal; each may be marked `N/A` with a reason. `scene-explorer-tests` is frozen (2024) and never required. |
| `TEST_SCENE_PIN` | `published` | `published` · `tarball-allowed` | A test scene repins to a published `@dcl/sdk` (or `@next`) before its PR merges (#100 guidance), instead of leaving a feature-branch tarball in `package.json` (the 4,24 precedent). |
| `ADR_NUMBER_RULE` | `next-free` | `next-free` · `pr-number` | ADR-1 says "use the PR number", practice is max(origin/main, open PRs) + 1 with the rationale in the PR body (#324 -> ADR-318). Collisions are common either way; always state the rationale. |
| `REVIEWER_HANDLES` | (empty) | GitHub handles per repo | Not encoded until the team confirms them. The review skill names the repo's CODEOWNERS instead. |
| `V1_SCOPE` | `components, fields, enums, restricted-actions` | add `comms` | SDK components and kernel-API restricted actions are mapped end to end in every engine. Comms (rfc4 / Pulse) get a technology check only; their implementation briefs are labelled `unmapped`. |
| `EXECUTE_DELEGATION` | `subagent-per-repo; unity architect for medium+` | `inline` · `subagent-per-repo` | In execute mode each repo's brief runs in its own subagent; medium and large Unity work hands off to unity-explorer's `dcl-sdk-feature-architect` agent. Long gates (bevy `cargo test`, SDK `make build`) are allowed with a printed time estimate. |

## Changing a value

Edit the `Value` cell, add one line to the git history explaining why, and leave existing bundles alone: their Decision logs quote the value they used. `scripts/proposal-gate.sh` validates a bundle against the values in force only for gates that have not passed yet.
