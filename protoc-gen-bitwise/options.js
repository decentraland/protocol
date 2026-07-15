'use strict'

/**
 * Parser for the custom bitwise field options defined in options.proto.
 *
 * The descriptor decoder hands us the raw serialized FieldOptions bytes (it
 * declares `options` as opaque bytes). We walk those bytes looking for the
 * custom extension field numbers — protobuf preserves unknown/unregistered
 * extension bytes, so they are always present even though no runtime here knows
 * the extension schema. This mirrors the original options_pb2.py.
 *
 * Wire format: tag = (field_number << 3) | wire_type
 *   wire_type 0 = varint, 1 = 64-bit, 2 = length-delimited, 5 = 32-bit
 */

const { readVarint, skipField } = require('./wire')

// Extension field numbers as defined in options.proto.
const QUANTIZED_FIELD_NUMBER = 50001
const BIT_PACKED_FIELD_NUMBER = 50002
const QUANTIZED_POWER_FIELD_NUMBER = 50003

/** Parse a serialized QuantizedFloatOptions message: { min, max, bits }. */
function parseQuantized(data) {
  const opts = { min: 0.0, max: 0.0, bits: 0 }
  let pos = 0
  while (pos < data.length) {
    let tag
    ;[tag, pos] = readVarint(data, pos)
    const fieldNum = tag >>> 3
    const wireType = tag & 0x7
    if (fieldNum === 1 && wireType === 5) {
      // min (float)
      opts.min = data.readFloatLE(pos)
      pos += 4
    } else if (fieldNum === 2 && wireType === 5) {
      // max (float)
      opts.max = data.readFloatLE(pos)
      pos += 4
    } else if (fieldNum === 3 && wireType === 0) {
      // bits (uint32)
      ;[opts.bits, pos] = readVarint(data, pos)
    } else {
      pos = skipField(data, pos, wireType)
    }
  }
  return opts
}

/** Parse a serialized QuantizedPowerFloatOptions message: { max, pow, bits }. */
function parseQuantizedPower(data) {
  const opts = { max: 0.0, pow: 0.0, bits: 0 }
  let pos = 0
  while (pos < data.length) {
    let tag
    ;[tag, pos] = readVarint(data, pos)
    const fieldNum = tag >>> 3
    const wireType = tag & 0x7
    if (fieldNum === 1 && wireType === 5) {
      // max (float)
      opts.max = data.readFloatLE(pos)
      pos += 4
    } else if (fieldNum === 2 && wireType === 5) {
      // pow (float)
      opts.pow = data.readFloatLE(pos)
      pos += 4
    } else if (fieldNum === 3 && wireType === 0) {
      // bits (uint32)
      ;[opts.bits, pos] = readVarint(data, pos)
    } else {
      pos = skipField(data, pos, wireType)
    }
  }
  return opts
}

/** Parse a serialized BitPackedOptions message: { bits }. */
function parseBitPacked(data) {
  const opts = { bits: 0 }
  let pos = 0
  while (pos < data.length) {
    let tag
    ;[tag, pos] = readVarint(data, pos)
    const fieldNum = tag >>> 3
    const wireType = tag & 0x7
    if (fieldNum === 1 && wireType === 0) {
      // bits (uint32)
      ;[opts.bits, pos] = readVarint(data, pos)
    } else {
      pos = skipField(data, pos, wireType)
    }
  }
  return opts
}

/**
 * Extract custom bitwise options from raw FieldOptions bytes.
 *
 * @param {Buffer|null} optionsRaw serialized FieldOptions, or null when unset.
 * @returns {{quantized: object|null, bitPacked: object|null, quantizedPower: object|null}}
 */
function getFieldOptions(optionsRaw) {
  if (!optionsRaw || optionsRaw.length === 0) {
    return { quantized: null, bitPacked: null, quantizedPower: null }
  }

  let quantized = null
  let bitPacked = null
  let quantizedPower = null
  let pos = 0

  while (pos < optionsRaw.length) {
    let tag
    ;[tag, pos] = readVarint(optionsRaw, pos)
    const fieldNum = tag >>> 3
    const wireType = tag & 0x7

    if (wireType === 2) {
      let len
      ;[len, pos] = readVarint(optionsRaw, pos)
      const valueBytes = optionsRaw.subarray(pos, pos + len)
      pos += len
      if (fieldNum === QUANTIZED_FIELD_NUMBER) {
        quantized = parseQuantized(valueBytes)
      } else if (fieldNum === BIT_PACKED_FIELD_NUMBER) {
        bitPacked = parseBitPacked(valueBytes)
      } else if (fieldNum === QUANTIZED_POWER_FIELD_NUMBER) {
        quantizedPower = parseQuantizedPower(valueBytes)
      }
      // else: unknown length-delimited field — already consumed.
    } else {
      pos = skipField(optionsRaw, pos, wireType)
    }
  }

  return { quantized, bitPacked, quantizedPower }
}

module.exports = { getFieldOptions }
