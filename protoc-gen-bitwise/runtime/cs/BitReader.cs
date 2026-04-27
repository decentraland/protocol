// Decentraland.Networking.Bitwise — BitReader
// Copy this file into your Unity project alongside generated *.Bitwise.cs files.

using System;

namespace Decentraland.Networking.Bitwise
{
    /// <summary>
    /// Reads bits from a byte buffer, MSB first within each byte (big-endian bit
    /// order).  Symmetric counterpart of <see cref="BitWriter"/>: every
    /// Write… call has a corresponding Read… call with identical arguments that
    /// reproduces the original value.
    /// </summary>
    public sealed class BitReader
    {
        private readonly byte[] _buffer;
        private int _bitPos;

        /// <param name="buffer">Source buffer filled by a <see cref="BitWriter"/>.</param>
        public BitReader(byte[] buffer)
        {
            _buffer = buffer ?? throw new ArgumentNullException(nameof(buffer));
            _bitPos = 0;
        }

        /// <summary>Current read position in bits.</summary>
        public int BitPosition => _bitPos;

        /// <summary>
        /// Returns <c>true</c> when all written bits have been consumed
        /// (i.e. <see cref="BitPosition"/> has reached the end of the buffer).
        /// </summary>
        public bool IsAtEnd => _bitPos >= _buffer.Length * 8;

        // -----------------------------------------------------------------
        // Core primitive
        // -----------------------------------------------------------------

        /// <summary>
        /// Reads <paramref name="bits"/> bits and returns them as the
        /// least-significant bits of a <see cref="uint"/>, MSB first.
        /// </summary>
        public uint ReadBits(int bits)
        {
            uint value = 0;
            for (int i = bits - 1; i >= 0; i--)
            {
                int byteIdx = _bitPos / 8;
                int bitIdx  = 7 - (_bitPos % 8);

                if ((_buffer[byteIdx] >> bitIdx & 1) == 1)
                    value |= 1u << i;

                _bitPos++;
            }
            return value;
        }

        // -----------------------------------------------------------------
        // Quantized float
        // -----------------------------------------------------------------

        /// <summary>
        /// Reads a quantized float encoded with <see cref="BitWriter.WriteQuantizedFloat"/>.
        /// Arguments must match those used during encoding exactly.
        /// </summary>
        public float ReadQuantizedFloat(float min, float max, int bits)
        {
            uint  maxQ       = (1u << bits) - 1;
            uint  quantized  = ReadBits(bits);
            float normalized = (float)quantized / maxQ;
            return min + normalized * (max - min);
        }

        // -----------------------------------------------------------------
        // Standard IEEE 754 helpers
        // -----------------------------------------------------------------

        /// <summary>Reads a 32-bit IEEE 754 float written by <see cref="BitWriter.WriteFloat"/>.</summary>
        public float ReadFloat()
        {
            uint bits = ReadBits(32);
            byte[] bytes =
            {
                (byte)(bits        & 0xFF),
                (byte)((bits >> 8)  & 0xFF),
                (byte)((bits >> 16) & 0xFF),
                (byte)((bits >> 24) & 0xFF),
            };
            return BitConverter.ToSingle(bytes, 0);
        }

        /// <summary>Reads a 64-bit IEEE 754 double written by <see cref="BitWriter.WriteDouble"/>.</summary>
        public double ReadDouble()
        {
            uint hi = ReadBits(32);
            uint lo = ReadBits(32);
            byte[] bytes =
            {
                (byte)(lo         & 0xFF),
                (byte)((lo >> 8)  & 0xFF),
                (byte)((lo >> 16) & 0xFF),
                (byte)((lo >> 24) & 0xFF),
                (byte)(hi         & 0xFF),
                (byte)((hi >> 8)  & 0xFF),
                (byte)((hi >> 16) & 0xFF),
                (byte)((hi >> 24) & 0xFF),
            };
            return BitConverter.ToDouble(bytes, 0);
        }
    }
}
