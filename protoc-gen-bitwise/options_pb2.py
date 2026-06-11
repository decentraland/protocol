"""
Manual parser for the custom bitwise field options defined in options.proto.

Rather than relying on protobuf extension registration (which requires a properly
compiled _pb2 module), this module parses the raw serialized FieldOptions bytes
directly using the protobuf binary wire format.  All protobuf runtimes preserve
unknown/unregistered extension bytes when round-tripping, so
field.options.SerializeToString() always contains the extension data even when
the extension is not registered in the Python runtime.

Wire format reference:
  tag  = (field_number << 3) | wire_type
  wire_type 0 = varint, 1 = 64-bit, 2 = length-delimited, 5 = 32-bit
"""

import struct

# Extension field numbers as defined in options.proto
QUANTIZED_FIELD_NUMBER = 50001
BIT_PACKED_FIELD_NUMBER = 50002


# ---------------------------------------------------------------------------
# Low-level wire-format helpers
# ---------------------------------------------------------------------------

def _read_varint(data: bytes, pos: int):
    """Decode a protobuf varint starting at *pos*. Returns (value, new_pos)."""
    result = 0
    shift = 0
    while pos < len(data):
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if not (byte & 0x80):
            break
        shift += 7
    return result, pos


def _read_float32(data: bytes, pos: int):
    """Decode a little-endian 32-bit float. Returns (value, new_pos)."""
    value, = struct.unpack_from('<f', data, pos)
    return value, pos + 4


def _skip_field(data: bytes, pos: int, wire_type: int) -> int:
    """Advance *pos* past a field with the given wire_type."""
    if wire_type == 0:
        _, pos = _read_varint(data, pos)
    elif wire_type == 1:
        pos += 8
    elif wire_type == 2:
        length, pos = _read_varint(data, pos)
        pos += length
    elif wire_type == 5:
        pos += 4
    # wire types 3 and 4 (start/end group) are deprecated; skip gracefully
    return pos


# ---------------------------------------------------------------------------
# Option message classes
# ---------------------------------------------------------------------------

class QuantizedFloatOptions:
    """Mirrors the QuantizedFloatOptions proto message."""

    __slots__ = ('min', 'max', 'bits')

    def __init__(self, min_val: float = 0.0, max_val: float = 0.0, bits: int = 0):
        self.min = min_val
        self.max = max_val
        self.bits = bits

    @classmethod
    def from_bytes(cls, data: bytes) -> 'QuantizedFloatOptions':
        obj = cls()
        pos = 0
        while pos < len(data):
            tag, pos = _read_varint(data, pos)
            field_num = tag >> 3
            wire_type = tag & 0x7
            if field_num == 1 and wire_type == 5:    # min  (float)
                obj.min, pos = _read_float32(data, pos)
            elif field_num == 2 and wire_type == 5:  # max  (float)
                obj.max, pos = _read_float32(data, pos)
            elif field_num == 3 and wire_type == 0:  # bits (uint32)
                obj.bits, pos = _read_varint(data, pos)
            else:
                pos = _skip_field(data, pos, wire_type)
        return obj

    def __repr__(self):
        return f'QuantizedFloatOptions(min={self.min}, max={self.max}, bits={self.bits})'


class BitPackedOptions:
    """Mirrors the BitPackedOptions proto message."""

    __slots__ = ('bits',)

    def __init__(self, bits: int = 0):
        self.bits = bits

    @classmethod
    def from_bytes(cls, data: bytes) -> 'BitPackedOptions':
        obj = cls()
        pos = 0
        while pos < len(data):
            tag, pos = _read_varint(data, pos)
            field_num = tag >> 3
            wire_type = tag & 0x7
            if field_num == 1 and wire_type == 0:    # bits (uint32)
                obj.bits, pos = _read_varint(data, pos)
            else:
                pos = _skip_field(data, pos, wire_type)
        return obj

    def __repr__(self):
        return f'BitPackedOptions(bits={self.bits})'


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def get_field_options(field_options_proto):
    """
    Extract custom bitwise options from a FieldDescriptorProto.options object.

    Serialises the options message to bytes and walks the wire-format stream
    looking for extension fields 50001 (quantized) and 50002 (bit_packed).

    Args:
        field_options_proto: google.protobuf.descriptor_pb2.FieldOptions instance
            (may be a default/empty instance when no options are set).

    Returns:
        tuple[QuantizedFloatOptions | None, BitPackedOptions | None]
    """
    try:
        raw = field_options_proto.SerializeToString()
    except Exception:
        return None, None

    if not raw:
        return None, None

    quantized = None
    bit_packed = None
    pos = 0

    while pos < len(raw):
        tag, pos = _read_varint(raw, pos)
        field_num = tag >> 3
        wire_type = tag & 0x7

        if wire_type == 2:                              # length-delimited
            length, pos = _read_varint(raw, pos)
            value_bytes = raw[pos:pos + length]
            pos += length
            if field_num == QUANTIZED_FIELD_NUMBER:
                quantized = QuantizedFloatOptions.from_bytes(value_bytes)
            elif field_num == BIT_PACKED_FIELD_NUMBER:
                bit_packed = BitPackedOptions.from_bytes(value_bytes)
            # else: unknown length-delimited field — already consumed
        else:
            pos = _skip_field(raw, pos, wire_type)

    return quantized, bit_packed
