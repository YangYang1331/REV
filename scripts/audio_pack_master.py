#!/usr/bin/env python3
"""音频采样包母带处理（v2.17.7）。

对 assets/audio/packs/<pack>/{hi,lo}/loop_*.flac 做三件事：
  1) 去掉直流偏置；
  2) 接缝体检：原接缝 > 峰值的 2% 才做 80ms 等功率交叉淡化，避免把循环点
     挪到排气脉冲上；多数源片本身剪得干净，保持原样；
  3) 用 ebur128 量响度后加固定增益，统一到 -16 LUFS / True Peak -1.5 dB，
     消除包间响度差（短循环上比 loudnorm 两遍法稳定）。

不改变采样率/声道数，不重采样；只重写 flac（16-bit）。
用法：python3 scripts/audio_pack_master.py [--dry-run]
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKS = os.path.join(ROOT, "assets", "audio", "packs")
BANDS = ("idle", "low", "mid", "high", "bounce")
TARGET_I = -16.0
TARGET_TP = -1.5
TARGET_LRA = 11.0
XFADE_SEC = 0.08
MAX_XFADE_FRAC = 0.02


def probe(path: str) -> tuple[int, int, int]:
    out = subprocess.check_output(
        [
            "ffprobe", "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=sample_rate,channels,bits_per_raw_sample",
            "-of", "json", path,
        ],
        text=True,
    )
    s = json.loads(out)["streams"][0]
    return int(s["sample_rate"]), int(s["channels"]), int(s.get("bits_per_raw_sample") or 16)


def decode(path: str, sr: int, ch: int) -> bytes:
    return subprocess.check_output(
        [
            "ffmpeg", "-v", "error", "-i", path,
            "-f", "f32le", "-acodec", "pcm_f32le", "-ac", str(ch), "-ar", str(sr), "-",
        ]
    )


def clean_loop(pcm, ch: int, sr: int):
    """去直流；仅当原接缝确实过大时才做首尾交叉淡化。

    多数源片本身就是在零交叉处剪的（接缝 < 峰值的 2%），强行淡化反而会把
    循环点挪到某个排气脉冲上，制造新的咔哒声。这里先量原接缝，只有超过
    2% 才处理，并在目标长度附近挑一个相邻采样差最小的切点。
    """
    import numpy as np

    n = len(pcm) // (4 * ch)
    if n < 16:
        return pcm
    x = np.frombuffer(pcm, dtype=np.float32).reshape(n, ch).astype(np.float32)
    # 去直流（逐声道），避免循环边界直流台阶。
    x = x - x.mean(axis=0, keepdims=True)
    peak = float(np.abs(x).max()) + 1e-9
    seam_abs = float(np.abs(x[0] - x[-1]).max()) / peak
    if seam_abs <= 0.02:
        return x.astype(np.float32).tobytes()

    target = min(int(sr * XFADE_SEC), int(n * MAX_XFADE_FRAC))
    lo = max(8, int(target * 0.5))
    hi = min(n // 4, max(lo, int(target * 2.0)))
    best_f = target
    best_d = float("inf")
    for f in range(lo, hi + 1):
        d = float(np.abs(x[n - f] - x[n - f - 1]).max())
        if d < best_d:
            best_d = d
            best_f = f
    f = best_f
    if f < 8:
        return x.astype(np.float32).tobytes()
    y = x[: n - f].copy()
    # 结尾 f 帧叠到开头，等功率交叉，循环点连续。
    t = np.linspace(0.0, 1.0, f, dtype=np.float32)[:, None]
    fin = np.sin(t * np.pi * 0.5)
    fout = np.cos(t * np.pi * 0.5)
    y[:f] = x[:f] * fin + x[n - f:] * fout
    return y.astype(np.float32).tobytes()


def measure_loudness(raw: bytes, sr: int, ch: int) -> tuple[float, float]:
    """用 ebur128 量整段响度与真峰值，返回 (LUFS, dBTP)。

    loudnorm 两遍法在 2~4s 的短循环上会算出错误的 target_offset
    （实测把 -16 LUFS 的素材压到 -46 LUFS），这里改成先测量再加固定增益，
    结果可预测且不会破坏动态。
    """
    proc = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-nostats",
            "-f", "f32le", "-ar", str(sr), "-ac", str(ch), "-i", "pipe:0",
            "-af", "ebur128=peak=true",
            "-f", "null", "-",
        ],
        input=raw, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )
    err = proc.stderr.decode("utf-8", "ignore")
    i = re.findall(r"I:\s*(-?\d+(?:\.\d+)?)\s*LUFS", err)
    p = re.findall(r"Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS", err)
    if not i or not p:
        raise RuntimeError("ebur128 measure failed:\n" + err[-800:])
    return float(i[-1]), float(p[-1])


def apply_gain(raw: bytes, sr: int, ch: int, out_path: str, gain_db: float) -> None:
    subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y",
            "-f", "f32le", "-ar", str(sr), "-ac", str(ch), "-i", "pipe:0",
            "-af", f"volume={gain_db:.2f}dB",
            "-ar", str(sr), "-ac", str(ch),
            "-c:a", "flac", "-sample_fmt", "s16", out_path,
        ],
        input=raw,
        check=True,
    )


def main() -> int:
    dry = "--dry-run" in sys.argv
    skip_packs = {"video_cockpit", "video_cruise"}
    total = 0
    for pack in sorted(os.listdir(PACKS)):
        pdir = os.path.join(PACKS, pack)
        if not os.path.isdir(pdir) or pack in skip_packs:
            continue
        for variant in ("hi", "lo"):
            vdir = os.path.join(pdir, variant)
            if not os.path.isdir(vdir):
                continue
            for band in BANDS:
                path = os.path.join(vdir, f"loop_{band}.flac")
                if not os.path.exists(path):
                    continue
                sr, ch, _ = probe(path)
                raw = decode(path, sr, ch)
                raw = clean_loop(raw, ch, sr)
                if dry:
                    print(f"[dry] {pack}/{variant}/loop_{band}.flac sr={sr} ch={ch}")
                    total += 1
                    continue
                meas = measure_loudness(raw, sr, ch)
                lufs, tp = meas
                gain = TARGET_I - lufs
                gain = min(gain, TARGET_TP - tp)
                gain = max(-24.0, min(24.0, gain))
                fd, tmp = tempfile.mkstemp(suffix=".flac")
                os.close(fd)
                try:
                    apply_gain(raw, sr, ch, tmp, gain)
                    os.replace(tmp, path)
                finally:
                    if os.path.exists(tmp):
                        os.unlink(tmp)
                total += 1
                print(
                    f"{pack:22s} {variant} {band:6s} "
                    f"I={lufs:6.1f} gain={gain:+5.1f}dB -> {TARGET_I:.0f} LUFS"
                )
    print(f"done: {total} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
