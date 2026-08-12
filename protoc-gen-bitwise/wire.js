'use strict'

/**
 * Self-contained protobuf wire-format codec for protoc-gen-bitwise.
 *
 * The plugin only needs a tiny slice of the descriptor/plugin schemas, so
 * rather than pull in a protobuf runtime (which would force every consumer —
 * including the sibling Pulse checkout that runs this file directly off disk —
 * to `npm install` the protocol repo) we decode the handful of fields we care
 * about by walking the wire format directly. This mirrors the original Python
 * plugin, which already hand-parsed FieldOptions for the same reason.
 *
 * Decoded subset:
 *   CodeGeneratorRequest { file_to_generate = 1; proto_file = 15; }
 *   FileDescriptorProto  { name = 1; package = 2; message_type = 4; }
 *   DescriptorProto      { name = 1; field = 2; }
 *   FieldDescriptorProto { name = 1; label = 4; type = 5; options = 8 (raw bytes); }
 *
 * Encoded subset:
 *   CodeGeneratorResponse { error = 1; supported_features = 2; file = 15; }
 *   CodeGeneratorResponse.File { name = 1; content = 15; }
 *
 * Wire types: 0 = varint, 1 = 64-bit, 2 = length-delimited, 5 = 32-bit.
 */

// ---------------------------------------------------------------------------
// Low-level readers
// ---------------------------------------------------------------------------

/** Decode a protobuf varint at `pos`. Returns [value, newPos]. */
function readVarint(buf, pos) {
  let result = 0
  let shift = 0
  let byte
  do {
    byte = buf[pos++]
    // Multiplication (not <<) keeps values correct past 32 bits.
    result += (byte & 0x7f) * Math.pow(2, shift)
    shift += 7
  } while (byte & 0x80)
  return [result, pos]
}

/** Advance `pos` past a field of the given wire type. Returns newPos. */
function skipField(buf, pos, wireType) {
  switch (wireType) {
    case 0: // varint
      return readVarint(buf, pos)[1]
    case 1: // 64-bit
      return pos + 8
    case 2: {
      // length-delimited
      const [length, next] = readVarint(buf, pos)
      return next + length
    }
    case 5: // 32-bit
      return pos + 4
    default:
      // Groups (3/4) are deprecated and never appear in descriptors.
      return pos
  }
}

// ---------------------------------------------------------------------------
// Request decoding
// ---------------------------------------------------------------------------

function decodeFieldDescriptor(buf) {
  const field = { name: '', label: 0, type: 0, optionsRaw: null }
  let pos = 0
  while (pos < buf.length) {
    let tag
    ;[tag, pos] = readVarint(buf, pos)
    const fieldNum = tag >>> 3
    const wireType = tag & 0x7
    if (fieldNum === 1 && wireType === 2) {
      let len
      ;[len, pos] = readVarint(buf, pos)
      field.name = buf.toString('utf8', pos, pos + len)
      pos += len
    } else if (fieldNum === 4 && wireType === 0) {
      ;[field.label, pos] = readVarint(buf, pos)
    } else if (fieldNum === 5 && wireType === 0) {
      ;[field.type, pos] = readVarint(buf, pos)
    } else if (fieldNum === 8 && wireType === 2) {
      let len
      ;[len, pos] = readVarint(buf, pos)
      // Keep the raw FieldOptions bytes so custom extensions survive (the
      // descriptor schema doesn't know about ext 50001/50002).
      field.optionsRaw = buf.subarray(pos, pos + len)
      pos += len
    } else {
      pos = skipField(buf, pos, wireType)
    }
  }
  return field
}

function decodeDescriptor(buf) {
  const message = { name: '', field: [] }
  let pos = 0
  while (pos < buf.length) {
    let tag
    ;[tag, pos] = readVarint(buf, pos)
    const fieldNum = tag >>> 3
    const wireType = tag & 0x7
    if (fieldNum === 1 && wireType === 2) {
      let len
      ;[len, pos] = readVarint(buf, pos)
      message.name = buf.toString('utf8', pos, pos + len)
      pos += len
    } else if (fieldNum === 2 && wireType === 2) {
      let len
      ;[len, pos] = readVarint(buf, pos)
      message.field.push(decodeFieldDescriptor(buf.subarray(pos, pos + len)))
      pos += len
    } else {
      // nested_type / enum_type / etc. are intentionally ignored — the
      // generator only walks top-level messages, matching the Python plugin.
      pos = skipField(buf, pos, wireType)
    }
  }
  return message
}

function decodeFileDescriptor(buf) {
  const file = { name: '', package: '', messageType: [] }
  let pos = 0
  while (pos < buf.length) {
    let tag
    ;[tag, pos] = readVarint(buf, pos)
    const fieldNum = tag >>> 3
    const wireType = tag & 0x7
    if (fieldNum === 1 && wireType === 2) {
      let len
      ;[len, pos] = readVarint(buf, pos)
      file.name = buf.toString('utf8', pos, pos + len)
      pos += len
    } else if (fieldNum === 2 && wireType === 2) {
      let len
      ;[len, pos] = readVarint(buf, pos)
      file.package = buf.toString('utf8', pos, pos + len)
      pos += len
    } else if (fieldNum === 4 && wireType === 2) {
      let len
      ;[len, pos] = readVarint(buf, pos)
      file.messageType.push(decodeDescriptor(buf.subarray(pos, pos + len)))
      pos += len
    } else {
      pos = skipField(buf, pos, wireType)
    }
  }
  return file
}

/** Decode a serialized CodeGeneratorRequest. */
function decodeRequest(buf) {
  const request = { fileToGenerate: [], protoFile: [] }
  let pos = 0
  while (pos < buf.length) {
    let tag
    ;[tag, pos] = readVarint(buf, pos)
    const fieldNum = tag >>> 3
    const wireType = tag & 0x7
    if (fieldNum === 1 && wireType === 2) {
      let len
      ;[len, pos] = readVarint(buf, pos)
      request.fileToGenerate.push(buf.toString('utf8', pos, pos + len))
      pos += len
    } else if (fieldNum === 15 && wireType === 2) {
      let len
      ;[len, pos] = readVarint(buf, pos)
      request.protoFile.push(decodeFileDescriptor(buf.subarray(pos, pos + len)))
      pos += len
    } else {
      pos = skipField(buf, pos, wireType)
    }
  }
  return request
}

// ---------------------------------------------------------------------------
// Response encoding
// ---------------------------------------------------------------------------

/** Encode an unsigned integer as a protobuf varint Buffer. */
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

function encodeTag(fieldNum, wireType) {
  return encodeVarint((fieldNum << 3) | wireType)
}

/** Encode a length-delimited (string/bytes) field: tag + length + payload. */
function encodeLengthDelimited(fieldNum, payload) {
  const buf = Buffer.isBuffer(payload) ? payload : Buffer.from(payload, 'utf8')
  return Buffer.concat([encodeTag(fieldNum, 2), encodeVarint(buf.length), buf])
}

function encodeFile(file) {
  return Buffer.concat([
    encodeLengthDelimited(1, file.name), // name = 1
    encodeLengthDelimited(15, file.content), // content = 15
  ])
}

/**
 * Encode a CodeGeneratorResponse.
 * @param {{error?: string|null, supportedFeatures?: number, files?: Array<{name:string,content:string}>}} response
 */
function encodeResponse(response) {
  const parts = []
  if (response.error != null) {
    parts.push(encodeLengthDelimited(1, response.error)) // error = 1
  }
  if (response.supportedFeatures != null) {
    parts.push(encodeTag(2, 0)) // supported_features = 2 (varint)
    parts.push(encodeVarint(response.supportedFeatures))
  }
  for (const file of response.files || []) {
    parts.push(encodeLengthDelimited(15, encodeFile(file))) // file = 15
  }
  return Buffer.concat(parts)
}

module.exports = {
  readVarint,
  skipField,
  decodeRequest,
  encodeResponse,
}
