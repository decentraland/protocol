'use strict'

/**
 * C# code generator for the protoc-gen-bitwise plugin.
 *
 * For every proto message that contains at least one uint32 field annotated
 * with [(quantized)], this module emits a C# partial class that adds a computed
 * float property named {FieldName}Quantized. The getter decodes the stored
 * uint32 to a float; the setter encodes a float back to a uint32. Standard
 * protobuf handles serialization of the uint32 wire field; this class adds a
 * typed float accessor on top.
 *
 * Only uint32 fields are supported. bit_packed and unannotated fields are
 * passed through without generating any accessor.
 *
 * Port of the original generator_csharp.py — output is intended to be
 * byte-for-byte identical.
 */

const { getFieldOptions } = require('./options')

// FieldDescriptorProto type/label constants.
const TYPE_UINT32 = 13
const LABEL_REPEATED = 3

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Mirrors Python str.capitalize(): upper-first, lowercase the rest. */
function capitalize(word) {
  if (word.length === 0) return ''
  return word[0].toUpperCase() + word.slice(1).toLowerCase()
}

/** position_x -> PositionX */
function snakeToPascal(name) {
  return name.split('_').map(capitalize).join('')
}

/** decentraland.kernel.comms.v3 -> Decentraland.Kernel.Comms.V3 */
function packageToNamespace(pkg) {
  if (!pkg) return 'Generated'
  return pkg.split('.').map(capitalize).join('.')
}

/**
 * Format a number with C printf %g semantics at `precision` significant digits:
 * shortest of fixed/scientific, with trailing zeros and a trailing dot removed.
 * Reproduces Python's `f'{value:.{precision}g}'`.
 */
function formatG(value, precision) {
  if (precision <= 0) precision = 1
  if (value === 0) return '0'
  if (!Number.isFinite(value)) return value > 0 ? 'inf' : 'nan'

  const negative = value < 0
  const v = Math.abs(value)

  // Correctly-rounded scientific form yields the decimal exponent X (handling
  // carry such as 9.999 -> 1.0e+1).
  const sci = v.toExponential(precision - 1)
  const eIdx = sci.indexOf('e')
  const X = parseInt(sci.slice(eIdx + 1), 10)

  let result
  if (X >= -4 && X < precision) {
    // Fixed notation with (precision - 1 - X) fraction digits.
    const fractionDigits = precision - 1 - X
    result = v.toFixed(fractionDigits >= 0 ? fractionDigits : 0)
    if (result.indexOf('.') !== -1) {
      result = result.replace(/0+$/, '').replace(/\.$/, '')
    }
  } else {
    // Scientific notation; printf prints at least two exponent digits.
    let mantissa = sci.slice(0, eIdx)
    if (mantissa.indexOf('.') !== -1) {
      mantissa = mantissa.replace(/0+$/, '').replace(/\.$/, '')
    }
    const expSign = X < 0 ? '-' : '+'
    let expDigits = String(Math.abs(X))
    if (expDigits.length < 2) expDigits = '0' + expDigits
    result = mantissa + 'e' + expSign + expDigits
  }

  return (negative ? '-' : '') + result
}

/** Format a value as a C# float literal (e.g. -100.0f). */
function formatFloat(value) {
  let text = formatG(value, 8)
  if (text.indexOf('.') === -1 && text.indexOf('e') === -1 && text.indexOf('E') === -1) {
    text += '.0'
  }
  return text + 'f'
}

/** Format a quantization step size for a doc comment (e.g. "≈ 0.003"). */
function formatStep(step) {
  return '≈ ' + formatG(step, 6)
}

// ---------------------------------------------------------------------------
// Per-message code generation
// ---------------------------------------------------------------------------

/**
 * Generate a C# partial class for a proto message, or null if it has no
 * quantized uint32 fields. Returns an array of lines (no trailing newline).
 */
function generateMessage(msgProto, indent) {
  const i = indent || '    '
  const props = []

  for (const field of msgProto.field) {
    // Repeated/map fields are not supported.
    if (field.label === LABEL_REPEATED) continue
    // Only uint32 fields are candidates for quantized accessors.
    if (field.type !== TYPE_UINT32) continue

    const { quantized } = getFieldOptions(field.optionsRaw)
    if (quantized === null) continue

    const step = (quantized.max - quantized.min) / ((1 << quantized.bits) - 1)

    props.push({
      propName: snakeToPascal(field.name),
      mn: formatFloat(quantized.min),
      mx: formatFloat(quantized.max),
      bits: quantized.bits,
      step,
    })
  }

  if (props.length === 0) return null

  const backings = []
  const lines = []
  lines.push(`public partial class ${msgProto.name}`)
  lines.push('{')

  for (const { propName, mn, mx, bits, step } of props) {
    const backing = '_' + propName[0].toLowerCase() + propName.slice(1)
    backings.push(backing)
    lines.push(`${i}private float? ${backing};`)
    lines.push(
      `${i}/// <summary>Float accessor for <see cref="${propName}"/>. Range [${mn}, ${mx}], ${bits} bits, step ${formatStep(step)}.</summary>`,
    )
    lines.push(`${i}public float ${propName}Quantized`)
    lines.push(`${i}{`)
    lines.push(`${i}${i}get => ${backing} ??= Quantize.Decode(${propName}, ${mn}, ${mx}, ${bits});`)
    lines.push(`${i}${i}set { ${backing} = value; ${propName} = Quantize.Encode(value, ${mn}, ${mx}, ${bits}); }`)
    lines.push(`${i}}`)
    lines.push('')
  }

  lines.push(`${i}/// <summary>Clears all cached decoded values. Call after mutating raw uint32 fields directly.</summary>`)
  lines.push(`${i}public void ResetDecodedCache()`)
  lines.push(`${i}{`)
  for (const backing of backings) {
    lines.push(`${i}${i}${backing} = null;`)
  }
  lines.push(`${i}}`)

  lines.push('}')
  return lines
}

// ---------------------------------------------------------------------------
// Per-file code generation (public entry point)
// ---------------------------------------------------------------------------

/**
 * Generate a C# source file for a FileDescriptorProto, or null if the file
 * contains no quantized uint32 fields.
 * @returns {{name: string, content: string} | null}
 */
function generateCsharp(fileProto) {
  const namespace = packageToNamespace(fileProto.package)

  const protoFile = fileProto.name.split('/').pop()
  const stem = snakeToPascal(protoFile.replace('.proto', ''))
  const outName = `${stem}.Bitwise.cs`

  const header = [
    '// <auto-generated>',
    '//   Generated by protoc-gen-bitwise. DO NOT EDIT.',
    `//   Source: ${fileProto.name}`,
    '// </auto-generated>',
    '',
    'using Decentraland.Networking.Bitwise;',
    '',
    `namespace ${namespace}`,
    '{',
  ]
  const footer = ['', `} // namespace ${namespace}`]

  const body = []
  for (const msg of fileProto.messageType) {
    const msgLines = generateMessage(msg)
    if (msgLines === null) continue
    // Indent each line by 4 spaces (inside the namespace block).
    for (const line of msgLines) {
      body.push(line ? '    ' + line : '')
    }
    body.push('')
  }

  if (body.length === 0) return null

  const content = header.concat(body, footer).join('\n') + '\n'
  return { name: outName, content }
}

module.exports = { generateCsharp }
