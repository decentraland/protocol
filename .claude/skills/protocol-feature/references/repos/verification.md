# Cross-repo verification: test scenes, docs, sdk-skills
How a protocol feature is proven and announced outside the engine repos: the sdk7-test-scenes scene that QA opens, the optional scene-explorer-tests suite, the decentraland/docs page, the decentraland/sdk-skills update, and who reviews what in each repo.

## Contents
1. Freshness pre-flight
2. sdk7-test-scenes: add a scene
3. CI deploy and the PR comment
4. SDK pin inside a test scene (`TEST_SCENE_PIN`)
5. Test-scene PR shape
6. Run a scene on each engine
7. scene-explorer-tests (optional, frozen)
8. decentraland/docs
9. decentraland/sdk-skills
10. Reviewers, bots and QA per repo
11. Tracking: there is no cross-repo board
12. Last verified

## 1. Freshness pre-flight
Local clones lag their remotes (the docs clone still has the pre-move `creator/sdk7/interactivity/npc-avatars.md`), so read the fetched branch, not the working tree: `git fetch origin main` then `git show origin/main:<path>` / `git ls-tree origin/main <dir>`. decentraland/sdk-skills is not cloned; read it with `gh api repos/decentraland/sdk-skills/contents/<path> --jq .content | base64 -d`. Engine-side facts live in the sibling files `.claude/skills/protocol-feature/references/repos/{unity,bevy,godot,sdk}.md`; policy values named below live in `.claude/skills/protocol-feature/references/policy.md`.

## 2. sdk7-test-scenes: add a scene
Every scene is a standalone SDK7 project; there is no npm workspace and no `dcl-workspace.json` since `34f960b chore: remove local workspace (#77)` (2026-07-22). unity-explorer's `docs/how-to-implement-new-sdk-components.md` step 3 and `.claude/agents/dcl-sdk-feature-implementation/dcl-test-scene-specialist.md` still say `check-parcels` updates `dcl-workspace.json`; do not copy that step.

README.md on origin/main, verbatim:
```
## Step to add a local scene
1. Just create a new folder inside the `scenes/` path. Name it `<x>,<y>-<feature-name>` after its base parcel.
2. Copy your scene inside here or start a new one `npx @dcl/sdk-commands init`
3. Run `npm install` once at the repo root (installs the checker's deps), then `npm run check-parcels` to verify the scene's parcels don't collide with another scene.
4. Commit your changes and push
```
`check-parcel-collisions.js` reads every `scenes/*/scene.json`, prints `✅ No collisions found`, or `❌🔴 Tile <x,y> has two or more scenes assigned:` and exits 1.

`scene.json` must carry the world name, because CI deploys to that shared world:
```json
"worldConfiguration": {
  "name": "sdk7testscenes.dcl.eth"
}
```
Minimal scene layout (copy `scenes/4,19-avatar-shape-movement/`): `.dclignore`, `.gitignore`, `README.md`, `images/scene-thumbnail.png`, `package.json`, `scene.json`, `src/index.ts`, `tsconfig.json` (`"extends": "@dcl/sdk/types/tsconfig.ecs7.json"`). Scripts: `"build": "sdk-commands build --skip-install"`, `"deploy": "sdk-commands deploy"`, `"start": "sdk-commands start"`. `package-lock.json` and `node_modules` are gitignored at every level.

Avatar parcels on origin/main (`git ls-tree --name-only origin/main scenes/ | grep '^scenes/4,'`): `4,19-avatar-shape-movement`, `4,20-avatar-shape`, `4,21-avatar-shape-emotes`, `4,22-avatar-shape-scene-emotes`, `4,23-emote-finish`, `4,24-avatar-nametag`; each claims only its base parcel, so **4,25 is free** as of commit 06b52ff. Re-run the listing and `npm run check-parcels` after fetching, because a parallel PR may take it. For AvatarShape locomotion work, base the scene on `scenes/4,19-avatar-shape-movement/src/index.ts` (a `CreateAvatarShape` helper, Transform jumps between four positions, and `Tween`/`TweenSequence` paths).

## 3. CI deploy and the PR comment
`.github/workflows/deploy-worlds.yml` runs on push to `main`, on every `pull_request`, and on `workflow_dispatch` with input `scene` (e.g. `scenes/88,-10-audio-visualization`). It diffs `HEAD~1..HEAD` for changed `scenes/<dir>/scene.json`, then per scene runs `npm install`, `npm run build` and:
```
npm run deploy -- --target-content=https://worlds-content-server.decentraland.zone --multi-scene
```
Deploys are additive into the one shared world, so a PR's version of a scene replaces main's at those parcels until the next deploy of that scene; warn QA when two PRs touch the same parcels.

On PRs the job `Post PR test instructions` creates or updates a comment titled `## How to test scene changes in the SEPOLIA World` using the coordinates of the first changed scene. Reuse its link shapes in PR bodies and QA plans (MetaMask must be on SEPOLIA):
```
Jump-in:      http://decentraland.zone/jump/?dclenv=zone&realm=sdk7testscenes.dcl.eth&position=<x,y>
Deep link:    decentraland://?dclenv=zone&realm=sdk7testscenes.dcl.eth&position=<x,y>
Custom build: --dclenv zone --realm sdk7testscenes.dcl.eth --position <x,y>
Unity Editor: Decentraland Environment = zone, Init Realm = sdk7testscenes.dcl.eth
```
The deploy check is named `Deploy scenes/<x>,<y>-<slug>`; tell QA to wait for it before opening the link.

## 4. SDK pin inside a test scene (`TEST_SCENE_PIN`)
Released features pin a published SDK (`"@dcl/sdk": "^7.24.5"` in 4,19; `"latest"` in 4,23). Unreleased features pin the tarballs from the js-sdk-toolchain PR bot comment (`# Test this pull request`, one `npm install "<url>"` block each for `@dcl/sdk` and `@dcl/js-runtime`, from `.github/workflows/ci.yml` there). Precedent merged to main still pinned, `scenes/4,24-avatar-nametag/package.json`:
```json
"@dcl/sdk": "https://sdk-team-cdn.decentraland.org/@dcl/js-sdk-toolchain/branch/feat/avatar-nametag/dcl-sdk-7.27.1-33889391869.commit-f984188.tgz",
"@dcl/js-runtime": "https://sdk-team-cdn.decentraland.org/@dcl/js-sdk-toolchain/branch/feat/avatar-nametag/@dcl/js-runtime/dcl-js-runtime-7.27.1-33889391869.commit-f984188.tgz"
```
The newer precedent, `scenes/84,-6-font-src` (#100), pins `"@dcl/sdk": "7.29.0"` plus an `@dcl/protocol` PR tarball with a postinstall bridge and states "Replace this temporary bridge with a published SDK supporting fontSrc before merging". The two conflict; apply the `TEST_SCENE_PIN` policy value (default `published`: repin to a released `@dcl/sdk`, or `@next` once the SDK PR is merged, before the scene PR merges) and say which one you applied in the PR body, so reviewers do not relitigate it.

## 5. Test-scene PR shape
Follow sdk7-test-scenes#100 (`feat: custom font QA scene at 84,-6`), the repo has no PR template:
```
## What this adds
## QA: open the scene            <- "Use the Explorer build from decentraland/unity-explorer#NNNN", the custom-build args, the jump-in link, "If using MetaMask, use SEPOLIA"
## QA: what to check             <- a `| Button | Expected result |` table, one row per on-screen control
## Validation and dependencies   <- what passed (`npm install`, `npm run build`, `npx tsc --noEmit`, root `npm run check-parcels`), the SDK/protocol pin, "Merge the protocol/Explorer feature before this scene"
```
Keep expected results observable without reading code ("Samples disappear one at a time"), and state what visual checks cannot prove.

## 6. Run a scene on each engine
From the scene folder, `npm install` then `npm run start` with one flag (all parsed in js-sdk-toolchain `packages/@dcl/sdk-commands/src/commands/start/index.ts`):

| Target | Command |
|---|---|
| Unity desktop client | `npm run start -- --explorer-alpha` (Windows: `npm run start '--' --explorer-alpha`) |
| Unity + MCP automation (screenshots, walk, click) | `npm run start -- --mcp --skip-auth-screen true`; server on port 8123, driven by the `unity-explorer-mcp` skill in decentraland/sdk-skills (`npx skills add decentraland/sdk-skills --skill unity-explorer-mcp`) |
| Bevy web | `npm run start -- --bevy-web` (alias `--web`) |
| Godot mobile app | `npm run start -- --mobile` (prints a QR) |
| Other start flags | `--dclenv`, `--realm`, `--position`, `--local-scene`, `--no-client`, `--multi-instance`, `--mcp-port` |

Custom engine builds against the local server (`http://127.0.0.1:8000`):
- Unity (`docs/how-to-connect-to-a-local-scene.md`): `Decentraland.exe --realm http://127.0.0.1:8000 --position 0,0 --local-scene true --debug --skip-version-check true` (macOS: `open Decentraland.app --args ...`). Agents cannot build Unity; a human runs `metaforge explorer run <PR>` from the Unity PR template.
- Bevy (`justfile`, args in `crates/system_api_types/src/launch_options.rs`): `just native-debug --realm http://127.0.0.1:8000 --position <x,y> --preview` (`native-release` for the release build).
- Godot (`lib/src/godot_classes/dcl_cli.rs`): `cargo run -- run -- --skip-lobby --preview --realm http://localhost:8000 --location <x,y>`.
- Deployed scene on any engine: the jump-in / deep link / custom-build args from section 3.

Record every runtime observation in the proposal as `observed (who, how, date)` or `pending`; a grep is never an L2 observation (see `.claude/skills/protocol-feature/references/process.md`).

## 7. scene-explorer-tests (optional, frozen)
decentraland/scene-explorer-tests is the only automated cross-engine suite, and it has not moved since `2b82e41` (2024-04-30). Facts that make it optional, never the gate (`ROLLOUT_INCLUDES` default excludes it):
- `package.json` and `build.sh` pin `@dcl/sdk` 7.3.36 from the `psquad/test-framework-tool` branch tarball; new tests must be added to root `workspaces` and `dcl-workspace.json`, and CI (`bash build.sh`) fails when `npm run sync` (syncpack) changes a package.json.
- Test shape: `<x>,<y>-<component>/src/tests/<name>/index.test.ts` calling `test('avatar-shape: title', async function (context) { ...; await context.helpers.waitNTicks(500); await assertSnapshot('screenshot/$explorer_snapshot_avatar_shape.png', camPos, target) })`; `testing-library/src/utils/snapshot-test.ts` swaps `$explorer` for the engine agent, 512x512, grey-diff threshold 0.9995.
- Godot: `src/main.rs` `coverage` runs a hard-coded `scene_test_coords` list ([52,-52] .. [54,-60], video disabled) against `http://localhost:7666/scene-explorer-tests`; `.github/workflows/coverage.yml` installs `@dcl/scene-explorer-tests@1.0.0-20240430222335.commit-2b82e41`; snapshots in `tests/snapshots/scenes/`, refreshed with `cargo run -- update-coverage-snapshots --branch <x> | --run-id <n>`; local run `cargo run -- run -- --scene-test "[[x,y]]" --realm http://localhost:8000` (`--scene-test` takes `[[x,y],...]` per `dcl_cli.rs`; README.md does not document it).
- Bevy: `.github/workflows/ci.yml` job `Test Scenes` is `continue-on-error: true`, runs only when Rust dependency files change, with `--test_scenes "52,-52;...;54,-60"`; snapshots in `crates/assets/src/assets/images/screenshots/`.
- Unity has only the generated `Explorer/Assets/Protocol/DecentralandProtocol/Testing.gen.cs`, no `TakeAndCompareScreenshot` implementation.
- Neither engine's coordinate list includes `54,-62-avatar-shape`. Adding an AvatarShape test means an SDK bump across all workspaces, a republish, a Godot pin bump and new snapshot images in both engine repos: mention it as a follow-up only when the user asks.

## 8. decentraland/docs
GitBook monorepo (`creator/`, `creator-esp/`, `player/`, `player-spa/`, `contributor/`, `contributor-esp/`, `apis/`, `ai-sdk-context/`); no `.github/` directory, so no templates and no CI beyond GitBook's PR preview check ("Every merge to `main` triggers an automatic deployment", README.md). Conventions: every page starts with `---\ndescription: ...\n---` front matter (seen on the pages themselves; README.md does not state it); from README.md, callouts are `{% hint style="info|warning|danger|success" %}`; every new page goes into `creator/SUMMARY.md` (max 2 nesting levels, groups are `##` headings); commit message `docs: Description of changes`.

SDK7 avatar docs on origin/main live in `creator/sdk7/interactivity/avatars/` (`README.md` index, `move-player.md`, `avatar-animations.md`, `locomotion.md`, `modifier-areas.md`, `avatar-nametags.md`, `npc-avatars.md`). The NPC page is `creator/sdk7/interactivity/avatars/npc-avatars.md` (the root `SUMMARY.md` lists it as the entry `NPC Avatars` pointing at `sdk7/interactivity/avatars/npc-avatars.md`, nested under the `Avatars` entry for `sdk7/interactivity/avatars/`), sections `Create an avatar`, `Animations`, `Looping Animations`, `Add a label above the name`, `Copy wearables from player`, `Display only wearables`, `Attach an entity to an NPC`, `Replace the player's avatar`. A new field on an existing component edits the matching section and, for a new page, also the bullet list in `avatars/README.md` (docs#228 touched `SUMMARY.md`, `avatars/README.md` and the new page). `ai-sdk-context/sdk7-complete-reference.md` repeats component fields and drifts separately.

Version-gate hint, verbatim from `avatar-nametags.md`, because readers on an older SDK must see why the field is missing:
```
{% hint style="warning" %}
**📔 Note**: `AvatarNametag` requires `@dcl/sdk` version 7.28.0 or newer.
{% endhint %}
```
Platform-limit hint (`creator/sdk7/3d-essentials/sounds.md`): `**📔 Note**: Global Sounds are a feature that's only supported in the DCL 2.0 desktop client.` Use the same shape for engines that have not shipped the feature; `creator/sdk7/releases/version-support-agreement.md` only requires that unstable features are "clearly labeled" and allows `@next` features to be undocumented.

Docs PR shape (docs#228 `docs: Nearby Voice Chat (PlayerVoiceState, VoiceChatModifierArea)`, draft): a short paragraph per component, then verbatim: "Draft until the components ship in an `@dcl/sdk` release. Sources: decentraland/protocol#499, decentraland/js-sdk-toolchain#1647, unity-explorer stack (linked once open), test scene `60,60-nearby-voice-areas` in sdk7-test-scenes." and "Before merge: replace "an `@dcl/sdk` release newer than 7.30.1" with the actual release version." Open it as a draft from the definition phase and fill the version number at release time.

Weekly sync: branches `docswriter/sync-YYYY-MM-DD` (docs#225, `docswriter/sync-2026-10-08`) port merged changes from the source repos, "English docs only; creator-esp untouched", and skip unreleased protocol work: "protocol d7ddc10 font_src: deliberately NOT documented, no published @dcl/sdk or Explorer release exposes it yet." SDK release notes go to `creator/sdk7/releases/releases.md`. The feature author therefore owns the draft docs PR; the sync will not write it. `creator-esp/` is updated by hand, so note "ES copy pending" in the bundle rather than leaving it implicit.

## 9. decentraland/sdk-skills
AI creator skills installed with `npx skills add decentraland/sdk-skills --all`. Skills sit at the repo root as `<skill>/SKILL.md` (e.g. `npcs/SKILL.md`, `player-avatar/SKILL.md`, `avatar-animations/SKILL.md`, `sdk-scenes/references/components-reference.md`); there is no `skills/` folder. `.sync-state.json` records `lastCommit`/`lastChecked` for `docs`, `protocol` (d7ddc10 on 2026-10-08), `js-sdk-toolchain`, `creator-hub`, `sdk7-test-scenes` and `sdk-skills`, so the sync PRs know what they already covered. CI is `node --test tests/*.test.mjs` (`.github/workflows/test.yml`).

`npcs/SKILL.md` ~120 currently states: "Moving the `Transform` position causes the NPC to walk/run to the destination (it does not teleport). ... the avatar plays its walk animation along the tween." and ~204 links `4,19-avatar-shape-movement` as "(walks to target)". Any AvatarShape locomotion opt-out must change both lines (and `sdk-scenes/references/components-reference.md`), otherwise generated scenes keep describing the old behaviour.

Open a sdk-skills PR whenever the feature is creator-visible (new component, field, restricted action or behaviour change). Precedents: #107 `feat: skybox textures configuration` (body is a `## Related PRs` list: unity-explorer#10287, protocol#495, js-sdk-toolchain#1638, docs#213, sdk7-test-scenes#106) and #118 `Teach player-avatar about nearby voice chat` (draft; "Draft until the components ship in an `@dcl/sdk` release. Sources: decentraland/protocol#499, decentraland/js-sdk-toolchain#1647."; touches the skill, `sdk-scenes/SKILL.md`, the components reference and `README.md`). Pure engine fixes with no API change need no PR there.

## 10. Reviewers, bots and QA per repo
| Repo | Templates | Bots | Human gate |
|---|---|---|---|
| protocol | none (`.github/` = `dependabot.yml`, `workflows/{build-and-publish,validate}.yml`) | PR comment `# Test this pull request` with the `npm install "<S3 tarball>"` line; `decentraland-bot` reviews as `## Review: ...` with P0/P1/P2-ranked findings (`[P2]` tags in #497, `### P0 — Blocker` headings in #464) | maintainer approval (e.g. #489); README asks for the Unity implementation before merge |
| js-sdk-toolchain | none | PR comment with `@dcl/sdk` and `@dcl/js-runtime` tarball URLs (`.github/workflows/ci.yml`) | SDK maintainers |
| unity-explorer (`origin/dev`) | `.github/PULL_REQUEST_TEMPLATE.md`: "For SDK features: Include or link to a test scene", `metaforge explorer run <PR>` steps, checklist `[ ] For SDK features: Test scene is included` | `auto-assign.yml` requests a `qa` reviewer on every PR (skipped by labels `no QA needed` / `no review`) and `techleads`/`devs` reviewers on PRs whose title is not `fix:`/`chore:`; `decentraland-bot` pre-review ends with `QA_REQUIRED: YES|NO` (`docs/branch-and-pr-standards.md`) | `enforce-group-approvals.yml`: >=1 `qa` approval (unless label `no QA needed`), >=1 `explorer-devs` approval (unless label `claude-approved`), CI green, not draft; squash merge |
| godot-explorer | `bug_report.yml` only; PR body per `REVIEW.md` (`## What` / `## Why` / optional `## Details` / `## Test plan` with `- [ ] **Expected:**` boxes) | `build` label posts the `📱 Mobile build pipeline` card; daily `pr-review-report.yml` to Slack | QA runs the test plan by hand on phones (TestFlight / Firebase); `CODEOWNERS` `@decentraland/rgl-mobile-team` |
| bevy-explorer | none | CI only (`Test Scenes` non-blocking) | maintainer review |
| sdk7-test-scenes | none | deploy comment (section 3) | author merges (unity guide: "you are responsible for merging it") |
| docs | none | GitBook preview check | docs maintainers; weekly sync |
| sdk-skills | none | `test.yml` | maintainers |

## 11. Tracking: there is no cross-repo board
Org projects exist per feature in shape-up style (#114 Nearby Voice Chat, #115 Point-at, #119 Avatar Masks, template #83 `[TEMPLATE] Shapes Projects`) and godot's issue-writer skill files to org project 43 (titled `MobileTeam` today; the skill still calls it "DAO Explorers"), but none tracks protocol, SDK, Unity, Bevy, Godot, test-scene, docs and sdk-skills PRs together. The proposal bundle is the tracker: keep one line per repo with the PR link and state (`open | merged | n/a: <reason>`), in merge order (protocol, SDK + engines, test scene, docs, sdk-skills), and update it in the review phase.

## 12. Last verified
2026-10-10 against sdk7-test-scenes `origin/main` 06b52ff, docs `origin/main` 9729496, scene-explorer-tests `origin/main` 2b82e41, godot-explorer `origin/main` cada2d9, bevy-explorer `origin/main` ad56994, unity-explorer `origin/dev` 41a9e92, js-sdk-toolchain `origin/main` 60e3717, protocol `main` d7ddc10, sdk-skills via `gh api` (`.sync-state.json` self-commit 8e5b628), GitHub PRs sdk7-test-scenes#77/#100, docs#225/#228, sdk-skills#107/#118, protocol#464/#489/#497/#499, unity-explorer#10118/#10409.
