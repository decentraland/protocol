# PR body house styles per repo

Title, branch, base, body skeleton and reviewer bots for every repo a protocol feature touches, so each PR reads like the ones that repo already merges.

## Contents

- [Global rules](#global-rules)
- [protocol](#protocol)
- [js-sdk-toolchain](#js-sdk-toolchain)
- [unity-explorer](#unity-explorer)
- [bevy-explorer](#bevy-explorer)
- [godot-explorer](#godot-explorer)
- [sdk7-test-scenes](#sdk7-test-scenes)
- [docs](#docs)
- [adr](#adr)
- [sdk-skills](#sdk-skills)
- [Bot vocabulary cheat sheet](#bot-vocabulary-cheat-sheet)
- [Last verified](#last-verified)

Fill-in skeletons live in `.claude/skills/protocol-feature/assets/protocol-pr-body.md` and `.claude/skills/protocol-feature/assets/engine-pr-bodies.md`; this file is the rulebook the review phase audits against.

## Global rules

- A body drafted in plan mode never claims a build, test, device run, measurement or Slack heads-up that did not happen in this session: verification items stay `- [ ]` with "to run", heads-ups say "to post". Reviewers in every repo treat an invented verification as a rewrite request, and QA plans its work from those lines.
- Write the body to the bundle (`pr-<repo>.md`) and print it in full before any `gh pr create`, because every repo treats an unread AI draft as a rewrite request (godot `godot-explorer/.claude/skills/pr-description/SKILL.md` §1 says a draft "is AG-2 until the author has read it").
- Lead with what changes for the player, creator or scene, in plain language. Do not narrate the diff: js-sdk-toolchain `REVIEW.md` §2 rejects a description that "reads as generated filler", godot `REVIEW.md` §4 holds a PR that "restates the diff file by file".
- State what the change does not do when a reader could assume otherwise. Observed: protocol #499 "This is voice-only and separate from the general audio effects proposed in #377", bevy #1158 "The PROXIMITY interaction path is untouched", godot #3031 "Not included: `TweenSequence` is not implemented".
- Link every sibling PR by `owner/repo#N` so reviewers can follow the feature across repos: protocol #489 `## Implementation`, protocol #495 `## Related PRs` (unity-explorer, js-sdk-toolchain, sdk7-test-scenes, docs, sdk-skills), unity #9902 "Test scene: ... SDK side: ..." paragraph (the one before the `-----------------` rule), SDK #1600 "Protocol source:" line. Write "pending" for a PR that is not open yet and edit it in later (`gh pr edit N --repo <owner/repo> --body-file ...`).
- Give a concrete way to test, in the repo's own idiom (section names differ, see below). "Tested locally" is not a test plan anywhere.
- Say which protocol branch and build a repo was pinned to, since every consumer pins differently (tarball URL, `@next`, vendored copy, `PROTOCOL_FIXED_VERSION_URL`).
- Use the `gh pr create` form each repo documents; pass `--body-file` from the bundle instead of inline heredocs so the printed body and the posted body are the same bytes.
- Trailing "🤖 Generated with [Claude Code](https://claude.com/claude-code)" lines appear on protocol, SDK, bevy and unity PRs; keep or drop per the user, never add it to godot (AG rule) or adr.

## protocol

- Title: conventional, squash-merged so the subject ends `(#N)`. Observed: `feat: AvatarNametag component (id 1221)` (#474), `feat: add font_src to TextShape, UiText, UiDropdown and UiInput` (#489), `feat: add PlayerVoiceState and VoiceChatModifierArea components` (#499), `feat: BadgesService.CheckAwards scene API` (#497). Put the component id in the title for a new component.
- Branch: `feat/<kebab>` (`feat/font-src-main`, `feat/avatar-nametag-main`, `feat/nearby-voice-sdk`). Base `main`. No PR template (`.github/` has only `dependabot.yml` and `workflows/`).
- Body skeleton (merged #489 / #474, open #499):
  1. Lead paragraph: the problem and the one-line change, lowercase and plain ("currently scenes can only pick from the six built-in `font` enum values. adds `font_src` to let a scene name its own face.").
  2. Per-field semantics with defaults and the no-op case: "Unset changes nothing, so existing scenes are unaffected." (#489); who writes it, where it is valid, what is never relayed (#474).
  3. `## Field numbering` when a number is skipped or shared with another branch: "The field numbers match the ones already carried on `experimental-bevy` ... `PBUiText` skips **7-8** and takes `font_src = 9`." (#489).
  4. How to test: "`make buf-lint && make test`; `make list-components-ids` shows 1224 and 1225 unique (1223 is claimed by #495)." (#499). `make list-components-ids` runs `scripts/list-components-ids.sh`; `make check-component-id ID=N` prints `id N is free` or `id N is taken` and scans only the local tree.
  5. `## Implementation` with one link per repo ("Implemented in decentraland/unity-explorer#9829", "SDK and Explorer PRs will link here once open"), or `## Related PRs` (#495) listing unity-explorer, js-sdk-toolchain, sdk7-test-scenes, docs and sdk-skills.
- #497 (a scene API, not a component) uses `## What` / `## Why` / `## How to test` / `## Status` instead; both shapes pass review. #476 (`double total_runtime_f64 = 5`, no `optional`) is still open, cite it as a counter-example rather than precedent.
- CI on the PR: `check_and_build`, `Deployment Notification`, `Validate compatibility with main branch`; `make buf-breaking` runs only on pushes to upstream non-main branches (`.github/workflows/validate.yml`).
- Bots: `github-actions[bot]` posts `# Test this pull request` with `npm install "https://sdk-team-cdn.decentraland.org/@dcl/protocol/branch//dcl-protocol-1.0.0-<runId>.commit-<sha7>.tgz"` (double slash is real, copy it verbatim). `decentraland-bot` posts a PR review titled `## Review: PR #N — <title>` with `### P0 — Blocker`, `### P1 — Should fix before merge`, `### P2 — Minor / Nice-to-have`, then `### API Contract / Backward Compatibility` and `### Security`; it caught the 1221 id collision on #464. Answer each P0/P1 inline before re-requesting.

## js-sdk-toolchain

- Title: Conventional Commits, often scoped: `feat(ecs): add AvatarNametag component` (#1600), `feat: add ExplorerUiEventsResult component and share the ExplorerUi enum` (#1511), `chore: bump @dcl/protocol to <version> (<reason>)`. Branch `feat/<slug>` (`feat/avatar-nametag`). Base `main`. No `Co-Authored-By` lines (`AGENTS.md` "Code conventions").
- Body: `REVIEW.md` §2 (origin/main) requires **What / why** in a short paragraph, **How to test** with steps a reviewer can run, and **Proof** (a test scene or failing-test repro; §3 rejects a bug fix without one). Reviewers cite rules as "REVIEW.md §1".
- Observed sections: lead paragraph; `Depends on decentraland/protocol#455 — **do not merge before it**.`; `## What changes` bullets; `## Before merging` checklist (`- [ ] decentraland/protocol#455 merged`, `- [ ] \`@dcl/protocol\` repinned from the PR tarball to the published version, lockfiles refreshed, snapshots and \`api.md\` regenerated`); `## Verification` with the exact commands (#1511). #1600 uses `## Summary` bullets, `Protocol source: decentraland/protocol#474`, `Renderer implementation: ...`, and a `## Test plan` of ticked `- [x]` commands.
- Say in the body that the pin is a tarball URL while the protocol PR is open, because the `check-local-deps` CI job blocks merge while any packaged dependency is an `http:`/`file:`/`git:` URL.
- Bots: `github-actions[bot]` `# Test this pull request` with `@dcl/sdk` and `@dcl/js-runtime` tarballs under `https://sdk-team-cdn.decentraland.org/@dcl/js-sdk-toolchain/branch/<branch>/...`, an `export SDK_COMMANDS=...; npx $SDK_COMMANDS init` block and `/changerealm https://sdk-team-cdn.decentraland.org/ipfs/<branch>-e2e`; `cloudflare-workers-and-pages[bot]` posts the playground preview. Paste the `@dcl/sdk` and `@dcl/js-runtime` URLs into the test scene's `package.json`.

## unity-explorer

- Base `dev`. Branch off `dev` with `feat/` `fix/` `chore/` `opti/` (`docs/branch-and-pr-standards.md`); sub-prefixes like `feat/sdk-scene/...` are allowed.
- Title `type: description`, lowercase prefix, enforced by `.github/workflows/validate-pr-title.yml` (check `semantic / title-matches-convention`). SDK features: `feat: sdk | scene name tag` (#9829), `feat: sdk teleportTo realm coords support` (#10047), `feat: font_src on TextShape, UiText, UiInput and UiDropdown` (#10118). `feat:` PRs never get auto-approved by the bot; `fix:`/`chore:` can.
- Body follows `.github/PULL_REQUEST_TEMPLATE.md` on `origin/dev`, all three sections filled or QA sends it back:
  1. `## What does this PR change?` — what and why, `Fix #NNNN` to auto-close, "For SDK features: Include or link to a test scene", the protocol PR link ("Protocol: decentraland/protocol#489").
  2. `## Test Instructions` — copy-pasteable, this is what QA runs: `metaforge explorer run XXXX` then the launch args `--dclenv zone --realm sdk7testscenes.dcl.eth --position 84,-6` (or `/goto sdk7testscenes.dcl.eth/84,-6` when already on zone, "MetaMask users: select SEPOLIA"), then a `| Click / do | Expected |` table or numbered `### Test Steps`.
  3. `## Quality Checklist` — keep `- [ ] For SDK features: Test scene is included`.
- `### QA TEST STEPS` is the SDK-team variant seen on #9902, after a `-----------------` rule: "Use the build from this PR to enter the ZONE/SEPOLIA world `sdk7testscenes.dcl.eth` at position `34,20` and confirm ..." plus a link to the scene source under `sdk7-test-scenes/scenes/<x>,<y>-<name>`. Either placement works; QA needs the realm, the position and a pass/fail sentence.
- `unity-explorer/.claude/skills/github-workflow/SKILL.md` on `origin/dev` is the repo's own PR skill: it reads the template first and refuses to create a PR with missing sections; its example is `gh pr create --title "fix: ..." --body "$(cat <<'EOF' ... EOF)"`.
- Review flow (`docs/branch-and-pr-standards.md`): 1 QA + 1 DEV reviewer auto-assigned; Jarvis review through `decentraland-bot` posts `## PR Review: <title>` / `## Jarvis review: ...` with `### STEP 2 — Root-cause check ... PASS` and emits the `Claude Review` commit status; labels `claude-approved`, `no QA needed`, `no review`, `auto-pr` are applied by automation or a maintainer, not by the author; merge gate `Enforce QA and DEV Approvals`; squash and merge with title + bullets + test steps.

## bevy-explorer

- Base `main`. Branch `feat/<slug>` or `fix/<slug>` (`feat/web-fonts`, `feat/max-camera-distance`, `fix/reconnect-presence`). No PR template (`.github/` holds `dependabot.yml` and workflows only); the root `CLAUDE.md` is a repo map and says nothing about PR bodies.
- Title: an imperative sentence, usually without a prefix, squash-merged as `<sentence> (#N)`: `Add font_src to TextShape, UiText, UiInput and UiDropdown` (#1263), `Keep room participants through a reconnect` (#1463); an occasional scope prefix `fix(pointer): max_distance is player distance; add max_camera_distance` (#1158).
- Body: prose, no template. #1158: `## Problem` / `## Fix`, "Vendored proto updated to match.", then "Verified against the wasm build with a test scene: ..." with the exact values. #1263: lead paragraph naming the protocol PR and SDK branch ("(protocol #487, SDK on `experimental-bevy`)"), `### Why ...`, `### Follow-ups`, `Test scene: <repo url>`. #1467/#1463: paragraphs with a bold lead sentence each, then "To see it: ..." reproduction.
- Always say which protocol branch the vendored `crates/dcl_component/src/proto/` copy now matches (main or `experimental-bevy`) and cite the protocol PR; bevy tracks `experimental-bevy`, so a main-only field needs that sentence.
- Bots: none observed on #1467 (no reviews, no bot comments). Main reviewer is the repo owner; CI `Test Scenes` is non-blocking.

## godot-explorer

- Base `main`. Title conventional (`feat:` / `fix:` / `chore:` / `refactor:`): `feat: implement MoveRotateScale tween mode` (#3031). Branch name is free in practice (`feat/hide-nametags-modifier-gonpombo8`, `kuruk-mm/tween-implement-moverotatescale-mode`); use `feat/<slug>`.
- Body is fixed by `REVIEW.md` §4 and `godot-explorer/.claude/skills/pr-description/SKILL.md` §2.1 on `origin/main`: `## What` (1-3 sentences) / `## Why` (1-3 sentences, including what it deliberately does NOT do; optional "Heads-up posted in #ext-foundation" line when the SDK or another team is affected) / `Closes #N` / `## Details` inside `<details><summary>Expand</summary>` / `## Test plan`.
- Test plan rules: QA runs it by hand on phones, so device, build and TestFlight/Firebase setup are assumed; deeplinks as `https://mobile.dclexplorer.com/open?realm=<realm>&position=<x,y>` (never `decentraland://`); first step "Open the link above" or "Open the app"; numbered Steps with on-screen names; every Expected or Regression line is a box, `- [ ] **Expected:** ...` / `- [ ] **Regression — <what>:** ...`; no bare `- [ ]`, no tables; `No QA needed — no behavior change` for non-behavioural PRs. What the author verified goes in Details as `- [x]` items.
- Open with `gh pr create -R decentraland/godot-explorer --base main --title "<type>: <summary>" --body-file <scratchpad>/pr-body.md`; rewrite with `gh pr edit <N> -R decentraland/godot-explorer --body-file ...`.
- Review: CODEOWNERS `* @decentraland/rgl-mobile-team`; `REVIEW.md` Tier 1 includes "Decentraland SDK contract breaks ... protocol field numbers"; severity labels `🔴` blocker / `🟡` suggestion / `nit`, ending `Approving` / `Requesting changes` / `Commenting`. Bots: `github-actions[bot]` keeps the sticky `📱 Mobile build pipeline` card and a `📦 Build Report` (Android APK per PR; iOS TestFlight needs the `build` label); `regenesis-claw` appears as an approving reviewer on #3031.

## sdk7-test-scenes

- Base `main`. Title `feat: <feature> test scene at <x>,<y>` / `feat: custom font QA scene at 84,-6` (#100); repins are `chore: repin the ... scene to a published SDK` (#104). Branch free (`codex/font-src-test-scene`); use `feat/<slug>`.
- Body (#100): `## What this adds` / `## QA: open the scene` ("Use the Explorer build from decentraland/unity-explorer#10118", "After the **Deploy scenes/84,-6-font-src** check succeeds, connect that build with" `--dclenv zone --realm sdk7testscenes.dcl.eth --position 84,-6`, the jump-in link, SEPOLIA note) / `## QA: what to check` (a `| Button | Expected result |` table is accepted here, unlike godot) / `## Validation and dependencies` ("Passed: `npm install` ..., `npm run build`, `npx tsc --noEmit`, root `npm run check-parcels`, and `git diff --check`"; "Replace this temporary bridge with a published SDK ... before merging"; "Merge the protocol/Explorer feature before this scene").
- Bot: `github-actions[bot]` posts `## How to test scene changes in the SEPOLIA World` with the jump-in link `http://decentraland.zone/jump/?dclenv=zone&realm=sdk7testscenes.dcl.eth&position=<x,y>` built from the first changed scene (`.github/workflows/deploy-worlds.yml` job `pr-comment`). Checks: `Detect changed scenes`, `Deploy scenes/<x>,<y>-<name>`, `Post PR test instructions`.

## docs

- Base `main`; merged with merge commits, so the title is free but recent feature PRs use `docs: <Feature> (<Components>)` (#228 `docs: Nearby Voice Chat (PlayerVoiceState, VoiceChatModifierArea)`). Reuse the protocol branch slug (`feat/nearby-voice-sdk`). No `.github/` on `origin/main` (only `.claude/settings.json`), so no template.
- Open as a **draft** and keep it draft until an `@dcl/sdk` release exposes the feature, because the weekly `docswriter/sync-*` PRs deliberately skip unreleased protocol features.
- Body (#228): lead "Adds a **<Page>** page under <Section> for ..." with one bullet per component; "Draft until the components ship in an `@dcl/sdk` release."; "Sources: decentraland/protocol#499, decentraland/js-sdk-toolchain#1647, unity-explorer stack (linked once open), test scene `60,60-nearby-voice-areas` in sdk7-test-scenes."; "Before merge: replace "an `@dcl/sdk` release newer than 7.30.1" with the actual release version." Touched files: the root `SUMMARY.md` (entry `creator/sdk7/.../<page>.md`), the section `README.md`, the new page. `creator/.gitbook.yaml` names `creator/SUMMARY.md` as the creator space nav, so check which of the two lists the sibling pages before editing.
- Checks: one `GitBook (./creator)` preview check per space; no reviewer bot.

## adr

- Branch `feat/adr-NNN-<slug>` (`feat/adr-318-audio-playback-position`), matching ADR-6's regexp `(chore|docs|feat|fix|refactor|style|test)/[0-9a-zA-Z_-]+` (`content/ADR-6-git-style-guide.md`). Base `main`, squash.
- Title carries the number: `ADR-318: Audio playback position reports` (#324), `ADR 316: Wearable Spring Bones` (#316), `docs: ADR-133 explorers SDK runtime logic override` (#310). Prefer `feat: ADR-NNN <title>`.
- Body (#324): `## Summary` / `## Why` / `## Contents` (what the document covers, one bullet each) / optional `## Notes on <decisions>` / a status and numbering line ("Status: Draft. Numbering: `main` reaches 316 and open PRs use 317, so 318 is the next free number; a few open PRs sit out of sequence at 323, 400 and 401.") / `## Related` (Protocol change, SDK change, Unity explorer change as full URLs) / `## Related pull requests` (Test scene, SDK skills).
- Review: CODEOWNERS `content/* @decentraland/adr-editors`; the author merges after 1-2 approvals. Reviewers on #324 asked to keep the spec protocol-only and to bound renderer behaviour so all three explorers can comply. Bot: `cloudflare-workers-and-pages[bot]` posts `## Deploying adr with Cloudflare Pages` with a preview URL (`https://<hash>.adr-cvq.pages.dev`) and a branch preview (`https://<branch-slug>.adr-cvq.pages.dev`); paste the branch preview into the protocol PR when the ADR is the spec.

## sdk-skills

- Not cloned locally; read with `gh pr view N --repo decentraland/sdk-skills`. Title `feat(<skill>): teach <thing>` (#97 `feat(audio-video): teach audio playback position reports`), branch `feat/<slug>`, base `main`.
- Body (#97): `## What this teaches` / `## The rule` (bold "Never ..." bullets) / version caveat under the existing `SDK VERSION GATE` convention / `## Changes per file` / `## Links` (SDK, Protocol, Unity explorer, ADR) / `## Related pull requests` (Test scene). State "`.sync-state.json` untouched." when it is.

## Bot vocabulary cheat sheet

| Repo | Bot / check | What to do with it |
|---|---|---|
| protocol | `github-actions[bot]` "Test this pull request" | copy the `branch//` tarball URL into SDK, unity and godot pins |
| protocol | `decentraland-bot` review, `P0` / `P1` / `P2` | fix or answer every P0 and P1 before re-request |
| js-sdk-toolchain | `github-actions[bot]` tarballs + `/changerealm`; `check-local-deps` | pin the test scene; repin to npm before merge |
| unity-explorer | `decentraland-bot` (Jarvis), `Claude Review` status, `semantic / title-matches-convention` | re-request with 🔄 after pushes; never self-apply labels |
| godot-explorer | `📱 Mobile build pipeline` card, `build` label for iOS | add the label through a maintainer when QA needs TestFlight |
| sdk7-test-scenes | "How to test scene changes in the SEPOLIA World" | paste its jump-in link into the unity/godot test plans |
| docs | `GitBook (./creator)` preview checks | open the preview before asking for review |
| adr | `cloudflare-workers-and-pages[bot]` preview | link the branch preview from the protocol PR |

## Last verified

2026-10-10 against protocol `d7ddc10` (origin/main = branch head), js-sdk-toolchain origin/main `60e3717`, unity-explorer origin/dev `41a9e92`, bevy-explorer origin/main `ad56994`, godot-explorer origin/main `cada2d9`, sdk7-test-scenes origin/main `06b52ff`, docs origin/main `9729496`, adr origin/main `3fce505`; PR bodies read live with `gh pr view` / `gh api`. The two asset skeletons (`assets/protocol-pr-body.md`, `assets/engine-pr-bodies.md`) were checked against the same heads.
