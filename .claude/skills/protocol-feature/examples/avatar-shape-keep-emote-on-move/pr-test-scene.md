<!-- Title: feat: AvatarShape keepEmoteOnMove test scene at 4,25 · Branch: feat/avatar-shape-keep-emote-on-move · Base: main
     Plan-mode draft: the "Passed" line lists commands to run; replace it with real results before opening. -->

## What this adds

An AvatarShape `keepEmoteOnMove` test scene at **4,25** (`scenes/4,25-avatar-shape-keep-emote`). It shows two NPCs, **A: default** and **B: keepEmoteOnMove**, and four click cubes (**Play emote**, **Move (Transform)**, **Move (Tween)**, **Replay while moving**) so QA can check on every explorer that B keeps its emote while the scene moves it and A keeps today's behaviour. Each cube prints its action to the console.

## QA: open the scene

**Use the Explorer build from decentraland/unity-explorer#N** (godot: decentraland/godot-explorer#N; bevy: decentraland/bevy-explorer#N). A released client may not support this field yet: on those, B behaves like A.

After the **Deploy scenes/4,25-avatar-shape-keep-emote** check succeeds, connect that build with:

```text
--dclenv zone --realm sdk7testscenes.dcl.eth --position 4,25
```

[Jump-in link](https://decentraland.zone/jump/?dclenv=zone&realm=sdk7testscenes.dcl.eth&position=4,25). If using MetaMask, use SEPOLIA. Mobile: `https://mobile.dclexplorer.com/open?realm=sdk7testscenes.dcl.eth&position=4,25`.

## QA: what to check

| Control | Expected result |
| --- | --- |
| **Play emote** | both NPCs start the dance emote in place |
| **Move (Transform)** right after | **B** slides to the new spot still dancing for the whole emote; **A** does what the client did before this feature (walks/runs on bevy; record it on Unity and mobile) |
| **Play emote** then **Move (Tween)** | **B** dances along the 6 s tween, no walk/run frames; after the emote ends it walks/runs (Unity, bevy) or idles (mobile) for the rest of the path |
| **Replay while moving** | **B** restarts the emote mid-travel and keeps it |
| **Move (Transform)** with no emote playing | both NPCs behave exactly as before this feature |
| Leave and re-enter the scene | still works; for failures, report the control, the client and a screenshot |

What visual checks cannot prove: that the explorer read the field rather than happening to keep the emote (Unity's animator and mobile may already keep it); compare A and B side by side on each client.

## Validation and dependencies

- Passed (to run): `npm install`, `npm run build`, `npx tsc --noEmit`, root `npm run check-parcels` (`✅ No collisions found`; 4,19-4,24 are the neighbouring avatar scenes), and `git diff --check`.
- SDK pinned to the decentraland/js-sdk-toolchain#N tarballs (`@dcl/sdk` and `@dcl/js-runtime` from its bot comment); protocol decentraland/protocol#N. Replace this temporary bridge with a published `@dcl/sdk` (or `@next`) before merging (`TEST_SCENE_PIN=published`).
- Merge the protocol/Explorer feature before this scene.
