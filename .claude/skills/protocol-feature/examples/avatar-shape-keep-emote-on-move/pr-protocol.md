<!-- Title: feat: add keep_emote_on_move to AvatarShape · Branch: feat/avatar-shape-keep-emote-on-move · Base: main
     Plan-mode draft (dry run): nothing below was run or posted; verification lines say "to run". -->

a scene that moves an NPC (`AvatarShape`) with a `Transform` write or a `Tween` while it plays an emote cannot keep that emote: the explorer blends walk/run in (bevy, and the behaviour the docs and sdk-skills describe) or does whatever its animator does. adds `keep_emote_on_move` to `PBAvatarShape` so the scene can say "animate the emote, not the legs" while it moves the entity.

`keep_emote_on_move` (`optional bool`) — `true`: a full-body emote started with `expression_trigger_id` keeps playing while the scene moves the entity (Transform or Tween); no walk/run is blended in until the emote ends or is replaced, then the explorer's locomotion rule applies again. Default `false`: unset changes nothing, so existing scenes are unaffected and every explorer keeps its current behaviour for moved NPCs.

Valid on scene-owned `AvatarShape` entities; ignored on `engine.PlayerEntity` and on other players' entities, whose emotes follow the explorer's input rules. Written by the scene, LWW with the rest of the component, local to the client that renders the scene and never relayed. Explorers without support keep their current behaviour (unknown fields are ignored).

This does not change what happens when the field is absent, does not add looping to AvatarShape emotes (`expression_trigger_timestamp` re-triggers stay the way to loop), does not touch masked emotes, and does not move the NPC differently: position and facing are driven exactly as today, only the animation choice changes.

## Field numbering

Checked `origin/main`, `origin/experimental-bevy`, `origin/protocol-squad`, `origin/experimental`, the 31 open PRs and the engine copies (bevy vendored tree, godot pin `0ff6038`, unity pin `d7ddc10`, sdk pin `6402953`) on 2026-10-10 with `scripts/field-numbers.sh PBAvatarShape` (`NEXT_SAFE_FIELD=14`).

* `PBAvatarShape` takes `keep_emote_on_move = 14`; 12 (`show_only_wearables`) is the last number on `main`.
* `PBAvatarShape` skips **13** because it is `repeated string force_render` on `experimental-bevy` and `protocol-squad` (PRs #472 / #202) and in bevy-explorer's vendored copy; the skip is recorded as a comment next to the new field (`// 13 is force_render on experimental-bevy`), not as a `reserved` line, so the branches keep an identical wire format when `force_render` lands on `main`.
* Component id 1080 unchanged; no new id.

## How to test

```bash
make buf-lint && make test          # to run on this branch
make list-components-ids            # 1080 appears once, unchanged
```

`make buf-breaking` against `main`: to run on the branch (needs network). A pre-check against a local export of `origin/main` with buf 1.8.0 passed: a new `optional` field on `PBAvatarShape` is not a WIRE_JSON break (adding `optional` to an existing field or renaming one would be, and neither happens here).

## Implementation

- js-sdk-toolchain: decentraland/js-sdk-toolchain#N (pending) — field-only PR: spec literals, `playground-assets.api.md`, snapshots
- unity-explorer: decentraland/unity-explorer#N (pending) — `SDKAvatarShapesMotionSystem.UpdateAnimations` keeps `MovementBlend` at 0 while the flag is set and an emote plays
- bevy-explorer: decentraland/bevy-explorer#N (pending) — vendored proto hand-merged (keeps `force_render = 13`, adds 14; matches `experimental-bevy` + this field); `animate` no longer cancels the emote on velocity for flagged NPCs
- godot-explorer: decentraland/godot-explorer#N (pending) — pin bump + field plumbing; moved AvatarShapes already keep their emote there (no locomotion inference); parity issue to file for the unset case

Merge order: this PR first, then every consumer repins from the `Test this pull request` tarball to the published `@dcl/protocol@next` build, then SDK and explorers, test scene last.

## Related

- Test scene: decentraland/sdk7-test-scenes#N (pending; `scenes/4,25-avatar-shape-keep-emote`, world `sdk7testscenes.dcl.eth` at `4,25`)
- Docs: decentraland/docs#N (pending; draft until an `@dcl/sdk` release)
- SDK skills: decentraland/sdk-skills#N (pending; `npcs/SKILL.md` describes today's walk-along-the-tween behaviour)
- ADR: none (small additive field, #489 / #470 precedent)
