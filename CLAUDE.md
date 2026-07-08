# CLAUDE.md — MMO Networking Stack

## Project Overview

High-performance MMO-style multiplayer networking stack. Protocol is **open** (Unity C# client + others). Infrastructure on **AWS**. Goals: high concurrency, aggressive interest management, low-latency state sync.

| Layer | Choice |
|---|---|
| Transport | ENet (UDP, channel-based) |
| Client | Unity (C#) |
| Server | Custom server |
| Schema source of truth | `.proto` files |
| Serialization | Custom protoc plugin (bitwise encoding) |
| Auth | Decentraland ECDSA chain validation (local, on HANDSHAKE channel 0) |

---

## Serialization: Custom Protoc Plugin

### What it does
Reads `.proto` files with custom field options and generates **bitwise encode/decode code** in C#, keeping all client implementations bit-for-bit identical.

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

```protobuf
message PositionDelta {
  float  dx        = 1 [(quantized)  = { min: -100.0, max: 100.0, bits: 16 }];
  float  dy        = 2 [(quantized)  = { min: -100.0, max: 100.0, bits: 16 }];
  float  dz        = 3 [(quantized)  = { min: -100.0, max: 100.0, bits: 16 }];
  uint32 entity_id = 4 [(bit_packed) = { bits: 20 }];
}
// Total: 68 bits = 9 bytes on the wire
```

### Plugin structure

```
protoc-gen-bitwise/
├── plugin.js            # stdin -> CodeGeneratorRequest, stdout -> CodeGeneratorResponse (Node)
├── generator_csharp.js  # emits C# for Unity
├── options.js           # parses the custom quantized / bit_packed field options
├── wire.js              # self-contained protobuf wire codec (zero runtime deps)
└── runtime/cs/          # C# runtime; Quantize.cs is copied into the generated output
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

## BitWriter / BitReader

The C# implementation uses the following bit layout: **big-endian within each byte**, MSB written first. Use **`Round`** (not truncate) when quantizing to minimize error.

### Core math — WriteQuantizedFloat

```
normalized = (clamp(value, min, max) - min) / (max - min)  // -> [0.0, 1.0]
quantized  = Round(normalized * ((1 << bits) - 1))          // -> integer
```

### Core math — ReadQuantizedFloat

```
normalized = quantized / ((1 << bits) - 1)
value      = min + normalized * (max - min)
```

### Implementation

```csharp
public class BitWriter
{
    private byte[] _buffer;
    private int    _bitPos;

    public BitWriter(byte[] buffer) { _buffer = buffer; _bitPos = 0; }

    public void WriteBits(uint value, int bits)
    {
        for (int i = bits - 1; i >= 0; i--)
        {
            int byteIdx = _bitPos / 8;
            int bitIdx  = 7 - (_bitPos % 8);
            if ((value >> i & 1) == 1) _buffer[byteIdx] |=  (byte)(1 << bitIdx);
            else                       _buffer[byteIdx] &= (byte)~(1 << bitIdx);
            _bitPos++;
        }
    }

    public void WriteQuantizedFloat(float value, float min, float max, int bits)
    {
        uint  maxQ       = (1u << bits) - 1;
        float clamped    = Math.Clamp(value, min, max);
        float normalized = (clamped - min) / (max - min);
        uint  quantized  = (uint)Math.Round(normalized * maxQ);
        WriteBits(quantized, bits);
    }
}

public class BitReader
{
    private byte[] _buffer;
    private int    _bitPos;

    public BitReader(byte[] buffer) { _buffer = buffer; _bitPos = 0; }

    public uint ReadBits(int bits)
    {
        uint value = 0;
        for (int i = bits - 1; i >= 0; i--)
        {
            int byteIdx = _bitPos / 8;
            int bitIdx  = 7 - (_bitPos % 8);
            if ((_buffer[byteIdx] >> bitIdx & 1) == 1) value |= 1u << i;
            _bitPos++;
        }
        return value;
    }

    public float ReadQuantizedFloat(float min, float max, int bits)
    {
        uint  maxQ       = (1u << bits) - 1;
        uint  quantized  = ReadBits(bits);
        float normalized = (float)quantized / maxQ;
        return min + normalized * (max - min);
    }
}
```

---

## Precision Reference

| Range       | Bits | Step size     |
|-------------|------|---------------|
| [-100, 100] | 16   | ~0.003 units  |
| [-10, 10]   | 12   | ~0.005 units  |
| [-100, 100] | 12   | ~0.049 units  |

Sub-centimeter precision is achievable at 12-16 bits for position deltas.

---

## Key Design Principles

- `.proto` files are the **single source of truth** for all message schemas
- The protoc plugin generates **C#** from the schema — never hand-write serialization
- Encode -> decode is a **no-op** (round-trip safe) due to consistent use of `Round`
- Prefer **client-driven resync** over proactive server corrections
- Push complexity to clients where appropriate; server maintains authority
- Channel 0: reliable messages (STATE_FULL snapshots, ACKs, resync requests, HANDSHAKE)
- Channel 1: unreliable sequenced (high-frequency position deltas, client input)