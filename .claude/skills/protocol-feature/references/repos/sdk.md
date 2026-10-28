# js-sdk-toolchain

How a merged (or in-flight) `@dcl/protocol` change becomes an `@dcl/sdk` feature: where the pin lives, what codegen produces, which files a PR touches, the few hand-written surfaces, the gates, and the PR conventions. Sibling engine files: `.claude/skills/protocol-feature/references/repos/unity.md`, `bevy.md`, `godot.md`; test scenes and docs live in `verification.md`.

## Contents

1. Where the protocol is pinned
2. Pin lifecycle: PR tarball, then `@next`
3. Codegen and the one reviewable artifact
4. Field on an existing component
5. New component: plain, with helpers, grow-only, JSX
6. Hand-written surfaces that do not update themselves
7. Gates: build, test, snapshots, lint
8. CI and the bot comment
9. PR and commit conventions
10. Kernel APIs and other unmapped paths

## 1. Where the protocol is pinned

`@dcl/protocol` is a dependency in exactly two files: root `package.json` and `packages/@dcl/sdk-commands/package.json`. On origin/main both read `"@dcl/protocol": "1.0.0-34643020503.commit-6402953"`. `packages/@dcl/ecs` has no protocol dependency, because codegen reads `${process.cwd()}/node_modules/@dcl/protocol/proto/decentraland/sdk/components` from the repo root (`scripts/build.spec.ts:compileEcsComponents` call). Ignore `docs/adding-or-modifying-a-component.md`: it says to install the pin inside `packages/@dcl/ecs`, points tests at `packages/@dcl/ecs/test/components/` and references `unity-renderer`, all stale.

The pin lags protocol main. Resolve `commit-<sha7>` in the protocol clone before promising a field exists on the SDK side; today `6402953` is four commits behind `d7ddc10`, so `font_src` (#489) is not in the SDK yet:

```bash
git -C <protocol-clone> merge-base --is-ancestor <sha7> origin/main && echo "pin contains it"
git -C <protocol-clone> log --oneline <sha7>..origin/main      # what the SDK does not have yet
```

## 2. Pin lifecycle: PR tarball, then `@next`

Protocol PR builds exist only on the SDK team CDN, never on npm. The protocol bot comment ("Test this pull request") prints the URL; the double slash is literal because `.github/workflows/build-and-publish.yml` builds the S3 prefix from `steps.myref.outputs.branch`, a step that lives in another job, so copy it verbatim:

```bash
npm i --save-exact "https://sdk-team-cdn.decentraland.org/@dcl/protocol/branch//dcl-protocol-1.0.0-<runId>.commit-<sha7>.tgz"
cd packages/@dcl/sdk-commands && npm i --save-exact "https://sdk-team-cdn.decentraland.org/@dcl/protocol/branch//dcl-protocol-1.0.0-<runId>.commit-<sha7>.tgz"
cd ../../.. && make build
```

Use `--save-exact` in both places so syncpack (`make lint-packages`) sees one version. Once the protocol PR merges to main (which publishes the npm `next` tag), repin with the Makefile target, verbatim from origin/main:

```make
update-protocol:
	npm i --save-exact @dcl/protocol@next
	cd packages/@dcl/sdk-commands; npm i --save-exact @dcl/protocol@next
	$(MAKE) sync-deps compile_apis
```

Or pin the exact published version `1.0.0-<runId>.commit-<sha7>` when `next` has moved past what you tested. Today `next` = `1.0.0-37324405267.commit-d7ddc10`; `latest` (`1.0.0-2569677750.commit-6ce832a`) is ancient, so do not use it. The repin is mandatory before merge: the `check-local-deps` job in `.github/workflows/ci.yml` runs on PRs to main and on main, and `.github/scripts/check-no-local-packages.cjs` fails any packed `package.json` whose dependency starts with `file:`, `http:`, `https:` or `git:`. Sequence the SDK PR after the protocol merge, and say so in the body (section 9).

## 3. Codegen and the one reviewable artifact

`make build` runs `make clean` then `scripts/build.spec.ts`, which calls `compileEcsComponents` (`scripts/protocol-buffer-generation/index.ts`) with protoc 3.20.1 and the `dcl_ts_proto` plugin over every `sdk/components/*.proto`, writing `packages/@dcl/ecs/src/components/generated/` (`<Pascal>.gen.ts`, `index.gen.ts`, `global.gen.ts`, `pb/`). That folder is gitignored (`packages/@dcl/ecs/.gitignore` has `src/components/generated`), so generated code never appears in a diff and stale generated code after a pin bump fails specs in confusing ways; rebuild first.

- Name: `snakeToPascal(file)`, so `avatar_nametag.proto` becomes `AvatarNametag`, `PBAvatarNametag`, `core::AvatarNametag`.
- Id: `scripts/protocol-buffer-generation/generateProtocolBuffer.ts:getComponentId` takes the single line containing both `option` and `ecs_component_id` and throws on zero or more than one match, so keep that pair of words out of comments.
- `test/ecs/component-numbers.spec.ts` with `MAX_STATIC_COMPONENT = 1 << 11` (`packages/@dcl/ecs/src/components/component-number.ts`) requires core ids below 2048.
- Every component is Last-Write-Wins unless its name is in `GROWN_ONLY_COMPONENTS` (section 5).

The reviewable artifact of any proto change is the committed api-extractor report `packages/@dcl/playground-assets/etc/playground-assets.api.md`. `scripts/build.spec.ts` runs `npm run build-local` in playground-assets (`api-extractor run --local`, which rewrites the report) when `GITHUB_STEP_SUMMARY` is unset, and plain `npm run build` (`api-extractor run`, which only compares) under GitHub Actions, so an uncommitted report fails CI. `scripts/build.spec.ts` also fails when the report contains `ae-forgotten-export` or a `_2` name conflict.

## 4. Field on an existing component

Precedents: #1165 (`showOnlyWearables` on AvatarShape; the PR is titled "feat: skin color alpha") and #1560 (`maxCameraDistance` on PointerEvents). A field-only PR touches:

- `package.json`, `package-lock.json`, `packages/@dcl/sdk-commands/package.json`, `packages/@dcl/sdk-commands/package-lock.json` (the pin)
- `packages/@dcl/playground-assets/etc/playground-assets.api.md` (for example `+    showOnlyWearables?: boolean | undefined;`)
- `test/ecs/components/<Name>.spec.ts`: add the new key to every object literal (`showOnlyWearables: false` twice in #1165)
- `test/snapshots/package-lock.json` plus the bundle goldens (15 `.crdt` files on `origin/main` today): `test/snapshots/development-bundles/{static-scene.test,testing-fw.test,two-way-crdt.test}.ts.crdt` and `test/snapshots/production-bundles/{append-value-crdt,billboard,cube-deleted,cube,cubes,pointer-events,schema-components,ui,with-main-function}.ts.crdt` (bundle size and malloc counts change). The other three `.crdt` files under `test/snapshots/` (`main.crdt`, `production-bundles/simple.ts.crdt`, `development-bundles/static-scene.test.js-main.crdt`) do not change on a component bump; they were last touched by #1287, #495 and #548. A bump that only changes `kernel/apis` protos (#1601) touches just the five pin/lock files.
- Hand-written code only when the field reaches an SDK-authored API: #1560 added `maxCameraDistance?: number` to `EventSystemOptions` in `packages/@dcl/ecs/src/systems/events.ts`.

Declare new scalar and message fields `optional`: `create()` / `createOrReplace()` take the full generated type, so a required property breaks every existing scene's type-check. `repeated` fields cannot be optional; the experimental-bevy branch had to add `packages/@dcl/ecs/src/components/extended/AvatarShape.ts` (`Omit<PBAvatarShape, 'forceRender'> & { forceRender?: string[] }`, serializing `[]` when undefined) and list `'AvatarShape'` in `skipExposeGlobally` to make `force_render` optional for scenes.

Spec shape (first case of `test/ecs/components/AvatarNametag.spec.ts`, condensed; the real file also imports `Color3` and adds a full-payload and an optionals-omitted case. `testComponentSerialization` round-trips both `createOrReplace(value)` and `create()` defaults):

```ts
import { Engine, components } from '../../../packages/@dcl/ecs/src'
import { testComponentSerialization } from './assertion'

describe('Generated AvatarNametag ProtoBuf', () => {
  it('should serialize/deserialize AvatarNametag with default values', () => {
    const newEngine = Engine()
    const AvatarNametag = components.AvatarNametag(newEngine)
    testComponentSerialization(AvatarNametag, { label: '', labelColor: undefined, backgroundColor: undefined, borderColor: undefined })
  })
})
```

## 5. New component: plain, with helpers, grow-only, JSX

**Plain data component** (#1600 AvatarNametag, 19 files): the section 4 set plus a new `test/ecs/components/<Name>.spec.ts`. Codegen exports it globally (`global.gen.ts`, re-exported by `packages/@dcl/ecs/src/index.ts`), so no hand-written code.

**Component with helpers** (#1441 TouchScreenControls; `extended/AudioAnalysis.ts` and `extended/LightSource.ts` follow the same shape): four hand-written files, each required because the global export, the getter and the public type are separate surfaces:

```ts
// packages/@dcl/ecs/src/components/extended/<Name>.ts
export interface TouchScreenControlsComponentDefinitionExtended extends LastWriteWinElementSetComponentDefinition<PBTouchScreenControls> { hideAll(): void }
export function defineTouchScreenControlsComponent(engine: Pick<IEngine, 'defineComponentFromSchema'>) { /* return { ...theComponent, hideAll() {...} } */ }
// packages/@dcl/ecs/src/components/index.ts
/* @__PURE__ */
export const TouchScreenControls: LwwComponentGetter<TouchScreenControlsComponentDefinitionExtended> = (engine) =>
  defineTouchScreenControlsComponent(engine)
// packages/@dcl/ecs/src/components/types.ts
export type { TouchScreenControlsComponentDefinitionExtended } from './extended/TouchScreenControls'
// packages/@dcl/ecs/src/index.ts
export const TouchScreenControls: TouchScreenControlsComponentDefinitionExtended = /* @__PURE__*/ components.TouchScreenControls(engine)
```

Skip the `components/types.ts` re-export and api-extractor raises `ae-forgotten-export`, configured as `logLevel: error` in `packages/@dcl/playground-assets/api-extractor.json`, which fails `make build`. `skipExposeGlobally` in `scripts/protocol-buffer-generation/generateIndex.ts` is `['Animator', 'MeshRenderer', 'MeshCollider', 'Material', 'Tween']`: components whose global export is the extended one, so codegen must not also emit a plain global. `NON_EXPOSED_LIST = [1097]` (MapPin) in `scripts/protocol-buffer-generation/index.ts` hides a component from the index entirely.

**Grow-only result component** (#1511 ExplorerUiEventsResult, #1543 ExplorerItemPurchaseResult): add the Pascal name to `GROWN_ONLY_COMPONENTS` in `scripts/protocol-buffer-generation/generateIndex.ts`. Current list on origin/main (8 entries):

```ts
const GROWN_ONLY_COMPONENTS = ['PointerEventsResult', 'VideoEvent', 'AvatarEmoteCommand', 'AudioEvent', 'TriggerAreaResult', 'AssetLoadLoadingState', 'ExplorerUiEventsResult', 'ExplorerItemPurchaseResult']
```

Listed components generate as `engine.defineValueSetComponentFromSchema("core::X", XSchema, { timestampFunction: (t) => t.timestamp, maxElements: 100 })`, so the proto needs a `timestamp` field. The choice is a hard-coded name list, not anything in the proto: forget the entry and you silently get an LWW component while serialization tests still pass. Guard it with the accumulation test from `test/ecs/components/ExplorerUiEventsResult.spec.ts` (`it('should accumulate appended values on the grow only value set')`, two `addValue` calls then `Array.from(X.get(entity))`). Cross-check the other engines' grow-only lists through the sibling files, since they drift independently.

**UI component settable from JSX** (UiInputBinding in #1441): four react-ecs files, plus `test/react-ecs/<name>.spec.tsx` using `setupEngine()` from `test/react-ecs/utils.ts` and a `test/ecs/components/<Name>.spec.ts`:

```ts
// packages/@dcl/react-ecs/src/components/types.ts   (EntityPropTypes; import { PBUiInputBinding } from '@dcl/ecs')
  uiInputBinding?: PBUiInputBinding
// packages/@dcl/react-ecs/src/react-ecs.ts            (EntityComponents)
  uiInputBinding: PBUiInputBinding
// packages/@dcl/react-ecs/src/reconciler/index.ts    (getComponentId)
  const UiInputBinding = components.UiInputBinding(engine)
  uiInputBinding: UiInputBinding.componentId
// packages/@dcl/react-ecs/src/reconciler/utils.ts    (entityComponent, which drives componentKeys)
  uiInputBinding: undefined as any
```

## 6. Hand-written surfaces that do not update themselves

- `packages/@dcl/ecs/src/systems/events.ts`: `EventSystemOptions` (`maxDistance`, deprecated `maxPlayerDistance`, `maxCameraDistance`) feeds `PointerEvents.Info`; a new Info field must be plumbed here.
- `packages/@dcl/react-ecs/src/components/Label/types.ts`: `UiLabelProps` is manual, so a new `PBUiText` field is untyped until declared there; the value then flows through `...textProps` in `Label/index.tsx`. origin/main has no `fontSrc` yet; experimental-bevy commit `1fb1939a` adds `fontSrc?: string | undefined` as the precedent.
- `packages/@dcl/react-ecs/src/components/uiTransform/types.ts` (`UiTransformProps`) and `uiTransform/index.ts:parseUiTransform` (helpers in `uiTransform/utils.ts`) are fully manual (`zIndex` and `opacity` were added by hand there).
- `Input/types.ts` (`UiInputProps extends Omit<PBUiInput, 'font' | 'textAlign' | 'fontSize'>`) and `Dropdown/types.ts` extend the PB type, so they pick up new fields automatically.
- Wrappers `Label`, `Button`, `Input`, `Dropdown` (`index.tsx`) destructure `uiTransform, uiBackground, onMouseDown, onMouseUp, onMouseEnter, onMouseLeave` by name and spread the rest into their PB. A new `EntityPropTypes` key must be destructured in each wrapper or it lands inside the wrong component; on origin/main `uiInputBinding` still is not, and the fix sits unmerged on `origin/fix/ui-input-binding-dropped` (fix commit `58b816d8`, branch head `b20bf02e`).
- The Inspector is not in this repo (`@dcl/inspector` 7.36.3 is a dependency of sdk-commands); editor support for a component is out of scope here.

## 7. Gates: build, test, snapshots, lint

Run from the repo root, in this order (the Makefile is the source of truth; AGENTS.md on origin/main documents it):

```bash
make install    # npm i + protoc 3.20.1 into node_modules/.bin/protobuf (first time, or after a clean)
make build      # make clean; codegen, per-package npm i + tsc, api report (not npm workspaces: each package has its own lockfile)
make test       # node_modules/.bin/jest --detectOpenHandles --forceExit --colors test/
make lint       # npx tsx scripts/lint-packages.ts; CI also runs make lint-packages (syncpack)
node_modules/.bin/jest --colors --forceExit --testPathPatterns='test/ecs'   # jest 30 on origin/main: plural flag; also test/react-ecs, test/snapshots
cd packages/@dcl/<package> && npx tsc --noEmit -p tsconfig.json              # babel-jest does not type-check tests
```

Snapshots: `test/snapshots.spec.ts` reads `process.env.UPDATE_SNAPSHOTS`, writes the new golden, then still asserts it against the old content, so the first run after any change fails by design and CI (which sets `UPDATE_SNAPSHOTS: true`) catches uncommitted goldens the same way.

```bash
UPDATE_SNAPSHOTS=true node_modules/.bin/jest --runTestsByPath test/snapshots.spec.ts   # fails once, rewrites the goldens
node_modules/.bin/jest --runTestsByPath test/snapshots.spec.ts                        # must pass
grep -rn "ERR!" test/snapshots/                                                       # must print nothing
```

`make update-snapshots` (build + test with the env var) also rewrites `test/ecs/composites/*.scene-snapshot.json`. An `ERR!` line means the QuickJS eval threw, usually a missing `~system/*` mock in the `require` shim of `test/snapshots.spec.ts`; never commit it. `jest.config.js` declares 100% coverage thresholds but `make test` passes no `--coverage`, so run `node_modules/.bin/jest --coverage --testPathPatterns='test/ecs'` yourself for new extended or system code. Before committing, revert `"peer": true` / `"dev": true` lockfile churn, revert files `make format` touched outside your change (it covers `test/` and `scripts/`, which `make lint` does not), and check that `"@dcl/ecs": "file:../ecs"` in `packages/@dcl/sdk-commands/package.json` was not rewritten. Windows checkouts fail `test/ecs/composite.spec.ts` on CRLF; Linux CI is the signal.

## 8. CI and the bot comment

`.github/workflows/ci.yml` (node 24.16.0) on pushes to main/auth-server and on PRs: `lint` (`make install`, `make lint`, `make lint-packages`), `docs` (`make docs`), `test` (`make install`, `make build`, `make test` with `UPDATE_SNAPSHOTS: true`, `make test-cli`, `make prepare`), `build` (oddish publishes the six packages to npm and S3 under `@dcl/js-sdk-toolchain/branch/<branch>`), `notify_deployment`, `cli_e2e`, `check-local-deps` (section 2). The `notify_deployment` comment is titled "Test this pull request" and gives, verbatim from #1600:

```bash
npm install "https://sdk-team-cdn.decentraland.org/@dcl/js-sdk-toolchain/branch/feat/avatar-nametag/dcl-sdk-7.27.1-33889391869.commit-f984188.tgz"
npm install "https://sdk-team-cdn.decentraland.org/@dcl/js-sdk-toolchain/branch/feat/avatar-nametag/@dcl/js-runtime/dcl-js-runtime-7.27.1-33889391869.commit-f984188.tgz"
export SDK_COMMANDS="https://sdk-team-cdn.decentraland.org/@dcl/js-sdk-toolchain/branch/feat/avatar-nametag/dcl-sdk-commands-7.27.1-33889391869.commit-f984188.tgz"; npx $SDK_COMMANDS init
/changerealm https://sdk-team-cdn.decentraland.org/ipfs/feat/avatar-nametag-e2e        # in play.decentraland.zone
https://playground.decentraland.org/?sdk-branch=feat/avatar-nametag
```

Manual check: install the `@dcl/sdk` tarball in a scene (or `make init-test-scene`, which clones sdk7-scene-template into `./test-scene` and installs the local packages) and run `npm run start` (= `sdk-commands start`; flags in `packages/@dcl/sdk-commands/src/commands/start/index.ts`: `--bevy-web`/`--web`, `--mobile`, `--dclenv zone`, `--position x,y`, `--no-client`, `--mcp`). Which engine to open and where the feature's test scene goes is in `verification.md`.

## 9. PR and commit conventions

- `AGENTS.md` is canonical (`CLAUDE.md` is `@AGENTS.md`). `REVIEW.md` is blocking: §1 no narration comments, §2 a short human description with What/why, How to test and Proof, §3 bug fixes ship a test scene or a failing-test repro, §4 one change request per violation citing the rule (`REVIEW.md §2`). Read both with `git show origin/main:<file>`, since local clones lag.
- Conventional Commits, usually scoped: `feat(ecs): add AvatarNametag component (#1600)`, `fix(react-ecs): ...`, `fix(sdk-commands): ...`. Pure repins: `chore: bump @dcl/protocol to 1.0.0-34239802138.commit-e89d7fa (TeleportToRequest.realm) (#1601)`. No `Co-Authored-By` lines. Squash merge, PR number appended.
- Body for a protocol-dependent PR (#1511 shape): the dependency line `Depends on decentraland/protocol#455 — **do not merge before it**`, a `## Before merging` checklist (protocol merged; `@dcl/protocol` repinned from the PR tarball to the published version; lockfiles refreshed; snapshots and `api.md` regenerated), and links to the protocol PR, the renderer PR or branch (#1600: `Protocol source: decentraland/protocol#474`, `Renderer implementation: decentraland/unity-explorer branch feat/sdk/scene-name-tag`) and the sdk7-test-scenes PR. Name the exact pin you tested in the body, as #1600 does.
- Test plan as `- [ ]` lines a reviewer can run: `make build`, the component's CRDT kind and id (`core::AvatarNametag` -> 1221), the new spec, the snapshot double run, the scoped jest command.

## 10. Kernel APIs and other unmapped paths

`~system/*` RPC changes are not components. `make compile_apis` runs protoc with `dcl_ts_proto` over `node_modules/@dcl/protocol/proto/decentraland/kernel/apis/*.proto` into `scripts/rpc-api-generation/src/proto/*.gen.ts`; `scripts/rpc-api-generation/index.ts:compileProtoApi` turns those into `scripts/rpc-api-generation/src/modules/index.d.ts`, which `scripts/build.spec.ts` copies to `packages/@dcl/js-runtime/apis.d.ts` (gitignored via `packages/@dcl/js-runtime/.gitignore`). Enums shared with `sdk/components/common` are rewritten to `import('../ecs').X` so scenes see one nominal type (#1511). Everything after that, such as the helper in `packages/@dcl/sdk/src/explorer-ui/index.ts` from #1543, is per-feature and unmapped end to end: read the precedent PR for the API you are extending rather than assuming a recipe. Comms (`rfc4`, Pulse) have no SDK-side recipe here either.

## Last verified

2026-10-10 against js-sdk-toolchain `origin/main` 60e3717f (2026-10-08) and protocol `main` d7ddc10; branch facts from `origin/experimental-bevy` and `origin/fix/ui-input-binding-dropped`; PR file lists via `gh pr view` (#1165, #1441, #1511, #1543, #1560, #1600, #1601).
