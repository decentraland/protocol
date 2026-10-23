<!-- Title: docs: AvatarShape keepEmoteOnMove (NPC Avatars) · Branch: feat/avatar-shape-keep-emote-on-move · Base: main · open as DRAFT -->

Adds a **Keep an animation while moving** section to the NPC Avatars page (`creator/sdk7/interactivity/avatars/npc-avatars.md`, under *Animations*) for the new `AvatarShape` field:

- `keepEmoteOnMove`: when `true`, an emote started with `expressionTriggerId` keeps playing while the scene moves the NPC with `Transform` or `Tween`; when the emote ends the avatar goes back to its normal walk/run or idle. Unset keeps today's behaviour. Snippet with `AvatarShape.create(npc, { ..., keepEmoteOnMove: true, expressionTriggerId: 'dance', expressionTriggerTimestamp: 0 })` and a `Tween` move.
- Version hint in the page's existing shape: `**📔 Note**: \`keepEmoteOnMove\` requires \`@dcl/sdk\` version <release> or newer.` plus a platform note that mobile NPCs do not play walk/run when moved, so the field changes nothing there yet.

No new page: `SUMMARY.md` and `avatars/README.md` unchanged. ES copy (`creator-esp/sdk7/interactivity/npc-avatars.md`) pending. `ai-sdk-context/sdk7-complete-reference.md` lists `AvatarShape` fields and should gain the property in the same PR.

Draft until the field ships in an `@dcl/sdk` release. Sources: decentraland/protocol#N, decentraland/js-sdk-toolchain#N, decentraland/unity-explorer#N (pending), decentraland/bevy-explorer#N (pending), decentraland/godot-explorer#N (pending), test scene `4,25-avatar-shape-keep-emote` in sdk7-test-scenes.

Before merge: replace "<release>" in the version hint with the actual `@dcl/sdk` release version.
