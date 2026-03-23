// Decentraland.Networking.Bitwise — BitWriter
// Copy this file into your Unity project alongside generated *.Bitwise.cs files.

using System;

namespace Decentraland.Networking.Bitwise
{
    /// <summary>
    /// Writes bits into a pre-allocated byte buffer, MSB first within each byte
    /// (big-endian bit order).  This matches the layout expected by
    /// <see cref="BitReader"/> so that encode → decode is always a round-trip no-op.
    /// </summary>
    public sealed class BitWriter
    {
        private readonly byte[] _buffer;
        private int _bitPos;

        /// <param name="buffer">Destination buffer (must be large enough for all writes).</param>
        public BitWriter(byte[] buffer)
        {
            _buffer = buffer ?? throw new ArgumentNullException(nameof(buffer));
            _bitPos = 0;
        }

        /// <summary>Current write position in bits.</summary>
        public int BitPosition => _bitPos;

        /// <summary>Number of bytes written (rounded up to the nearest byte).</summary>
        public int ByteLength => (_bitPos + 7) / 8;

        /// <summary>Returns a copy of the written bytes (trimmed to <see cref="ByteLength"/>).</summary>
        public byte[] ToArray()
        {
            var result = new byte[ByteLength];
            Array.Copy(_buffer, result, ByteLength);
            return result;
        }

        // -----------------------------------------------------------------
        // Core primitive
        // -----------------------------------------------------------------

        /// <summary>
        /// Writes the <paramref name="bits"/> least-significant bits of
        /// <paramref name="value"/>, MSB first.
        /// </summary>
        public void WriteBits(uint value, int bits)
        {
            for (int i = bits - 1; i >= 0; i--)
            {
                int byteIdx = _bitPos / 8;
                int bitIdx  = 7 - (_bitPos % 8);

                if ((value >> i & 1u) == 1u)
                    _buffer[byteIdx] |=  (byte)(1 << bitIdx);
                else
                    _buffer[byteIdx] &= (byte)~(1 << bitIdx);

                _bitPos++;
            }
        }

        // -----------------------------------------------------------------
        // Quantized float
        // -----------------------------------------------------------------

        /// <summary>
        /// Quantizes <paramref name="value"/> into <paramref name="bits"/> bits
        /// using the range [<paramref name="min"/>, <paramref name="max"/>] and
        /// writes it to the buffer.
        ///
        /// Uses <c>Math.Round</c> (banker's rounding → ties-to-even) to guarantee
        /// that encode → decode is a round-trip no-op.
        /// </summary>
        public void WriteQuantizedFloat(float value, float min, float max, int bits)
        {
            uint  maxQ       = (1u << bits) - 1;
            float clamped    = Math.Clamp(value, min, max);
            float normalized = (clamped - min) / (max - min);
            uint  quantized  = (uint)Math.Round(normalized * maxQ);
            WriteBits(quantized, bits);
        }

        // -----------------------------------------------------------------
        // Standard IEEE 754 helpers (used for un-annotated float/double fields)
        // -----------------------------------------------------------------

        /// <summary>Writes a 32-bit IEEE 754 float (4 bytes).</summary>
        public void WriteFloat(float value)
        {
            byte[] bytes = BitConverter.GetBytes(value);
            // GetBytes is little-endian on all platforms; write MSB first.
            uint bits = (uint)bytes[0]
                      | ((uint)bytes[1] << 8)
                      | ((uint)bytes[2] << 16)
                      | ((uint)bytes[3] << 24);
            WriteBits(bits, 32);
        }

        /// <summary>Writes a 64-bit IEEE 754 double (8 bytes).</summary>
        public void WriteDouble(double value)
        {
            byte[] bytes = BitConverter.GetBytes(value);
            uint lo = (uint)bytes[0]
                    | ((uint)bytes[1] << 8)
                    | ((uint)bytes[2] << 16)
                    | ((uint)bytes[3] << 24);
            uint hi = (uint)bytes[4]
                    | ((uint)bytes[5] << 8)
                    | ((uint)bytes[6] << 16)
                    | ((uint)bytes[7] << 24);
            // Write high 32 bits first so the bit stream is big-endian at word level too.
            WriteBits(hi, 32);
            WriteBits(lo, 32);
        }
    }
}
