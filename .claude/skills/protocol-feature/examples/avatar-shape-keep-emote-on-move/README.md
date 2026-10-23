# Example bundle: keep an AvatarShape emote playing while it moves

A complete plan-mode run of `/protocol-feature --draft` for a small feature (an `optional bool` on `PBAvatarShape`), produced on 2026-10-10 by a fresh session following the skills, with no repo edited and no PR opened. It is the reference for what each phase leaves behind:

| File | Phase |
|---|---|
| `proposal.md` | all six sections, Gate log, Decision log |
| `protocol.diff` | 4, the exact `.proto` change (field 14; 13 skipped for `force_render`) |
| `pr-protocol.md` | 4, protocol PR body in the repo's style |
| `actions.md`, `pr-sdk.md`, `pr-unity.md`, `pr-bevy.md`, `pr-godot.md`, `pr-test-scene.md`, `pr-docs.md`, `pr-sdk-skills.md` | 5, one brief and one PR body per consumer, in merge order |
| `review.md` | 6, alignment matrix, P0/P1/P2, pins, follow-ups |

Facts inside were true on that date (branch shas, pins, open PRs); regenerate them with the scripts before reusing any number. Absolute machine paths were replaced with `<protocol>`, `<repos>` and `<scratch>`.
