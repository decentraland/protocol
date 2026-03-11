"""
C# code generator for the protoc-gen-bitwise plugin.

For every proto message that contains at least one uint32 field annotated with
[(quantized)], this module emits a C# partial class that adds a computed float
property named {FieldName}Quantized.  The getter decodes the stored uint32 to
a float; the setter encodes a float back to a uint32.  Standard protobuf
handles serialization of the uint32 wire field; this class adds a typed float
accessor on top.

Protobuf encodes small uint32 values via varint, so a value that fits in
2^20 costs 3 bytes on the wire — cheaper than a raw IEEE 754 float (4 bytes).

Only uint32 fields are supported.  bit_packed and unannotated fields are
passed through without generating any accessor.
"""

from google.protobuf import descriptor_pb2

from options_pb2 import get_field_options

# FieldDescriptorProto type constants (aliased for readability)
_FT = descriptor_pb2.FieldDescriptorProto


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _snake_to_pascal(name: str) -> str:
    """position_x → PositionX"""
    return ''.join(word.capitalize() for word in name.split('_'))


def _package_to_namespace(package: str) -> str:
    """decentraland.kernel.comms.v3 → Decentraland.Kernel.Comms.V3"""
    if not package:
        return 'Generated'
    return '.'.join(part.capitalize() for part in package.split('.'))


def _format_float(value: float) -> str:
    """Format a Python float as a C# float literal (e.g. -100.0f)."""
    text = f'{value:.8g}'
    if '.' not in text and 'e' not in text and 'E' not in text:
        text += '.0'
    return text + 'f'


def _format_step(step: float) -> str:
    """Format a quantization step size for display in a doc comment (e.g. ≈ 0.003)."""
    return f'\u2248 {step:.6g}'


# ---------------------------------------------------------------------------
# Per-message code generation
# ---------------------------------------------------------------------------

def _gen_message(msg_proto, indent: str = '    ') -> list[str] | None:
    """
    Generate a C# partial class for a proto message.

    For each uint32 field with a [(quantized)] annotation, emits a cached float
    property {FieldName}Quantized backed by the raw uint32 field.

    Returns a list of lines (without trailing newline) or None if the message
    has no quantized uint32 fields.
    """
    props: list[tuple[str, str, str, int, float]] = []  # (prop_name, mn, mx, bits, step)

    for field in msg_proto.field:
        # Repeated/map fields are not supported
        if field.label == _FT.LABEL_REPEATED:
            continue

        # Only uint32 fields are candidates for quantized accessors
        if field.type != _FT.TYPE_UINT32:
            continue

        quantized, _ = get_field_options(field.options)
        if quantized is None:
            continue

        step = (quantized.max - quantized.min) / ((1 << quantized.bits) - 1)

        props.append((
            _snake_to_pascal(field.name),
            _format_float(quantized.min),
            _format_float(quantized.max),
            quantized.bits,
            step,
        ))

    if not props:
        return None

    i = indent
    backings: list[str] = []
    lines: list[str] = []
    lines.append(f'public partial class {msg_proto.name}')
    lines.append('{')

    for prop_name, mn, mx, bits, step in props:
        backing = '_' + prop_name[0].lower() + prop_name[1:]
        backings.append(backing)
        lines.append(f'{i}private float? {backing};')
        lines.append(f'{i}/// <summary>Float accessor for <see cref="{prop_name}"/>. Range [{mn}, {mx}], {bits} bits, step {_format_step(step)}.</summary>')
        lines.append(f'{i}public float {prop_name}Quantized')
        lines.append(f'{i}{{')
        lines.append(f'{i}{i}get => {backing} ??= Quantize.Decode({prop_name}, {mn}, {mx}, {bits});')
        lines.append(f'{i}{i}set {{ {backing} = value; {prop_name} = Quantize.Encode(value, {mn}, {mx}, {bits}); }}')
        lines.append(f'{i}}}')
        lines.append('')

    lines.append(f'{i}/// <summary>Clears all cached decoded values. Call after mutating raw uint32 fields directly.</summary>')
    lines.append(f'{i}public void ResetDecodedCache()')
    lines.append(f'{i}{{')
    for backing in backings:
        lines.append(f'{i}{i}{backing} = null;')
    lines.append(f'{i}}}')

    lines.append('}')
    return lines


# ---------------------------------------------------------------------------
# Per-file code generation (public entry point)
# ---------------------------------------------------------------------------

def generate_csharp(file_proto) -> dict | None:
    """
    Generate a C# source file for a FileDescriptorProto.

    Returns a dict with keys 'name' (output path) and 'content' (C# source),
    or None if the file contains no quantized uint32 fields.
    """
    namespace = _package_to_namespace(file_proto.package)

    # Output is placed flat in the output root, matching --csharp_out convention.
    # e.g. "decentraland/kernel/comms/v3/my_message.proto"
    #    → "MyMessage.Bitwise.cs"
    proto_file = file_proto.name.rsplit('/', 1)[-1]
    stem = _snake_to_pascal(proto_file.replace('.proto', ''))
    out_name = f'{stem}.Bitwise.cs'

    header = [
        '// <auto-generated>',
        '//   Generated by protoc-gen-bitwise. DO NOT EDIT.',
        f'//   Source: {file_proto.name}',
        '// </auto-generated>',
        '',
        'using Decentraland.Networking.Bitwise;',
        '',
        f'namespace {namespace}',
        '{',
    ]
    footer = [
        '',
        f'}} // namespace {namespace}',
    ]

    body: list[str] = []
    for msg in file_proto.message_type:
        msg_lines = _gen_message(msg)
        if msg_lines is None:
            continue
        # Indent each line by 4 spaces (inside the namespace block)
        for line in msg_lines:
            body.append(('    ' + line) if line else '')
        body.append('')

    if not body:
        return None  # nothing to emit

    content = '\n'.join(header + body + footer) + '\n'
    return {'name': out_name, 'content': content}
