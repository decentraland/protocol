<!-- Title: feat(npcs): teach AvatarShape keepEmoteOnMove · Branch: feat/avatar-shape-keep-emote-on-move · Base: main
     Repo not cloned locally; read with `gh api repos/decentraland/sdk-skills/contents/npcs/SKILL.md`. -->

## What this teaches

`AvatarShape.keepEmoteOnMove`: an NPC moved with `Transform` or `Tween` keeps playing its `expressionTriggerId` emote instead of switching to walk/run; when the emote ends the avatar returns to its normal locomotion. Unset keeps today's behaviour.

## The rule

- **Never** re-trigger an emote every frame to fake "emote while moving"; set `keepEmoteOnMove: true` once and move the entity.
- **Never** rely on the flag to loop an emote: emotes on `AvatarShape` still play once; bump `expressionTriggerTimestamp` to replay.
- **Never** set it expecting other players or the local player to be affected; it only applies to scene-owned NPCs.

SDK VERSION GATE: requires `@dcl/sdk` <release> or newer; on older explorers the NPC behaves as before (walk/run on Unity and bevy; idle slide on mobile).

## Changes per file

- `npcs/SKILL.md` ~120: after "the avatar plays its walk animation along the tween" add the `keepEmoteOnMove` caveat and a 4-line snippet; ~204: add `4,25-avatar-shape-keep-emote` next to the 4,19 scene line.
- `sdk-scenes/references/components-reference.md`: `AvatarShape` row gains `keepEmoteOnMove?: boolean`.
- `.sync-state.json` untouched.

## Links

- SDK: decentraland/js-sdk-toolchain#N · Protocol: decentraland/protocol#N · Unity explorer: decentraland/unity-explorer#N · ADR: none (small additive field)

## Related pull requests

- Test scene: decentraland/sdk7-test-scenes#N · Docs: decentraland/docs#N
