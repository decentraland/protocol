'use strict'

/**
 * Byte-for-byte parity test for the C# generator.
 *
 * Builds in-memory FieldDescriptorProto structures (with real serialized
 * FieldOptions extension bytes), runs them through the same options parser and
 * generator the plugin uses, and asserts the output equals committed golden
 * files. This locks down the %g float formatting and the emitted layout without
 * needing protoc.
 *
 * Run with: node protoc-gen-bitwise/test/generator.test.js   (or `npm run gen:test`)
 */

const assert = require('assert')
const fs = require('fs')
const path = require('path')

const { generateCsharp } = require('../generator_csharp')

// FieldDescriptorProto.Type
const TYPE_DOUBLE = 1
const TYPE_BOOL = 8
const TYPE_UINT32 = 13
// FieldDescriptorProto.Label
const LABEL_OPTIONAL = 1

// --- minimal wire encoders to build serialized FieldOptions extension bytes ---

function encodeVarint(value) {
  const bytes = []
  let v = value
  while (v > 0x7f) {
    bytes.push((v & 0x7f) | 0x80)
    v = Math.floor(v / 128)
  }
  bytes.push(v & 0x7f)
  return Buffer.from(bytes)
}

function tag(fieldNum, wireType) {
  return encodeVarint((fieldNum << 3) | wireType)
}

function floatLE(value) {
  const b = Buffer.alloc(4)
  b.writeFloatLE(value, 0)
  return b
}

function lengthDelimited(fieldNum, payload) {
  return Buffer.concat([tag(fieldNum, 2), encodeVarint(payload.length), payload])
}

// FieldOptions bytes carrying ext 50001 (quantized) = { min, max, bits }
function quantizedOptions(min, max, bits) {
  const inner = Buffer.concat([
    tag(1, 5), floatLE(min),
    tag(2, 5), floatLE(max),
    tag(3, 0), encodeVarint(bits),
  ])
  return lengthDelimited(50001, inner)
}

// FieldOptions bytes carrying ext 50002 (bit_packed) = { bits }
function bitPackedOptions(bits) {
  const inner = Buffer.concat([tag(1, 0), encodeVarint(bits)])
  return lengthDelimited(50002, inner)
}

// FieldOptions bytes carrying ext 50003 (quantized_power) = { max, pow, bits }
function quantizedPowerOptions(max, pow, bits) {
  const inner = Buffer.concat([
    tag(1, 5), floatLE(max),
    tag(2, 5), floatLE(pow),
    tag(3, 0), encodeVarint(bits),
  ])
  return lengthDelimited(50003, inner)
}

function field(name, type, optionsRaw) {
  return { name, label: LABEL_OPTIONAL, type, optionsRaw: optionsRaw || null }
}

function readGolden(name) {
  return fs.readFileSync(path.join(__dirname, 'golden', name), 'utf8')
}

// --------------------------------------------------------------------------
// Case 1: quantization_example.proto
// --------------------------------------------------------------------------

const quantizationExample = {
  name: 'decentraland/common/quantization_example.proto',
  package: 'decentraland.common',
  messageType: [
    {
      name: 'PositionDelta',
      field: [
        field('dx', TYPE_UINT32, quantizedOptions(-100, 100, 16)),
        field('dy', TYPE_UINT32, quantizedOptions(-100, 100, 16)),
        field('dz', TYPE_UINT32, quantizedOptions(-100, 100, 16)),
        field('entity_id', TYPE_UINT32, bitPackedOptions(20)),
        field('sequence', TYPE_UINT32, bitPackedOptions(12)),
      ],
    },
    {
      name: 'PlayerInput',
      field: [
        field('move_x', TYPE_UINT32, quantizedOptions(-1, 1, 8)),
        field('move_z', TYPE_UINT32, quantizedOptions(-1, 1, 8)),
        field('yaw', TYPE_UINT32, quantizedOptions(-180, 180, 12)),
        field('buttons', TYPE_UINT32, bitPackedOptions(8)),
        field('sequence', TYPE_UINT32, bitPackedOptions(12)),
      ],
    },
    {
      name: 'VelocityState',
      field: [
        field('vx', TYPE_UINT32, quantizedPowerOptions(50, 2, 8)),
        field('vy', TYPE_UINT32, quantizedPowerOptions(50, 2, 8)),
        field('vz', TYPE_UINT32, quantizedPowerOptions(50, 2, 8)),
      ],
    },
    {
      name: 'AvatarStateSnapshot',
      field: [
        field('x', TYPE_UINT32, quantizedOptions(-4096, 4096, 16)),
        field('y', TYPE_UINT32, quantizedOptions(-256, 256, 14)),
        field('z', TYPE_UINT32, quantizedOptions(-4096, 4096, 16)),
        field('pitch', TYPE_UINT32, quantizedOptions(-90, 90, 10)),
        field('yaw', TYPE_UINT32, quantizedOptions(-180, 180, 12)),
        field('entity_id', TYPE_UINT32, bitPackedOptions(20)),
        field('animation_state', TYPE_UINT32, bitPackedOptions(6)),
        field('is_grounded', TYPE_BOOL, null),
        field('timestamp', TYPE_DOUBLE, null),
      ],
    },
  ],
}

// --------------------------------------------------------------------------
// Case 2: pulse_server.proto (PlayerStateDeltaTier0) — wider bit/range coverage
// --------------------------------------------------------------------------

const pulseServer = {
  name: 'decentraland/pulse/pulse_server.proto',
  package: 'decentraland.pulse',
  messageType: [
    {
      name: 'PlayerStateDeltaTier0',
      field: [
        field('position_x', TYPE_UINT32, quantizedOptions(0, 16, 8)),
        field('position_y', TYPE_UINT32, quantizedOptions(0, 200, 13)),
        field('position_z', TYPE_UINT32, quantizedOptions(0, 16, 8)),
        field('velocity_x', TYPE_UINT32, quantizedPowerOptions(50, 2, 8)),
        field('velocity_y', TYPE_UINT32, quantizedPowerOptions(50, 2, 8)),
        field('velocity_z', TYPE_UINT32, quantizedPowerOptions(50, 2, 8)),
        field('rotation_y', TYPE_UINT32, quantizedOptions(0, 360, 7)),
        field('movement_blend', TYPE_UINT32, quantizedOptions(0, 3, 5)),
        field('slide_blend', TYPE_UINT32, quantizedOptions(0, 1, 4)),
        field('head_yaw', TYPE_UINT32, quantizedOptions(0, 360, 7)),
        field('head_pitch', TYPE_UINT32, quantizedOptions(0, 360, 7)),
        field('point_at_x', TYPE_UINT32, quantizedOptions(-3000, 3000, 17)),
        field('point_at_y', TYPE_UINT32, quantizedOptions(0, 200, 7)),
        field('point_at_z', TYPE_UINT32, quantizedOptions(-3000, 3000, 17)),
      ],
    },
  ],
}

// --------------------------------------------------------------------------

const cases = [
  { proto: quantizationExample, golden: 'QuantizationExample.Bitwise.cs' },
  { proto: pulseServer, golden: 'PulseServer.Bitwise.cs' },
]

// Set UPDATE_GOLDEN=1 to rewrite the golden files from the current generator output
// (after an intentional generator change), then re-run without it to verify.
const update = process.env.UPDATE_GOLDEN === '1'

let failed = 0
for (const { proto, golden } of cases) {
  const result = generateCsharp(proto)
  assert.ok(result, `expected output for ${golden}`)
  assert.strictEqual(result.name, golden, `output filename for ${golden}`)

  if (update) {
    fs.writeFileSync(path.join(__dirname, 'golden', golden), result.content)
    console.log(`updated - ${golden}`)
    continue
  }

  try {
    assert.strictEqual(result.content, readGolden(golden))
    console.log(`ok   - ${golden} matches golden`)
  } catch (e) {
    failed++
    console.error(`FAIL - ${golden} differs from golden`)
    console.error(e.message)
  }
}

if (update) {
  console.log('\nGolden files updated. Re-run `npm run gen:test` to verify.')
  process.exit(0)
}

if (failed > 0) {
  console.error(`\n${failed} golden mismatch(es)`)
  process.exit(1)
}
console.log('\nAll bitwise generator golden tests passed.')
