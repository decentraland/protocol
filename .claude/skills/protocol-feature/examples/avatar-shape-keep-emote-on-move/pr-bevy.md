<!-- Title: Keep an AvatarShape emote playing while the scene moves it · Branch: feat/avatar-shape-keep-emote-on-move · Base: main
     Plan-mode draft: the verification paragraph describes what is to be observed, not what was. -->

## Problem

A scene NPC (`AvatarShape`) that is moved with a Transform write or a Tween loses its emote as soon as it moves: `animate` cancels the triggered emote when the damped velocity rises above the slowest speed seen since the emote began (`velocity_cancels` is true for every non-foreign avatar), and the velocity-selected walk/run takes over. Creators have no way to say "keep the emote, I am moving the entity on purpose".

## Fix

Follow decentraland/protocol#N: `PBAvatarShape.keep_emote_on_move` (`optional bool`, field 14). When it is `true` on a scene-owned AvatarShape, `animate` no longer treats velocity as a cancel reason for that avatar, so the triggered emote keeps playing through the motion until it finishes or the scene's `expressionTriggerId` / timestamp changes; locomotion then resumes from velocity as before. Unset or `false` changes nothing. The flag is ignored for the primary user (`AvatarShape` on the player entity, #1242) and for foreign players, whose emotes already persist under movement until a wire stop.

Vendored proto updated to match `experimental-bevy` plus this field (`crates/dcl_component/src/proto/decentraland/sdk/components/avatar_shape.proto` keeps `repeated string force_render = 13` and gains `keep_emote_on_move = 14`; the file is deliberately not a byte copy of protocol `main`, which lacks 13). `impl From<&UserProfile> for AvatarShape` sets the new field to `None`. The NPC velocity source (`npc_dynamics.rs`) and the headless build are untouched.

Verification (to run before opening; write what was observed, not what is expected): native build with the test scene at `4,25`, NPC **B** keeps the dance emote across the Transform jump and the 6 s tween while NPC **A** cancels and walks as today; after the emote ends **B** walks/runs for the rest of the tween. Console check without an SDK build: `/set_component <entity> AvatarShape {"expressionTriggerId":"dance","keepEmoteOnMove":true}` then move the entity from the scene and `/inspect_component <entity> AvatarShape`. Test scene: https://github.com/decentraland/sdk7-test-scenes/tree/main/scenes/4,25-avatar-shape-keep-emote. SDK: decentraland/js-sdk-toolchain#N. Unity: decentraland/unity-explorer#N. Godot: decentraland/godot-explorer#N.
