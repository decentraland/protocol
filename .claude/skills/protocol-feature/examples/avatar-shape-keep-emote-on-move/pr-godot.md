<!-- Title: feat: AvatarShape keep_emote_on_move · Branch: feat/avatar-shape-keep-emote-on-move · Base: main
     Plan-mode draft per REVIEW.md §4 / pr-description skill: Expected and Regression lines are the boxes; no tables; deeplinks only. -->

## What
Scenes can mark an NPC with `keepEmoteOnMove` so its emote keeps playing while the scene moves it. On mobile a moved NPC already keeps its emote (no walk/run is inferred for scene-driven motion), so this PR bumps the protocol pin, reads the new field into the avatar, and changes nothing a player can see.

## Why
Protocol decentraland/protocol#N adds `keep_emote_on_move` to `PBAvatarShape`; Unity (decentraland/unity-explorer#N) and bevy (decentraland/bevy-explorer#N) use it to stop blending walk/run over the emote. Mobile never animated locomotion for a Transform/Tween-moved AvatarShape, so `true` is already our behaviour; wiring the flag now keeps it that way once locomotion inference lands (issue #N, `need tech test`). This PR deliberately does NOT add locomotion for moved NPCs, so `false` still shows the idle slide it shows today.

- [ ] Heads-up to post in #ext-foundation before merge — the protocol pin moves from `0ff6038` to the `@next` build (brings AvatarNametag, ExplorerUiEventsResult, ExplorerItemPurchaseResult and `font_src` schemas; no behaviour change until their features ship)

Closes #N

## Details
<details>
<summary>Expand</summary>

- `src/install_dependency.rs`: `PROTOCOL_FIXED_VERSION_URL` bumped to <tarball while the protocol PR is open | npm url of the `next` build>; exhaustive literals the bump breaks fixed with `..Default::default()`; `lib/build.rs` proto patches become no-ops (the pin now ships `EmoteState` and the rfc4 fields).
- `lib/src/scene_runner/components/avatar_shape.rs`: `update_avatar_shape` forwards `keep_emote_on_move` (default `false`) in the `avatar_shape_config` dictionary handed to `async_update_avatar`; itest covers the put/read.
- `godot/src/decentraland_components/avatar/avatar_anim_helpers.gd`: static reader for the config key (keeps `avatar.gd` under the gdlint line cap); `avatar.gd` stores it and passes `self_idle or keep_emote_on_move` to `emote_controller.process`, which is a no-op today because `self_idle` is always true for an AvatarShape.
- [ ] To verify before opening: `cd lib && cargo fmt --all && cargo clippy -- -D warnings`; `cargo run -- build`; `cargo run -- run --itest`; `gdformat godot/ && gdlint godot/`; device run of the test plan (tick each only after it ran).

</details>

## Test plan

**Setup:** open [this link](https://mobile.dclexplorer.com/open?realm=sdk7testscenes.dcl.eth&position=4,25) (`https://mobile.dclexplorer.com/open?realm=sdk7testscenes.dcl.eth&position=4,25`). The scene shows two NPCs, **A: default** and **B: keepEmoteOnMove**, and four cubes: **Play emote**, **Move (Transform)**, **Move (Tween)**, **Replay while moving**.

**1. Flagged NPC keeps its emote while moved**
1. Open the link above.
2. Tap **Play emote**, then **Move (Transform)**.
   - [ ] **Expected:** **B** slides to its new spot still performing the dance for the whole emote, then stands idle.
3. Tap **Play emote**, then **Move (Tween)**.
   - [ ] **Expected:** **B** keeps dancing along the 6 s path; when the emote ends it stands idle while it finishes sliding (no walk/run on mobile).

**2. Unset case unchanged**
1. Open the link above, tap **Play emote**, then **Move (Transform)**.
   - [ ] **Expected:** **A** behaves exactly as on the current release: it slides with the emote still playing (today's mobile behaviour; record a video if it differs).

**Regression:** emotes on your own avatar share `avatar_emote_controller.gd`.
- [ ] **Regression — own avatar emotes:** play an emote from the wheel and walk with the joystick: the emote stops as before.
- [ ] **Regression — scene emotes on NPCs:** in scene `4,22` the NPCs still play their scene emotes.
