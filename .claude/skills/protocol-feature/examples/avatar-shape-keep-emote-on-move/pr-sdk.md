<!-- Title: feat(ecs): add keepEmoteOnMove to AvatarShape · Branch: feat/avatar-shape-keep-emote-on-move · Base: main
     Plan-mode draft: verification lines stay unticked until they ran. -->

Scenes can now set `keepEmoteOnMove: true` on an `AvatarShape` so an NPC keeps playing its `expressionTriggerId` emote while the scene moves it with `Transform` or `Tween`, backed by `keep_emote_on_move` (field 14) from the protocol. Today the explorer blends walk/run in and the emote is lost; unset keeps that behaviour.

Depends on decentraland/protocol#N — **do not merge before it**.

## What changes

- `@dcl/protocol` pinned to the PR tarball in `package.json` and `packages/@dcl/sdk-commands/package.json` (`npm i --save-exact "<tarball url>"` in both). The current pin `1.0.0-34643020503.commit-6402953` is four protocol commits behind `main`, so this bump also brings `font_src` (protocol #489); no scene-facing change from that beyond the new optional properties.
- `test/ecs/components/AvatarShape.spec.ts`: `keepEmoteOnMove` added to both literals; regenerated `packages/@dcl/playground-assets/etc/playground-assets.api.md` (`keepEmoteOnMove?: boolean | undefined` on `PBAvatarShape`), the CRDT snapshot goldens and the lockfiles.
- No hand-written surface: `AvatarShape` has no `extended/` helper on `main`, is LWW and is not a UI prop.

## How to test

```bash
make build && node_modules/.bin/jest --testPathPatterns 'test/ecs/components/AvatarShape'
UPDATE_SNAPSHOTS=true node_modules/.bin/jest --runTestsByPath test/snapshots.spec.ts && node_modules/.bin/jest --runTestsByPath test/snapshots.spec.ts
grep -rn "ERR!" test/snapshots/   # must print nothing
make lint && make test
```

- [ ] to run: the four commands above (the first snapshot run fails by design and rewrites the goldens; the second must pass)

## Proof

Test scene decentraland/sdk7-test-scenes#N (`scenes/4,25-avatar-shape-keep-emote`) installs this PR's `@dcl/sdk` and `@dcl/js-runtime` tarballs from the bot comment; NPC **A** (no flag) shows today's behaviour when moved, NPC **B** (`keepEmoteOnMove: true`) keeps its emote through the Transform jump and the Tween.

## Before merging

- [ ] decentraland/protocol#N merged
- [ ] `@dcl/protocol` repinned from the PR tarball to the published version (`make update-protocol`), lockfiles refreshed, snapshots and `api.md` regenerated (`check-local-deps` rejects http pins)

Related: decentraland/unity-explorer#N (pending) · decentraland/bevy-explorer#N (pending) · decentraland/godot-explorer#N (pending) · docs decentraland/docs#N (pending)
