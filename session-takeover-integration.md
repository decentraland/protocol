# Session takeover protocol integration

## Contract

Package: `decentraland.kernel.comms.v3`, source `proto/decentraland/kernel/comms/v3/archipelago.proto`.

| Declaration | Wire numbers |
| --- | --- |
| KickedReason | KR_NEW_SESSION=0 (unchanged), KR_BANNED=1 |
| SessionStatus | UNSPECIFIED=0, TAKEOVER_PENDING=1, TAKEOVER_FAILED=2 |
| SessionStatusMessage | state=1 (SessionStatus), retry_after_ms=2 (uint32) |
| ServerPacket.message | session_status=7; existing tags 1–6 unchanged |

TypeScript imports:

```ts
import { ServerPacket, SessionStatus, SessionStatusMessage, KickedMessage, KickedReason }
  from '@dcl/protocol/out-js/decentraland/kernel/comms/v3/archipelago.gen'

const status = { state: SessionStatus.TAKEOVER_PENDING, retryAfterMs: 1500 }
const natsBytes = SessionStatusMessage.encode(status).finish()
const socketBytes = ServerPacket.encode({
  message: { $case: 'sessionStatus', sessionStatus: status }
}).finish()
```

Gatekeeper publishes bare status to `engine.peer.<wallet>.session_status.<session>` and bare
KickedMessage to `engine.peer.<wallet>.kicked.<session>`. Connector authenticates and targets
exact wallet/session, supplies the envelope, and keeps pending sockets open. Success is the existing
island_changed. Control events bypass assignment deduplication. No wallet-only control fallback.

Pending suppresses recovery for at least retryAfterMs; expiration is not permission to handshake.
Failure withholds credentials and requires user retry. KR_NEW_SESSION means authoritative logical
session supersession, not replacing another socket for the same session. Same-session socket
replacement must close only the old transport or await a separately approved reason. Unknown kick
reasons stop automatic retries but are not confirmed supersession. Legacy empty KickedMessage still
means KR_NEW_SESSION. Unknown binary enum numbers remain numbers in the generated JS decoder;
JSON conversions may map them to UNRECOGNIZED. Consumers must use an explicit switch/default.

## Reproduce artifacts on Windows

From this worktree, install dependencies with the shared heavy-verification mutex and RAM guard.
Use Node 24, protoc 22.2 (package config), @dcl/ts-proto 1.154.0, protobufjs 7.2.4, and Buf 1.8.0.
Provide the Windows Buf 1.8.0 binary at `node_modules/.bin/buf` (the existing local install has it).
Then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-session-artifacts.ps1
```

The script acquires the mutex nonblocking (exit 75 means retry later), runs Buf checks, generates all
public TS entrypoints, compiles JS, generates Archipelago.gen.cs directly with protoc, runs the wire
and bitwise goldens, and packs a local archive. Outputs:

- `out-session-takeover/dcl-protocol-1.0.0.tgz`
- `out-session-takeover/Archipelago.gen.cs`
- Reusable goldens: `test/fixtures/session-control.json` (hex bytes and canonical JSON).

No registry version is reserved: the archive's 1.0.0 is the repository's development version, not a
new published stable release. Identify it by source commit and SHA256. Consumer owners may install
the absolute archive locally with `npm install --no-save --package-lock=false <archive>` (under the
same mutex) in their isolated candidate. Keep temporary local paths out of committed manifests and
locks. Verify the installed generated exports before testing. Do not broaden unrelated dependency
pins or social-service's isolated alias.

For Unity, copy the generated Archipelago.gen.cs to the existing generated protocol location after
checking local changes; keep its existing .meta file. It uses the existing Google.Protobuf runtime and
Vectors generated definitions. No handwritten parallel protocol classes are needed.

## CI and release gates

Linux reproduction after installing dependencies: `make buf-breaking`, `make test`,
`npm run gen:test`, `npm pack`; direct C# regeneration uses protoc 22.2 with
`--csharp_out=<output> --csharp_opt=file_extension=.gen.cs -I=proto
proto/decentraland/kernel/comms/v3/archipelago.proto`.

Before publication, CI needs either an approved immutable artifact upload keyed to the reviewed
protocol commit and SHA256, or a checkout/build of that exact protocol commit followed by a local
archive install. Local filesystem paths cannot serve as remote CI pins. This pass does not upload or
publish. Stable publication and coordinated consumer lock updates require separate approval.

Required integration gates: all ban producers use KR_BANNED; same-session socket replacement does
not latch logical supersession; pending/failure reach only the winning session; authoritative kick
latches suppression before transport close; stale asynchronous callbacks cannot issue credentials or
late control events; old readers ignore status and retain parking compatibility; two-client tests
exercise lost status, reconnect replay, timeout/watchdog, and late assignment after supersession.
LiveKit Cloud revocation/removal and next-second cutoff behavior require actual Cloud evidence;
protocol goldens do not establish that gate.
