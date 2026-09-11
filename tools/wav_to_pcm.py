#!/usr/bin/env python3
"""
wav_to_pcm.py  -  Convert a WAV file to 8-bit signed mono PCM for Amiga Paula.

Usage:
    py tools/wav_to_pcm.py <input.wav> <output.raw> [--rate RATE]

Default sample rate: 8000 Hz
Output: 8-bit signed mono, padded to even length (Paula requires word-aligned AUDxLEN).

Paula setup (PAL Amiga):
    AUD0LCH/L = <output.raw address>
    AUD0LEN   = <file_size_bytes / 2>        (word count)
    AUD0PER   = 3546895 / RATE               (e.g. 443 for 8000 Hz)
    AUD0VOL   = 40
"""

import wave
import array
import struct
import sys
import argparse


def convert(input_path, output_path, target_rate=8000):
    with wave.open(input_path, 'rb') as w:
        channels   = w.getnchannels()
        src_rate   = w.getframerate()
        samp_width = w.getsampwidth()
        num_frames = w.getnframes()
        raw        = w.readframes(num_frames)

    total_samples = num_frames * channels

    if samp_width == 1:
        # WAV 8-bit is unsigned 0-255 → shift to signed -128..127
        samples = [b - 128 for b in raw]
        scale   = 1.0
    elif samp_width == 2:
        samples = list(array.array('h', raw))   # signed 16-bit LE
        scale   = 1.0 / 256                     # >> 8 to reach 8-bit range
    elif samp_width == 3:
        # 24-bit signed LE — unpack as 32-bit then shift
        samples = []
        for i in range(total_samples):
            b = raw[i*3 : i*3+3]
            val = struct.unpack('<i', b + (b'\xff' if b[2] & 0x80 else b'\x00'))[0]
            samples.append(val)
        scale = 1.0 / 65536                     # >> 16 to reach 8-bit range
    elif samp_width == 4:
        # Could be 32-bit int or 32-bit float — detect by WAV format tag via raw header
        # Python's wave module doesn't expose the format tag, so try float first:
        # if values are all in [-1.0, 1.0] range treat as float, else as int32.
        int32s = list(array.array('i', raw))    # try as signed 32-bit int
        # Heuristic: 32-bit float WAVs typically have format tag 3 (IEEE_FLOAT).
        # Python's wave module only reads PCM (tag 1), so if wave.open succeeded
        # the file claims to be PCM — treat as int32.
        try:
            floats = list(struct.unpack_from(f'<{total_samples}f', raw))
            if all(-2.0 <= v <= 2.0 for v in floats[:min(1000, len(floats))]):
                samples = [int(v * 127) for v in floats]
                scale   = 1.0
            else:
                samples = int32s
                scale   = 1.0 / 16777216        # >> 24 to reach 8-bit range
        except Exception:
            samples = int32s
            scale   = 1.0 / 16777216
    else:
        sys.exit(f"Unsupported sample width: {samp_width} bytes  "
                 f"(supported: 8-bit, 16-bit, 24-bit, 32-bit int, 32-bit float)")

    # Mix down to mono
    if channels == 2:
        mono = [(samples[i * 2] + samples[i * 2 + 1]) / 2 for i in range(num_frames)]
    else:
        mono = samples[:num_frames]

    # Downsample
    if src_rate % target_rate == 0:
        step = src_rate // target_rate
        downsampled = mono[::step]
    else:
        ratio = src_rate / target_rate
        out_len = int(num_frames / ratio)
        downsampled = [mono[min(int(i * ratio), len(mono) - 1)] for i in range(out_len)]

    # Convert to 8-bit signed
    def to_s8(v):
        s = int(v * scale) if scale != 1.0 else int(v)
        return max(-128, min(127, s)) & 0xFF

    pcm8 = bytes(to_s8(s) for s in downsampled)

    # Pad to even length (Paula AUDxLEN is in words)
    if len(pcm8) % 2:
        pcm8 += b'\x00'

    with open(output_path, 'wb') as f:
        f.write(pcm8)

    pal_period = 3546895 // target_rate
    word_count = len(pcm8) // 2
    duration   = len(pcm8) / target_rate
    print(f"Input:  {input_path}")
    print(f"        {channels}ch, {src_rate} Hz, {samp_width*8}-bit, {num_frames} frames")
    print(f"Output: {output_path}")
    print(f"        {len(pcm8)} bytes ({len(pcm8)//1024} KB), {duration:.2f}s at {target_rate} Hz")
    print(f"Paula:  AUD0PER={pal_period} (PAL {target_rate} Hz), AUD0LEN={word_count}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('input',  help='Source WAV file')
    parser.add_argument('output', help='Destination .raw file')
    parser.add_argument('--rate', type=int, default=8000,
                        help='Target sample rate in Hz (default: 8000)')
    args = parser.parse_args()
    convert(args.input, args.output, args.rate)
