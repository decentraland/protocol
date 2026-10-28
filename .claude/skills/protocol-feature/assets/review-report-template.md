# Review: <title> (<slug>) — <date>

Scope: protocol PR #<n> (<branch>) against js-sdk-toolchain #<n>, unity-explorer #<n>, bevy-explorer #<n>, godot-explorer #<n>. Merge gate in force: `<policy.merge_gate>`.

## Alignment matrix

| Check | protocol | sdk | unity | bevy | godot | Result |
|---|---|---|---|---|---|---|
| component id / field numbers | | | | | | |
| `optional` on new fields | | | | | | |
| grow-only parity (SDK `GROWN_ONLY_COMPONENTS` · godot `GROW_ONLY_SET_COMPONENTS` · bevy `add_crdt_go_component` · unity `AsProtobufResult`) | | | | | | |
| defaults in proto comments == engine code == SDK helpers | | | | | | |
| vendored / generated copy matches the merged proto | n/a | api.md regenerated | `.gen.cs` regenerated | byte-equal | pin contains the commit | |
| public index line present | | n/a | n/a | n/a | n/a | |

## Findings

### P0 (blocks merge)
- 

### P1 (should fix before merge)
- 

### P2 (minor)
- 

## Pins before merge
- sdk: both `package.json` files pin a published build (no http/file)
- unity: `scripts/package.json`, lockfile and `.gen.cs` agree on a published build
- godot: `PROTOCOL_FIXED_VERSION_URL` is an npm URL
- test scene: pinned per `policy.test_scene_pin`

## Merge-order readiness
- [ ] protocol
- [ ] sdk
- [ ] unity
- [ ] bevy
- [ ] godot
- [ ] test scene

## Follow-ups
- docs:
- sdk-skills:
- adr (Draft -> Living):
- non-gating engines / parity issues:
