#!/usr/bin/env node
'use strict'

/**
 * protoc-gen-bitwise — protoc plugin that generates C# bitwise serialization code.
 *
 * Protocol:
 *   1. protoc writes a serialised CodeGeneratorRequest to this process's stdin.
 *   2. This plugin reads it, generates C# partial classes with float accessor
 *      properties for every message that carries [(quantized)] field annotations.
 *   3. A serialised CodeGeneratorResponse is written to stdout.
 *
 * Implemented in plain Node with a self-contained protobuf wire codec (see
 * wire.js) so it runs with only `node` on PATH — no npm install required, even
 * when invoked directly from a sibling checkout.
 *
 * Usage (from project root):
 *   protoc \
 *     --proto_path=proto \
 *     --bitwise_out=generated/ \
 *     --plugin=protoc-gen-bitwise=protoc-gen-bitwise/plugin.js \
 *     proto/my_messages.proto
 *
 * On Windows, protoc needs an executable wrapper, e.g. a .cmd that runs:
 *   node "<path>\protoc-gen-bitwise\plugin.js" %*
 */

const { decodeRequest, encodeResponse } = require('./wire')
const { generateCsharp } = require('./generator_csharp')

// CodeGeneratorResponse.Feature.FEATURE_PROTO3_OPTIONAL — advertised so protoc
// does not reject the plugin when the schema uses proto3 `optional` fields.
const FEATURE_PROTO3_OPTIONAL = 1

function readStdin() {
  return new Promise((resolve, reject) => {
    const chunks = []
    process.stdin.on('data', (chunk) => chunks.push(chunk))
    process.stdin.on('end', () => resolve(Buffer.concat(chunks)))
    process.stdin.on('error', reject)
  })
}

async function main() {
  const requestBytes = await readStdin()
  const request = decodeRequest(requestBytes)

  // Lookup map for all file descriptors (parity with the Python plugin).
  const fileByName = new Map()
  for (const file of request.protoFile) fileByName.set(file.name, file)

  const files = []
  let error = null

  for (const fileName of request.fileToGenerate) {
    // Skip the options definition file itself — it has no messages to generate.
    if (fileName === 'decentraland/common/options.proto') continue

    const fileProto = fileByName.get(fileName)
    if (!fileProto) continue

    try {
      const generated = generateCsharp(fileProto)
      if (generated) files.push(generated)
    } catch (exc) {
      error = `protoc-gen-bitwise: error processing ${fileName}: ${exc && exc.message ? exc.message : exc}`
    }
  }

  const response = encodeResponse({
    error,
    supportedFeatures: FEATURE_PROTO3_OPTIONAL,
    files,
  })

  // Let the write flush before the process exits (do not call process.exit()).
  process.stdout.write(response)
}

main().catch((exc) => {
  const response = encodeResponse({
    error: `protoc-gen-bitwise: ${exc && exc.stack ? exc.stack : exc}`,
    supportedFeatures: FEATURE_PROTO3_OPTIONAL,
    files: [],
  })
  process.stdout.write(response)
})
