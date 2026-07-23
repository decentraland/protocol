# CLAUDE.md — MMO Networking Stack

## Project Overview

High-performance MMO-style multiplayer networking stack. Protocol is **open** (Unity C# client + others). Infrastructure on **AWS**. Goals: high concurrency, aggressive interest management, low-latency state sync.

| Layer | Choice |
|---|---|
| Transport | ENet (UDP, channel-based) |
| Client | Unity (C#) |
| Server | Custom server |
| Schema source of truth | `.proto` files |
| Serialization | Standard protobuf wire format + custom protoc plugin (quantized float accessors) |
| Auth | Decentraland ECDSA chain validation (local, on HANDSHAKE channel 0) |

---

## Serialization: Custom Protoc Plugin

### What it does
Reads `.proto` files with custom field options and generates C# **partial classes** (`*.Bitwise.cs`) that add typed float accessors on top of quantized `uint32` fields, keeping the quantization math bit-for-bit identical across all client implementations.

The wire format is **standard protobuf** — a quantized value lives in a plain `uint32` field and travels as an ordinary varint. There is no custom bit stream; any protobuf-capable client can parse the messages without this plugin. Per annotated field the plugin emits:

- `float {Field}Quantized` — computed accessor (no backing cache): the getter decodes the stored `uint32`, the setter encodes a float back into it, via the static `Quantize` helpers
- `const float {Field}QuantizedStep` — the coarsest quantization step of the field, safe as an equality tolerance
- per message: `bool AreQuantizedFieldsInRange()` — pure-integer check that every stored code fits its declared bit width (`0 .. 2^bits-1`); reject malformed/hostile messages before storing or relaying

Only non-repeated `uint32` fields get accessors; `bit_packed` and unannotated fields pass through with no generated code.

### Custom Field Options (`options.proto`)

```protobuf
syntax = "proto3";
import "google/protobuf/descriptor.proto";

message QuantizedFloatOptions {
  float  min  = 1;
  float  max  = 2;
  uint32 bits = 3;
}

// Signed power-law quantizer: an (bits-1)-bit magnitude (high bits) plus a sign
// (LSB), decoded as sign * max * u^pow. Exact zero; pow>1 concentrates resolution
// near zero; sign in the LSB keeps small magnitudes in one varint byte.
message QuantizedPowerFloatOptions {
  float  max  = 1;
  float  pow  = 2;
  uint32 bits = 3;
}

message BitPackedOptions {
  uint32 bits = 1;
}

extend google.protobuf.FieldOptions {
  QuantizedFloatOptions      quantized       = 50001;
  BitPackedOptions           bit_packed      = 50002;
  QuantizedPowerFloatOptions quantized_power = 50003;
}
```

### Usage example

Quantized fields are declared **`uint32`** (not `float`) — the float type exists only in the generated accessor:

```protobuf
message PositionDelta {
  uint32 dx        = 1 [(quantized)  = { min: -100.0, max: 100.0, bits: 16 }];
  uint32 dy        = 2 [(quantized)  = { min: -100.0, max: 100.0, bits: 16 }];
  uint32 dz        = 3 [(quantized)  = { min: -100.0, max: 100.0, bits: 16 }];
  uint32 entity_id = 4 [(bit_packed) = { bits: 20 }];
  uint32 sequence  = 5 [(bit_packed) = { bits: 12 }];
}
// Varint wire cost: dx/dy/dz/entity_id ≤ 4 B each (1 B tag + ≤ 3 B varint),
// sequence ≤ 3 B — worst-case 19 B, less when proto3 omits zero-valued fields.
```

`proto/decentraland/common/quantization_example.proto` is the fully worked reference: per-field wire costs for the linear, power-law, and bit-packed annotations.

### Plugin structure

```
protoc-gen-bitwise/
├── plugin.js            # stdin -> CodeGeneratorRequest, stdout -> CodeGeneratorResponse (Node)
├── generator_csharp.js  # emits the *.Bitwise.cs accessor partials for Unity
├── options.js           # parses the custom quantized / quantized_power / bit_packed field options
├── wire.js              # self-contained protobuf wire codec (zero runtime deps)
└── runtime/cs/          # C# runtime: Quantize.cs — consumers copy it next to the generated files
```

Plugin contract: a protoc plugin that reads a serialized `CodeGeneratorRequest` from stdin and writes a serialized `CodeGeneratorResponse` to stdout. It is a plain Node script — **no `npm install` required, only `node` on PATH**. protoc invokes it through a tiny wrapper that runs `node plugin.js` (`.cmd` on Windows, a shell script elsewhere, since protoc cannot exec a `.js` directly).

```bash
protoc \
  --proto_path=proto \
  --bitwise_out=generated/ \
  --plugin=protoc-gen-bitwise=protoc-gen-bitwise/plugin.js \
  movement.proto position.proto
```

Parity is locked down by `npm run gen:test` (compares generator output against golden C# fixtures in `protoc-gen-bitwise/test/`).

---

## Quantize Runtime

Generated accessors call the static `Quantize` class (`protoc-gen-bitwise/runtime/cs/Quantize.cs`, namespace `Decentraland.Networking.Bitwise`) — the only C# runtime file; consumers copy it next to the generated `*.Bitwise.cs` partials. Quantization uses **`Round`** (not truncate) to minimize error; identical rounding on both sides makes encode -> decode a round-trip no-op.

### Core math — linear (`Quantize.Encode` / `Quantize.Decode`)

```
encoded = Round(clamp01((value - min) / (max - min)) * (2^bits - 1))
decoded = encoded / (2^bits - 1) * (max - min) + min
```

### Core math — power-law (`Quantize.EncodePower` / `Quantize.DecodePower`)

For signed fields like velocity that need an exact zero and fine resolution near zero:

```
u       = clamp01(|value| / max) ^ (1 / pow)
encoded = (Round(u * (2^(bits-1) - 1)) << 1) | sign     // magnitude in high bits, sign in LSB
decoded = sign * max * ((encoded >> 1) / (2^(bits-1) - 1)) ^ pow
```

- Zero encodes exactly to code `0` (a zero magnitude never sets the sign bit), so proto3 omits a stopped field entirely
- `pow > 1` concentrates resolution near zero, coarse near `±max`
- Sign in the LSB makes the varint cost track magnitude, not direction — a small `|value|` of either sign stays in one varint byte

---

## Precision Reference

| Range       | Bits | Step size     |
|-------------|------|---------------|
| [-100, 100] | 16   | ~0.003 units  |
| [-10, 10]   | 12   | ~0.005 units  |
| [-100, 100] | 12   | ~0.049 units  |

Sub-centimeter precision is achievable at 12-16 bits for position deltas.

Wire cost is varint-based — 1 tag byte per present field (field numbers ≤ 15) plus:

| Code bits | Worst-case varint | Worst-case field total |
|-----------|-------------------|------------------------|
| ≤ 7       | 1 B               | 2 B                    |
| ≤ 14      | 2 B               | 3 B                    |
| ≤ 21      | 3 B               | 4 B                    |

Proto3 omits fields equal to 0, so typical cost is lower than worst-case.

---

## Key Design Principles

- `.proto` files are the **single source of truth** for all message schemas
- The protoc plugin generates the **C# quantized accessors** from the schema — never hand-write quantization math; standard protobuf handles the wire encoding
- Encode -> decode is a **no-op** (round-trip safe) due to consistent use of `Round`
- Validate inbound quantized messages with `AreQuantizedFieldsInRange()` before storing or relaying — the server relays raw codes verbatim
- Prefer **client-driven resync** over proactive server corrections
- Push complexity to clients where appropriate; server maintains authority
- Channel 0: reliable messages (STATE_FULL snapshots, ACKs, resync requests, HANDSHAKE)
- Channel 1: unreliable sequenced (high-frequency position deltas, client input)