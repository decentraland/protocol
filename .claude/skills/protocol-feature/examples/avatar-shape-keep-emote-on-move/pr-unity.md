<!-- Title: feat: sdk | AvatarShape keepEmoteOnMove · Branch: feat/avatar-shape-keep-emote-on-move · Base: dev
     Plan-mode draft: checklist items stay unticked until they ran. -->

# Pull Request Description

## What does this PR change?

Implements decentraland/protocol#N for `PBAvatarShape`: when a scene sets `keepEmoteOnMove: true` on an NPC and moves it with a Transform write or a Tween, the emote started by `expressionTriggerId` keeps playing for its full length while the NPC translates; no walk/run is blended in until the emote ends, then locomotion resumes from the NPC's speed as today. Unset / `false` keeps today's behaviour.

Not included: any change to the unset path. On `dev` the `Emote` and `Emote Loop` -> `Movement` transitions on `MovementBlend > 0.1` in `CharacterAnimator.controller` are muted, so a moved NPC may already keep its emote and slide; this PR does not unmute them. Whether `false` should cancel NPC emotes on movement (parity with bevy and with the docs) is a separate decision: <link once decided>.

- `scripts/package.json` pins `@dcl/protocol` to <the PR tarball | `1.0.0-<runId>.commit-<sha7>`>; `AvatarShape.gen.cs` regenerated with `npm run build-protocol`; repin to `@next` once the protocol PR merges.
- `SDKAvatarShapesMotionSystem.UpdateAnimations` reads the flag from the global-world `PBAvatarShape` twin (presence resolved at read time, never written back) and keeps `MovementBlend` at 0 while the flag is set and the avatar's `CharacterEmoteComponent` reports a playing emote; position and rotation interpolation are untouched, so the NPC still moves and faces its travel direction.
- EditMode test `Explorer/Assets/DCL/Character/CharacterMotion/Tests/SDKAvatarShapesMotionSystemShould.cs` covers: flag + emote playing -> blend 0; flag + no emote -> blend from speed; no flag -> blend from speed.

Test scene: decentraland/sdk7-test-scenes#N (`scenes/4,25-avatar-shape-keep-emote`). SDK side: decentraland/js-sdk-toolchain#N. Bevy: decentraland/bevy-explorer#N. Godot: decentraland/godot-explorer#N.

## Test Instructions

**Steps (standard run)**:
```bash
metaforge explorer run XXXX  # ← replace with this PR number
```

Launch with `--dclenv zone --realm sdk7testscenes.dcl.eth --position 4,25` (already on zone: `/goto sdk7testscenes.dcl.eth/4,25`). MetaMask users: select SEPOLIA.

### QA TEST STEPS

Use the build from this PR to enter the ZONE/SEPOLIA world `sdk7testscenes.dcl.eth` at position `4,25` and confirm that NPC **B** ("keepEmoteOnMove") keeps dancing while it travels, and NPC **A** ("default") behaves as before.

| Click / do | Expected |
| --- | --- |
| **Play emote** | both NPCs start the dance emote in place |
| **Move (Transform)** right after | **B** slides to the new spot still dancing for the whole emote, then stands idle (or walks if moved again); **A**: record what it does (today's behaviour; if it keeps dancing and slides, note it, that is the muted-transition baseline) |
| **Play emote**, then **Move (Tween)** | **B** dances along the 6 s tween without walk/run frames; after the emote ends it walks/runs for the rest of the tween |
| **Replay while moving** | **B** restarts the emote mid-travel and keeps it |
| Regression: **A** moved without an emote | walks/runs to the target exactly as on `dev` |
| Regression: your own avatar | pressing a movement key still cancels your emote |

(the test scene can also be run locally: https://github.com/decentraland/sdk7-test-scenes/tree/main/scenes/4,25-avatar-shape-keep-emote)

## Quality Checklist
- [ ] Changes have been tested locally
- [ ] Documentation has been updated (if required) — docs decentraland/docs#N (draft)
- [ ] Performance impact has been considered (one extra component read per NPC per frame)
- [ ] For SDK features: Test scene is included (decentraland/sdk7-test-scenes#N)
