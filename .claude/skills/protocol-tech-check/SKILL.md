---
name: protocol-tech-check
description: Phase 3 of a Decentraland protocol proposal: grades unity-explorer, bevy-explorer, godot-explorer and js-sdk-toolchain as already-supported / feasible / uncertain / blocked with schema, consumer and runtime evidence. Invoke with /protocol-tech-check <proposals/<slug> | component or field>; protocol-feature routes here automatically.
argument-hint: "[proposals/<slug> | <PbComponent or field>] [--engines unity,bevy,godot] [--runtime]"
disable-model-invocation: true
---

# Phase 3: technology verification

Answer three questions per engine, with evidence: does it have the schema, does anything consume it, and where would the new behaviour hook in. Then state what each engine does today, because the proposal's default must reproduce that. The output is `## 3. Technology verification` of `proposal.md`: a matrix, a branch-drift line, the cross-engine mismatches to decide, and a runtime plan.

Paths are relative to the protocol repo root. Read `.claude/skills/protocol-feature/references/subsystems.md` for the hook table and the mismatch list of the area, and the engine's `references/repos/<engine>.md` for how it consumes the protocol.

## 1. Entry

- Bundle from the router or the arguments. A bare question (no bundle) creates a stub bundle at phase 3 (earlier gates `waived` by the user with the reason "standalone entry") so the matrix is kept.
- `bash .claude/skills/protocol-feature/scripts/proposal-gate.sh <proposal.md> 3` prints `OK`.
- Freshness: read `origin/main` (unity-explorer `origin/dev`) with `git show` / `git grep`, never a working tree you have not checked, and name the branch and sha in the matrix. Run `scripts/find-repos.sh --fetch` first when FETCH_HEAD is older than a day.

## 2. Evidence ladder

Run `bash .claude/skills/protocol-feature/scripts/engine-support.sh <PbName> [--field <snake>]` and read its output as two layers:

- **L0 schema**: does the engine's copy of the protocol contain the message / field, and which protocol branch or pin it comes from. sdk: exact pins in two `package.json` files; unity: `scripts/package.json` pin and `Explorer/Assets/Protocol/DecentralandProtocol/<Name>.gen.cs`; bevy: vendored `crates/dcl_component/src/proto/...` diffed against `origin/main` and `origin/experimental-bevy`; godot: `PROTOCOL_FIXED_VERSION_URL` commit vs the proto's introducing commit, plus `GROW_ONLY_SET_COMPONENTS`. Missing L0 means "feasible, needs a pin or vendor bump", never blocked.
- **L1 consumers**: grep hits outside generated directories, plus registration hits (unity `ComponentsContainer.cs`, bevy `add_crdt_lww_component::<PbX` / `reg!(`, godot `update_<name>`, sdk `GROWN_ONLY_COMPONENTS` / `extended/`). Zero hits with L0 present is `SCHEMA-ONLY`: the type exists and nothing reads it (Unity's 1218, 1219, 1222; `PBAvatarShape.talking`).
- **Hook**: the `path:symbol` from `subsystems.md` where the behaviour would change; confirm it still exists with `git grep -n '<symbol>' origin/<branch> -- <path>`. Name the system that owns the behaviour (unity `Explorer/Assets/DCL/SDKComponents/<Feature>/Systems/*System.cs` or the global-world system, bevy the `update_world/*.rs` or `crates/<area>/src/*.rs` system, godot `lib/src/scene_runner/components/<name>.rs` plus the GDScript node), and only then the helpers it calls. A row with no confirmed hook is `uncertain`. Line numbers: only `~N` for lines you printed in this run; never from a reference file.
- **Baseline**: what the engine does today for this exact case, from the code you read (for AvatarShape movement: unity `SDKAvatarShapesMotionSystem.UpdateAnimations` drives `MovementBlend`, while on `origin/dev` the animator's `Emote -> Movement` exit on `MovementBlend > 0.1` is muted for both `Emote` and `Emote Loop`, so the emote's fate is unconfirmed; bevy `animate.rs` `velocity_cancels`; godot `dcl_avatar.rs` ExternalController, nothing sets walk/jog/run for AvatarShape).
- **L2 runtime**: observed behaviour, or `pending` with a plan (section 4). Required for `already-supported`.

## 3. Verdicts and effort

| Verdict | Meaning |
|---|---|
| `already-supported` | L1 consumer exists **and** L2 observed behaviour equals the proposal for default and non-default values |
| `feasible` | schema present or obtainable, hook confirmed, bounded file list; note "needs pin/vendor bump" when L0 is missing |
| `uncertain` | hook not found, code paths disagree, platform split (bevy headless runs no animation; unity legacy-animation emotes bypass Mecanim; godot masked emotes survive movement), or behaviour inferred from code only. Name the file or the scene that would resolve it; for godot, the `need tech test` issue to file |
| `blocked` | missing subsystem (Unity has no `~system/Testing` screenshot implementation) or needs a comms / RFC change out of scope |
| `n/a` | the engine lacks the feature class |

Effort S/M/L with a precedent PR (`references/repos/<engine>.md` lists them). Also fill the **branch drift** line (which protocol branch each engine would receive the change from: unity `@next`, sdk exact pin, godot pin commit, bevy `origin/experimental-bevy`) and the **cross-engine mismatches** list for the area, copied from `subsystems.md` and extended with what you found.

## 4. Runtime plan (L2)

Written in plan mode, executed in execute mode or by a human:

- Scene: sdk7-test-scenes `scenes/<x>,<y>-<slug>` on a free parcel (`ls scenes/` on `origin/main`, then `npm run check-parcels` at the repo root prints `No collisions found`). Avatar work starts from `scenes/4,19-avatar-shape-movement/src/index.ts`. Baseline first (field absent), then the field set; one observable per case.
- unity: `npm run start -- --explorer-alpha`, or `npm run start -- --mcp` (the Explorer's MCP server, port 8123) driven through the sdk-skills `unity-explorer-mcp` skill for screenshots and movement; otherwise a human runs `metaforge explorer run <PR>`. Agents cannot compile Unity, so this row stays `pending` until someone observes it.
- bevy: `just native-debug --realm http://127.0.0.1:8000 --preview --position x,y`; console `/set_component <entity> <PascalName> {"<camelField>":true}`, `/inspect_component`, `/debug_dump_avatar` work before any SDK build exists.
- godot: `cargo run -- run -- --preview --realm http://localhost:8000 --location x,y --skip-lobby`; phones via `https://mobile.dclexplorer.com/open?realm=...&position=...` links (the form godot's PR test plans use).
- Record `observed (who, how, date)` or `pending` per engine. scene-explorer-tests is frozen (2024) and never the gate.

## 5. Exit

- Every engine the merge gate counts (`policy.merge_gate`) is `already-supported` or `feasible`, or the user logged an exception in the Gate log as `waived`; no gating row is `blocked`. Small track: L2 may stay `pending`; log it in the Decision log.
- `status: verified` (or `blocked` when a gating engine is blocked), `phase: 4`, Gate log row 3, Decision log rows quoting `merge_gate`.
- `bash .claude/skills/protocol-feature/scripts/proposal-gate.sh <proposal.md> 4` prints `OK`.
- Show the matrix and print the next command: `/protocol-define proposals/<slug>`.

## Common mistakes

- "The field is in `.gen.cs` / the vendored proto" taken as support: it is L0 only.
- Marking `already-supported` from code reading alone: L2 is required, and the baselines of the three engines differ more often than they agree.
- Forgetting headless bevy (`NoRenderApp` runs only `AvatarCorePlugin`, no animation) or AvatarShape placed on the PLAYER entity (honoured in bevy, #1242).
- Citing a working-tree path from a stale clone without the branch and sha, or describing what a vendored proto, a `Cargo.toml` or a pin contains without having printed it in this run.
- Skipping the sdk row: a plain field is a mechanical SDK PR (spec, api.md, snapshots), but a `repeated` field or a UI prop needs hand-written code.
