# Protocol definitions

This module is intended to be installed as a node_module via `npm install @dcl/protocol`.

It is recommended that every project compiles the needed files only as part of its build process. Some imports are required:

- `-I=$(pwd)/node_modules/@dcl/protocol/public`
- `-I=$(pwd)/node_modules/@dcl/protocol/proto`

An example compilation looks like this:

```bash
protoc \
  --plugin=./node_modules/.bin/protoc-gen-dcl_ts_proto \
  --dcl_ts_proto_opt=esModuleInterop=true,returnObservable=false,outputServices=generic-definitions,fileSuffix=.gen \
  --dcl_ts_proto_out="$(pwd)/out-ts" \
  -I="$(pwd)/node_modules/@dcl/protocol/public" \
  -I="$(pwd)/node_modules/@dcl/protocol/proto" \
  "$(pwd)/node_modules/@dcl/protocol/public/sdk-components.proto"
```

# Style Guidelines

1. All .proto files are snake_case.proto.
2. For pascal or camel case usage, please make a deterministic one from the snake case. Example: nft_shape will transform to NftShape.
3. See https://docs.buf.build/best-practices/style-guide. The most of other styles are taken from there, the Buf configuration is in proto/buf.yml.
4. Use public/ folder only for .proto with protocol exposing, that is only for files with `import public`. This folder is not processed by the linter.

# Dev with Decentraland Repositories

Many repositories depend on this protocol definition: [js-sdk-toolchain](https://github.com/decentraland/js-sdk-toolchain) (the SDK), [unity-explorer](https://github.com/decentraland/unity-explorer), [bevy-explorer](https://github.com/decentraland/bevy-explorer) and [godot-explorer](https://github.com/decentraland/godot-explorer) (the explorers), plus [sdk7-test-scenes](https://github.com/decentraland/sdk7-test-scenes), [docs](https://github.com/decentraland/docs) and [sdk-skills](https://github.com/decentraland/sdk-skills). Scenes deployed to the world are immutable, so whatever reaches `main` here is permanent: a field can be deprecated, never renamed, renumbered or retyped (CI runs `buf breaking` against `main` on every push to a branch).

## The feature process

Adding or changing a component, field, enum value, restricted action or scene API follows six phases: need, design, technology verification (can each explorer support it?), definition (the `.proto` change, with ids and field numbers checked across every branch, open PR and engine copy), implementation (one PR per consumer, in merge order) and review. The process, its gates and the policy values in force are documented in [`.claude/skills/protocol-feature/references/process.md`](.claude/skills/protocol-feature/references/process.md) and [`references/policy.md`](.claude/skills/protocol-feature/references/policy.md); the state of a feature lives in a proposal bundle under [`proposals/`](proposals/README.md).

With Claude Code in this repo, `/protocol-feature "<idea>"` starts a proposal and `/protocol-feature --draft "<idea>"` simulates all six phases without opening anything; `/protocol-review <PR>` reviews a protocol PR against the SDK and the three explorers.

## Merge order

> **Important Note: Avoid Merging Protocol PR Without The Consumers Validated Against It**
>
> Don't merge a protocol PR into `main` until the SDK and the explorers have validated the change end to end against the PR package, and every explorer is accounted for (an implementation PR, or a filed parity-gap issue).
>
> The order for introducing changes in the protocol is:
>
> 1. Create a PR in the Protocol repository. CI comments a `npm install "https://sdk-team-cdn.decentraland.org/@dcl/protocol/branch/..."` link.
> 2. Point the consumers at that package while developing: `js-sdk-toolchain` (both `package.json` files), `unity-explorer` (`scripts/package.json` + `npm run build-protocol`), `godot-explorer` (`PROTOCOL_FIXED_VERSION_URL`), `bevy-explorer` (copy the touched `.proto` into its vendored tree).
> 3. Once the protocol PR and the consumer PRs are ready, merge the protocol PR first; `main` publishes `@dcl/protocol@next`.
> 4. Repin every consumer to the published package (`@dcl/protocol@next` or the exact `1.0.0-<runId>.commit-<sha>` version), then merge the SDK and explorer PRs in any order, the test scene last.

Testing locally: install the PR package in a scene, or link the SDK and the protocol by path (`npm install ../protocol` in `js-sdk-toolchain`, `npm install ../../js-sdk-toolchain/packages/@dcl/sdk` from a test scene). The SDK's CI rejects URL or file dependencies on PRs to `main`, which is why the repin step cannot be skipped.

## SDK: New component or component modification

Repositories: `js-sdk-toolchain`, `unity-explorer`, `bevy-explorer`, `godot-explorer`

At the protocol level the component is one `.proto` file under `proto/decentraland/sdk/components/` with a unique `option (common.ecs_component_id)` (take the next free id with the skill's `scripts/next-component-id.sh`, which also sees open PRs and the `experimental-bevy` branch; `make check-component-id ID=xxx` only sees the local tree) and an `import public` line in `public/sdk-components.proto`. `js-sdk-toolchain` CI fails if the component has no serialization test (`test/ecs/components/<Name>.spec.ts`). Each explorer registers the component by hand; the per-engine steps are in [`.claude/skills/protocol-feature/references/repos/`](.claude/skills/protocol-feature/references/repos/).

## SDK: New APIs or APIs modifications

Repositories: `js-sdk-toolchain` and the explorers. Scene APIs are the services under `proto/decentraland/kernel/apis/`, indexed by `public/sdk-apis.proto`. The explorers wire each RPC by hand (JavaScript module, native bridge, handler), so a new parameter is a change in every explorer plus the SDK's `make compile_apis` types. Merge the protocol PR first, then the explorers, then the SDK.

## Comms

`proto/decentraland/kernel/comms/rfc4/comms.proto` (LiveKit) requires updating [ADR-104 (RFC-4)](https://adr.decentraland.org/adr/ADR-104) whenever it changes; `proto/decentraland/pulse/*` is the authoritative-server protocol and the only place the quantization options in `CLAUDE.md` apply.

---

# Bitwise Serialization Plugin (`protoc-gen-bitwise`)

A custom protoc plugin that generates C# partial classes with typed float
accessors for quantized `uint32` fields in high-frequency MMO networking
messages (position deltas, player input, etc.).  It runs alongside
`--csharp_out` in the same protoc invocation; the two output files coexist
via C# `partial class`.

## How it works

Protobuf encodes `uint32` values as varints, which are already compact for
small values: a value up to 2¹⁴−1 costs 2 bytes, up to 2²¹−1 costs 3 bytes.
Rather than a separate binary packing layer, the plugin leverages this:

1. Declare quantized fields as `uint32` in the `.proto` schema and annotate
   them with `[(decentraland.common.quantized)]` to specify the float range
   and bit resolution.
2. `--csharp_out` generates the standard protobuf class with the raw `uint32`
   property (e.g. `PositionX`).
3. `--bitwise_out` (this plugin) generates a `partial class` extension with a
   computed float accessor (e.g. `PositionXQuantized`) that encodes/decodes
   transparently via `Quantize.Encode` / `Quantize.Decode` on every access —
   the raw `uint32` property remains the single source of truth (no cache to
   go stale when the raw field is mutated directly).

The wire representation is a standard protobuf message — any protobuf-capable
client can read it without knowledge of the plugin.

## Prerequisites

| Requirement | Version |
|---|---|
| Node.js | 16+ |
| `protoc` | 3.19+ |

The plugin is a dependency-free Node script — no `npm install` or extra
packages are required to run it.

## Step 1 — Annotate your `.proto` file

Declare quantized fields as `uint32` and import `options.proto`:

```protobuf
syntax = "proto3";

import "decentraland/common/options.proto";

package decentraland.kernel.comms.v3;

message PositionDelta {
  // Float range [-100, 100] quantized to 16 bits ≈ 0.003-unit precision.
  // Stored as uint32 on the wire; protobuf encodes it as a 3-byte varint.
  uint32 dx        = 1 [(decentraland.common.quantized)  = { min: -100.0, max: 100.0, bits: 16 }];
  uint32 dy        = 2 [(decentraland.common.quantized)  = { min: -100.0, max: 100.0, bits: 16 }];
  uint32 dz        = 3 [(decentraland.common.quantized)  = { min: -100.0, max: 100.0, bits: 16 }];

  // Unannotated uint32: protobuf varint encodes small values compactly by default.
  uint32 entity_id = 4 [(decentraland.common.bit_packed) = { bits: 20 }];
}
```

### Annotation reference

| Annotation | Target type | Parameters | Effect |
|---|---|---|---|
| `[(decentraland.common.quantized)]` | `uint32` | `min`, `max`, `bits` | Plugin emits a `float {Name}Quantized` accessor and a `{Name}QuantizedStep` const |
| `[(decentraland.common.quantized_power)]` | `uint32` | `max`, `pow`, `bits` | Power-law quantizer over `[-max, max]`: `(bits-1)`-bit magnitude (high bits) + sign (LSB), decoded as `sign·max·u^pow`. Exact zero; `pow>1` gives fine resolution near zero, coarse near `±max`; sign in the LSB keeps small magnitudes one varint byte. `float {Name}Quantized` accessor (`Quantize.EncodePower`/`DecodePower`) |
| `[(decentraland.common.bit_packed)]` | `uint32` | `bits` | Documents the value range; protobuf handles varint compaction automatically |

### Wire cost at worst-case (all bits set)

| Quantization bits | Max value | Varint bytes | Tag (field ≤ 15) | Total per field |
|---|---|---|---|---|
| 8 | 255 | 2 | 1 | 3 B |
| 12 | 4 095 | 2 | 1 | 3 B |
| 14 | 16 383 | 2 | 1 | 3 B |
| 16 | 65 535 | 3 | 1 | 4 B |
| 20 | 1 048 575 | 3 | 1 | 4 B |

Proto3 omits fields equal to their default value (0), so average cost is lower.

## Step 2 — Run protoc

```bash
protoc \
  --proto_path=proto \
  --proto_path=/path/to/google/protobuf/include \
  --csharp_out=generated/cs \
  --plugin=protoc-gen-bitwise=protoc-gen-bitwise/plugin.js \
  --bitwise_out=generated/cs \
  proto/decentraland/kernel/comms/v3/comms.proto
```

> `plugin.js` carries a `#!/usr/bin/env node` shebang. On Windows, protoc
> cannot exec a `.js` directly, so point `--plugin` at a small `.cmd` wrapper
> that runs `node plugin.js`; on unix an equivalent shell script is used. Both
> consumer repos (Pulse, unity-explorer) generate this wrapper automatically.

The plugin emits one `*.Bitwise.cs` file (PascalCase, flat in the output
directory) for each `.proto` file that contains at least one `[(quantized)]`
field.

## Step 3 — Copy the runtime

Copy `Quantize.cs` into your project:

```
Assets/
└── Scripts/
    └── Networking/
        └── Bitwise/
            └── Quantize.cs   ← protoc-gen-bitwise/runtime/cs/Quantize.cs
```

`Quantize.cs` lives in the `Decentraland.Networking.Bitwise` namespace and
provides the static encode/decode methods used by the generated accessors:

```csharp
public static class Quantize
{
    public static uint  Encode(float value, float min, float max, int bits);
    public static float Decode(uint encoded, float min, float max, int bits);
    public static uint  EncodePower(float value, float max, float pow, int bits);
    public static float DecodePower(uint encoded, float max, float pow, int bits);
}
```

## Step 4 — Use the generated code

The plugin emits a `partial class` that adds float accessors on top of the
standard protobuf-generated `uint32` properties:

```csharp
using Decentraland.Kernel.Comms.V3;

// --- Build and send ---
var delta = new PositionDelta();
delta.DxQuantized = 3.14f;   // encodes to uint32, stored in delta.Dx
delta.DyQuantized = 0f;
delta.DzQuantized = -7.5f;
delta.EntityId    = 42u;

byte[] bytes = delta.ToByteArray();   // standard protobuf serialization
SendOnChannel1(bytes);

// --- Receive and read ---
var received = PositionDelta.Parser.ParseFrom(receivedBytes);
if (!received.AreQuantizedFieldsInRange()) return;   // reject malformed/hostile codes
float x = received.DxQuantized;   // decoded from the stored uint32 on each access
float y = received.DyQuantized;
float z = received.DzQuantized;
```

## Generated file example

For the `comms.proto` file above the plugin emits `Comms.Bitwise.cs` (one file
per `.proto`, named after the proto file). Each quantized field gets a
`{Name}QuantizedStep` const and a float accessor; each message gets an
`AreQuantizedFieldsInRange()` guard for validating inbound wire codes:

```csharp
// <auto-generated>
//   Generated by protoc-gen-bitwise. DO NOT EDIT.
//   Source: decentraland/kernel/comms/v3/comms.proto
// </auto-generated>

using Decentraland.Networking.Bitwise;

namespace Decentraland.Kernel.Comms.V3
{
    public partial class PositionDelta
    {
        /// <summary>Coarsest quantization step of <see cref="DxQuantized"/>. Safe as an equality tolerance.</summary>
        public const float DxQuantizedStep = 0.0030518044f;
        /// <summary>Float accessor for <see cref="Dx"/>. Range [-100.0f, 100.0f], 16 bits, step ≈ 0.0030518.</summary>
        public float DxQuantized
        {
            get => Quantize.Decode(Dx, -100.0f, 100.0f, 16);
            set => Dx = Quantize.Encode(value, -100.0f, 100.0f, 16);
        }

        /// <summary>Coarsest quantization step of <see cref="DyQuantized"/>. Safe as an equality tolerance.</summary>
        public const float DyQuantizedStep = 0.0030518044f;
        /// <summary>Float accessor for <see cref="Dy"/>. Range [-100.0f, 100.0f], 16 bits, step ≈ 0.0030518.</summary>
        public float DyQuantized
        {
            get => Quantize.Decode(Dy, -100.0f, 100.0f, 16);
            set => Dy = Quantize.Encode(value, -100.0f, 100.0f, 16);
        }

        /// <summary>Coarsest quantization step of <see cref="DzQuantized"/>. Safe as an equality tolerance.</summary>
        public const float DzQuantizedStep = 0.0030518044f;
        /// <summary>Float accessor for <see cref="Dz"/>. Range [-100.0f, 100.0f], 16 bits, step ≈ 0.0030518.</summary>
        public float DzQuantized
        {
            get => Quantize.Decode(Dz, -100.0f, 100.0f, 16);
            set => Dz = Quantize.Encode(value, -100.0f, 100.0f, 16);
        }

        /// <summary>
        ///     True when every quantized field holds a wire code within its declared bit width
        ///     (<c>0 .. 2^bits-1</c>). The encoder never emits a code above this bound, so a larger
        ///     value is a malformed/hostile message: decoding it would land far outside the field's
        ///     <c>[min, max]</c> and, since the server relays raw codes verbatim, poison every observer.
        ///     Reject before storing or relaying. Pure integer comparison — no decode.
        /// </summary>
        public bool AreQuantizedFieldsInRange() =>
            Dx <= 65535u
            && Dy <= 65535u
            && Dz <= 65535u;
    }

} // namespace Decentraland.Kernel.Comms.V3
```
