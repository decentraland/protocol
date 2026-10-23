# Evals for the protocol-feature skills

`evals.json` holds eight hypothetical scenarios in the skill-creator format. They are dry runs: every scenario must end with a bundle of markdown and nothing else (no PR, issue, commit, branch or sibling-repo edit).

## How to run one scenario

1. Pick a workspace outside the repo and point the bundle directory at it: `export PROTOCOL_FEATURE_OUT=/tmp/protocol-evals/<id>/` (the skills honour it instead of `proposals/`). Set `DCL_REPOS_ROOT` if the sibling repos are not next to this one or under the user's `Projects/decentraland` folder.
2. Start a fresh session in the protocol repo (`claude`), paste the scenario's `prompt`, and let it run. For the resume scenario, first copy `evals/fixtures/avatar-shape-keep-emote-on-move/` into the workspace as `proposals/avatar-shape-keep-emote-on-move/`.
3. Grade with the `expectations` list: each is checked against the bundle files and the transcript (commands run), not against keywords in the reply. The last expectation of every scenario fails the run on any outward action.
4. A baseline run (same prompt, skills removed or `disable-model-invocation` on all of them) shows what the skills add.

Keep workspaces out of the repo; commit only fixtures and the reference example under `examples/`.

## Trigger accuracy of the router description

`trigger-eval.json` holds 20 realistic queries (10 should invoke the skill, 10 near-misses should not). `trigger-test.py` runs each one through `claude -p` in this repo and reports whether `protocol-feature` was the first tool call:

```bash
python3 .claude/skills/protocol-feature/evals/trigger-test.py \
  .claude/skills/protocol-feature/evals/trigger-eval.json "$PWD" 2 4 /tmp/trigger-results.json
```

Measured on 2026-10-10: 19/20 with the previous description (every negative silent in 30 runs; one positive, the "is id 1223 free" question, missed), and that query triggers 3/3 after the "or check whether one is free" clause was added, with the controls unchanged. Re-run after editing the description; the near-misses (a godot UI bug, a godot PR description, Pulse quantization, scene code using AvatarShape, `buf lint` on social_service, the bevy HUD, a catalyst ADR, SDK CRDT internals, the bitwise plugin) are the ones that must stay silent.
