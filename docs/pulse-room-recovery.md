# Retained takeover protocol

Pulse retains unfinished takeover cleanup in existing assignment messages. Gatekeeper executes
cleanup and reports completion. One Pulse and one active Gatekeeper are assumed.

## Wire contract

| Message / field | Meaning |
| --- | --- |
| `PeerClusterChange` fields 1–5 | Existing assignment and one-shot displacement fields; unchanged |
| Reserved field 6 / `room_recovery` | Retired draft plan; never reinterpret its bytes |
| `pending_takeovers` (7) | Repeated `PendingTakeover` entries still requiring cleanup |
| Optional `token_not_before` (8) | Confirmed token `nbf` floor in whole Unix seconds |
| `PendingTakeover.takeover_id` (1) | Globally unique operation ID, stable until completion |
| `displaced_session` (2), `displaced_cluster_id` (3) | Previous owner and room to remove/revoke |
| `TakeoverCompleted.takeover_id` (1) | Exact pending operation being confirmed |
| `TakeoverCompleted.revoke_before` (2) | Effective confirmed whole-second revocation cutoff |

Present `token_not_before=0` represents a supported first assignment. Absence cannot authorize
credentials. Gatekeeper requires a valid current assignment, a present safe-integer floor and
an empty pending list before issuing credentials. Old readers skip the new fields and do not
enforce this barrier; activate the matching backend pair together.

All timestamps must be nonnegative JavaScript-safe integers. Completion cutoffs must be
positive and exceed the pending operation's prior token floor. Pulse removes only the matching
ID for that wallet, applies the maximum confirmed floor and ignores duplicate/unknown IDs.
A newer admitted takeover has a different ID even if the room and sessions repeat.

## Communication and ownership

Change events, periodic `peer.{wallet}.cluster_snapshot` hints and positive
`peer.{wallet}.cluster_assignment` replies all use `PeerClusterChange`. The assignment request
still carries the authenticated session selector. Hints trigger a fresh lookup before action.

Gatekeeper publishes the only new NATS event, `TakeoverCompleted`, on
`peer.{wallet}.takeover_completed`. Restrict publishing to Gatekeeper through broker ACLs.
Pulse owns retained pending state; publishing an event does not clear it.

Gatekeeper caches confirmed results in memory and re-reports them after lost completions.
It positively reads the current assignment after completion: an empty pending list permits
issuance; successful NATS publication alone does not. Repeated hints must not remove the
replacement participant. Never-admitted intermediate owners do not replace earlier cleanup.

## Scope

There is no plan epoch, revision, admission enum, bootstrap event, cleanup-only record or
retirement-observation exchange. Uncertain LiveKit calls block the affected wallet in the
running Gatekeeper. Crash-safe execution, recovery after lost Pulse state and general room
movement/departure cleanup are outside this narrower contract.

The previous draft artifact used field 6 and different completion subjects. Reserving that
field makes it fail closed for the new consumer; the two drafts are not interoperable.
Explorer's wire format and metadata stay unchanged. Connector must forward refreshed credentials
for the same room. See the [implementation plan](https://github.com/decentraland/Pulse/blob/fix/pulse-owned-room-recovery/docs/demand-driven-recovery-protocol-plan.md)
for behavior, limits and rollout.

## Generation and validation

The schema is the source of truth. Use the existing `scripts/test.sh` generation pipeline or
the Windows `scripts/generate-room-recovery.ps1` equivalent. Generate only `PulseClusters.cs`
into Pulse; preserve unrelated generated files.

`node --test scripts/room-recovery.test.cjs` verifies legacy golden bytes, optional-field
presence, takeover/completion round trips, old-reader behavior, retired draft bytes and
timestamp bounds. Run normal schema lint/build/compatibility checks as well.

Consumer artifact provenance belongs in Gatekeeper's `docs/protocol-dependency.md`; pin the
exact reviewed CI artifact and verify its schema before consumer testing. Promote it to the
normal reviewed release before production activation.
