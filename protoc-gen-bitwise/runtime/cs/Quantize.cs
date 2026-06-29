// Decentraland.Networking.Bitwise — Quantize
// Copy this file into your project alongside generated *.Bitwise.cs files.
// ReSharper disable once RedundantUsingDirective

using System;

namespace Decentraland.Networking.Bitwise
    // ReSharper disable once ArrangeNamespaceBody
{
    /// <summary>
    ///     Static helpers for quantizing float values to/from unsigned integers.
    ///     Intended for use with protobuf uint32 fields: the integer is transmitted
    ///     as a protobuf varint, while the float accessor lives in a generated partial class.
    /// </summary>
    public static class Quantize
    {
        /// <summary>
        ///     Encodes <paramref name="value" /> to a quantized <see cref="uint" />.
        ///     Values outside [<paramref name="min" />, <paramref name="max" />] are clamped.
        /// </summary>
        public static uint Encode(float value, float min, float max, int bits)
        {
            var steps = (1u << bits) - 1;
            var t = Math.Clamp((value - min) / (max - min), 0f, 1f);
            return (uint)MathF.Round(t * steps);
        }

        /// <summary>Decodes a quantized <see cref="uint" /> back to a float.</summary>
        public static float Decode(uint encoded, float min, float max, int bits)
        {
            var steps = (1u << bits) - 1;
            return (float)encoded / steps * (max - min) + min;
        }

        /// <summary>
        ///     Encodes <paramref name="value" /> with a power-law curve into a sign bit plus an
        ///     (<paramref name="bits" /> - 1)-bit linear unorm magnitude. The magnitude is
        ///     <c>(|value| / max)^(1/pow)</c>, so the inverse <see cref="DecodePower" /> reconstructs
        ///     <c>sign * max * u^pow</c>. Zero is representable exactly; <paramref name="pow" /> &gt; 1
        ///     concentrates resolution near zero. Magnitudes outside [0, <paramref name="max" />] are
        ///     clamped.
        /// </summary>
        public static uint EncodePower(float value, float max, float pow, int bits)
        {
            var magnitudeSteps = (1u << (bits - 1)) - 1;
            var t = Math.Clamp(MathF.Abs(value) / max, 0f, 1f);
            var u = MathF.Pow(t, 1f / pow);
            var magnitude = (uint)MathF.Round(u * magnitudeSteps);
            var sign = value < 0f ? 1u << (bits - 1) : 0u;
            return sign | magnitude;
        }

        /// <summary>Decodes a power-law quantized <see cref="uint" /> back to a float (inverse of
        /// <see cref="EncodePower" />).</summary>
        public static float DecodePower(uint encoded, float max, float pow, int bits)
        {
            var signBit = 1u << (bits - 1);
            var magnitudeSteps = signBit - 1;
            var u = (float)(encoded & magnitudeSteps) / magnitudeSteps;
            var magnitude = max * MathF.Pow(u, pow);
            return (encoded & signBit) != 0 ? -magnitude : magnitude;
        }
    }
}
