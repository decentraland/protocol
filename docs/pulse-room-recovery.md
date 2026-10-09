# Pulse room recovery backend contract

This additive contract extends `PeerClusterChange` in `pulse_clusters.proto`. Released fields
1–5 retain their names, numbers and meaning; field 6 is `RoomRecoveryPlan room_recovery`.
The existing change, periodic hint and positive assignment lookup subjects continue to carry
`PeerClusterChange`. Positive lookup keeps its raw 42-byte authenticated session selector.

## Authority and field semantics

| Message / field | Meaning |
| --- | --- |
| `RoomRecoveryPlan.epoch` (1) | Random Pulse lifetime identity. State loss creates a new epoch, initially blocked pending controlled old-room reset. |
| `revision` (2) | Positive canonical decimal uint64 revision string. Keeping it as a string avoids JavaScript precision loss. |
| `admission` (3) | `UNSPECIFIED=0`, `PENDING=1`, `READY=2`. Only explicit `READY` can permit credentials. Unknown enum values fail closed. |
| `cleanup_only` (4) | Retained departure record; never permits credentials, even with `READY`. The envelope retains its last valid session selector for cleanup lookup. |
| `operations` (5) | All unfinished removals/revocations, including earlier transitions. Each operation has a stable ID and exact cluster/room identity. |
| `token_not_before` (6) | Confirmed whole Unix-second cutoff that island-token `nbf` must satisfy. |
| `bootstrap_required` (7) | Blocks credentials until an operator confirms controlled room reset for this exact epoch. |
| `RoomCleanupOperation` | `operation_id=1`, `cluster_id=2`, `minimum_revoke_before=3` (whole Unix seconds). A takeover adds fresh work; a hint does not. |
| `RoomCleanupCompleted` | `epoch=1`, `revision=2`, `operation_id=3`, `cluster_id=4`, `revoke_before=5` (effective whole Unix-second cutoff), `observed_ready=6` (retirement observation, default false). |
| `RoomRecoveryBootstrapCompleted` | `epoch=1`; confirms only the current blocked epoch. |

Missing plans, empty epoch/revision, malformed or unknown state, pending operations,
cleanup-only records and bootstrap-required plans do not authorize minting. Gatekeeper must
positively re-read the exact current plan after reporting completion and before every island
credential path. Pulse rechecks live session registration when serving admission authority.
All cutoff consumers validate nonnegative safe integers; generated TS uses `number` for uint64
and rejects decoded values above `Number.MAX_SAFE_INTEGER`. Revisions do not use that conversion.

Pulse owns retained operations independently of the event outbox. It records a completion only
when epoch, revision, operation ID and cluster all match current work and the cutoff satisfies
the operation minimum. Repeated or obsolete completion must not clear newer work. Every rented
protobuf publication must replace or clear `room_recovery`; shared snapshots must not expose
mutable message instances to subsequent outbox reuse.

Completed departure tombstones and Gatekeeper's confirmed cleanup receipts have no TTL-based
garbage collection. A delayed old acknowledgement must not permit a lower token floor after a
new destructive retry has established a higher cutoff. Ordinary operation completions set
`observed_ready=false` and require nonempty operation/cluster IDs and a positive cutoff. A
retirement observation sets `observed_ready=true`, requires nonempty exact epoch/revision and
empty operation/cluster IDs with cutoff zero. Cross-purpose fields are malformed and rejected.

Gatekeeper may send a retirement observation only after positively reading a cleanup-only
`READY` plan with zero operations and no bootstrap barrier, finding no dispatched journal rows,
retiring only confirmed receipts, and re-reading that exact current ready revision. Pulse retains
the completed tombstone until this exact observation arrives and its clock passes the confirmed
cutoff plus a 15-second grace. That grace covers at most five seconds of Gatekeeper token
backdating and ten seconds of Pulse/Gatekeeper clock difference; both clocks must remain within
five seconds of the same Cloud time. Stale revision/epoch observations and malformed observations cannot retire state.
This observation uses the existing completion subject, not a client delivery acknowledgement.

## Subjects and compatibility boundary

Gatekeeper publishes completions on `peer.{wallet}.room_cleanup_completed`; Pulse subscribes.
An operator publishes `RoomRecoveryBootstrapCompleted` on
`pulse.room_recovery.bootstrap_completed` after a controlled old-room reset. Broker permissions
must restrict cleanup-completion publishing to Gatekeeper and bootstrap-confirmation publishing
to the operator identity. Clients and Connector receive neither permission. Pulse remains the
only assignment/recovery authority. Subject naming alone is not publisher authentication.

This is wire-compatible with existing readers, which skip field 6. Those readers do not enforce
the admission barrier, so mixed old Gatekeeper/new Pulse operation is unsafe: activation requires
the coordinated backend pair and controlled no-admission bootstrap. Explorer's island wire and
ordinary metadata stay unchanged. The connector forwards renewed same-room credentials.
There is no new client proof, request/reply chain, delivery acknowledgement or automatic bootstrap.

## Generation and local evidence

Baseline: protocol `d7ddc105fe14480f053ae4ad5bcefc375054dd67`, branch
`feat/pulse-room-recovery`. Schemas are the source of truth. Normal public-entry-point generation
uses protoc 22.2 and `@dcl/ts-proto` 1.154.0 with existing options:

```text
--dcl_ts_proto_opt=esModuleInterop=true,returnObservable=false,outputServices=generic-definitions,fileSuffix=.gen,oneof=unions
```

Generate every `public/*.proto` with the existing `scripts/test.sh` pipeline (or its equivalent
Windows `scripts/generate-room-recovery.ps1` invocation), then `tsc -p tsconfig.json`. The Windows
script follows the same generated-directory cleanup and holds the required verification mutex.
`public/comms.proto` already imports
`pulse_clusters.proto`; generated exports resolve at
`@dcl/protocol/out-js/decentraland/pulse/pulse_clusters.gen`. Ignored `out-ts`, `out-js` and `out-cs`
outputs are generated, not edited. The Pulse consumer regenerates only `PulseClusters.cs` from
this schema with `--csharp_out`; other pre-existing generated consumer files are preserved.

Exact SHA256 values for this local candidate:

| File | SHA256 |
| --- | --- |
| `pulse_clusters.proto` | `ab7dfcaafec3afd6e53b565cfca71e3874e316ea29ba098821848549f756b26a` |
| generated `pulse_clusters.gen.ts` | `c4ab97045e8b558a3e7f3c44280d3e30994e18ce052e62af8d1bff48ec9b4b3a` |
| generated `pulse_clusters.gen.js` | `90302e0ac2b0252378774e3c742b48406f1788dfb1cc8ed213d8b1175f1b33ad` |
| Pulse `PulseClusters.cs` | `006599623d7ee49c5a4adb4dd45b15abfec8de2e181d48986943b64dcea27a01` |
| local `dcl-protocol-1.0.0.tgz` | `992db9fbda0c4ab387b92c378cc6d14b35fa7c9ddb729d70a2e8e69c4e8da36b` |

The normal full npm package is 729,793 bytes (7,946,598 unpacked); npm integrity is
`sha512-BdeXJhG4HMvkK3RaiSETwfnilKaYGyWVm9lqU3W6P3YON0mJefv2kYjM/Yy7Y0E+K7qJVgphFecXudX5k9nLug==`.
Package version `1.0.0` describes this historical local archive, not a registry release.
For the reviewable consumer PR, [CI run 37907573378](https://github.com/decentraland/protocol/actions/runs/37907573378)
published `1.0.0-37907573378.commit-c4acba0` from merge commit
`c4acba0921073fd71006e953b5cc4efce91497cd` (PR head `1e8a96749eb7696cd0ad173e0da615859b8589b9`).
Gatekeeper pins that exact CDN artifact in its package manifest and lockfile, with archive SHA256
`c2d21ff388e51ab753ac1381ef8991356d852c88840e01dcd5097b1650549f11`.
The published schema matches after checkout line-ending normalization; generated TS/JS and
declarations match the tested outputs. The different archive hash reflects the published version
and packaging. This CI prerelease is not available under that version in the npm registry.

Validation commands (serialize expensive work with `Local\DCL_It2_HeavyVerification`, same-process
`WaitOne(0)`, at least 5 GB free RAM, Node heap 2048 MB):

```text
node_modules/.bin/tsc -p tsconfig.json
node_modules/.bin/buf lint proto
node_modules/.bin/buf build proto
node_modules/.bin/buf breaking proto --against '.git#ref=d7ddc105fe14480f053ae4ad5bcefc375054dd67,subdir=proto'
node --test scripts/room-recovery.test.cjs
npm pack --pack-destination <local-validation-directory>
# Windows generation / optional scoped C# / packaging:
powershell -File scripts/generate-room-recovery.ps1 -PackDirectory <local-validation-directory> -PulseGeneratedDirectory <Pulse/src/Protocol/Generated>
```

All five checks passed locally. Nine wire tests cover unchanged legacy golden bytes, defaults,
unknown states/fields, old readers, full plans, departure/bootstrap flags, completions and integer
boundaries and the additive retirement-observation default. Reproduce the package from matching
inputs and verify hashes before using it.
Two local `npm pack` runs over the same generated inputs produced the identical archive hash;
this records observed local reproducibility, not a cross-platform deterministic-byte guarantee.
Production remains gated on promoting the dependency to the reviewed main-release artifact,
consumer install validation, Cloud revocation acceptance, broker ACLs and coordinated bootstrap.
