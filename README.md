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

Many repositories depend on this protocol definition and that sometimes implies some merge order. We don't have to worry much about compatibility because the checks are running with each PR, if you break something, the CI will warn you. But, in some cases, it's desirable to merge the implementation in a specific order to avoid unexpected behavior in the corner cases (multiple repositories are waiting for the build at the same time).

> **Important Note: Avoid Merging Protocol PR Without Completed Unity Implementation**
>
> Please don't merge a protocol PR into the main branch unless the corresponding implementation in Unity has been completed. This is important to avoid any potential issues or build failures in Unity.
>
> The ideal order for introducing breaking changes in the protocol is as follows:
>
> 1. Create a PR in the Protocol repository.
> 2. Use the npm test link from the CI of the protocol PR in the protocol-dependent application for development.
> 3. Once both the protocol PR and the protocol-dependent application (e.g. unity-renderer) PR are ready for merging, synchronize their merging as follows:
>    1. Merge the protocol PR.
>    2. Modify protocol-dependent application PR to use the `@dcl/protocol@next` package to stop using the PR npm test link.
>    3. Merge the protocol-dependent application PR.

Some dev-cases are described here:

## SDK: New component or component modification

Repositories: [unity-renderer](https://github.com/decentraland/unity-renderer/) and [js-sdk-toolchain](https://github.com/decentraland/js-sdk-toolchain/)

At the protocol level both operations shouldn't be a problem, but `js-sdk-toolchain` CI will fail if the component is not tested. This can happen if the PR **`A`** from the protocol is merged, and you update your PR **`B`** from `js-sdk-toolchain` with the changes before the PR **`A`** from `js-sdk-toolchain` is merged.

Some guidelines and testing before merge:

- The protocol package is uploaded to S3 while developing in a PR. This can be used in the target repositories
- Testing in the playground: Playground allows us to test by adding query parameters: `https://playground.decentraland.org/?&renderer-branch=**feat/my-new-component**&sdk-branch=**feat/new-component-approach**`
- Testing locally: you can write an example scene and install the package `@dcl/sdk` uploaded to S3 commented in the PR comments.
- Testing in the Unity Editor: if you need to test with the editor opened, write the `ws` query parameter in your local or playground test.
- Start merging when the three PRs are already to merge: first merge the Protocol one, then update the other two with the version @next and merge them at the same time.

## SDK: New APIs or APIs modifications

Repositories: [kernel](https://github.com/decentraland/kernel/), [js-sdk-toolchain](https://github.com/decentraland/js-sdk-toolchain/) and [scene-runtime](https://github.com/decentraland/scene-runtime/)
In this case, there is no problem with when each PR is merged. It's recommendable to merge first the rpc server-side (in this case, Kernel), second the `scene-runtime` (and this would require a second update from `kernel`) and last the `js-sdk-toolchain`.

## Comms

TODO

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
   cached float accessor (e.g. `PositionXQuantized`) that encodes/decodes
   transparently via `Quantize.Encode` / `Quantize.Decode`.

The wire representation is a standard protobuf message — any protobuf-capable
client can read it without knowledge of the plugin.

## Prerequisites

| Requirement | Version |
|---|---|
| Python | 3.10+ |
| `protobuf` Python package | 4.x or 3.20+ |
| `protoc` | 3.19+ |

```bash
pip install protobuf
```

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
| `[(decentraland.common.quantized)]` | `uint32` | `min`, `max`, `bits` | Plugin emits a cached `float {Name}Quantized` accessor |
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
  --plugin=protoc-gen-bitwise=protoc-gen-bitwise/plugin.py \
  --bitwise_out=generated/cs \
  proto/decentraland/kernel/comms/v3/comms.proto
```

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
provides two static methods used by the generated accessors:

```csharp
public static class Quantize
{
    public static uint  Encode(float value, float min, float max, int bits);
    public static float Decode(uint encoded, float min, float max, int bits);
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
float x = received.DxQuantized;   // decoded on first access, cached thereafter
float y = received.DyQuantized;
float z = received.DzQuantized;

// If raw uint32 fields are mutated directly after construction, invalidate the cache:
received.ResetDecodedCache();
```

## Generated file example

For the `PositionDelta` message above the plugin emits `PositionDelta.Bitwise.cs`:

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
        private float? _dx;
        public float DxQuantized
        {
            get => _dx ??= Quantize.Decode(Dx, -100.0f, 100.0f, 16);
            set { _dx = value; Dx = Quantize.Encode(value, -100.0f, 100.0f, 16); }
        }

        private float? _dy;
        public float DyQuantized
        {
            get => _dy ??= Quantize.Decode(Dy, -100.0f, 100.0f, 16);
            set { _dy = value; Dy = Quantize.Encode(value, -100.0f, 100.0f, 16); }
        }

        private float? _dz;
        public float DzQuantized
        {
            get => _dz ??= Quantize.Decode(Dz, -100.0f, 100.0f, 16);
            set { _dz = value; Dz = Quantize.Encode(value, -100.0f, 100.0f, 16); }
        }

        /// <summary>Clears all cached decoded values. Call after mutating raw uint32 fields directly.</summary>
        public void ResetDecodedCache()
        {
            _dx = null;
            _dy = null;
            _dz = null;
        }
    }

} // namespace Decentraland.Kernel.Comms.V3
```
