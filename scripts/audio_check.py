#!/usr/bin/env python3
"""声浪资产体检：缺文件 / 响度 / 真峰值 / 静音 / 接缝 / 亮度趋势。

用法：python3 scripts/audio_check.py [--json out.json]
退出码 1 表示有硬性问题（CI 用它拦住坏素材）。
"""
import glob
import json
import os
import subprocess
import sys

import numpy as np
from scipy.signal import resample_poly, butter, sosfilt, welch

ROOT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio', 'packs')
ROOT = os.path.abspath(ROOT)
BANDS = ['idle', 'low', 'mid', 'high', 'bounce']

# 阈值（可按车型放宽，但默认必须通过）
LUFS_MIN, LUFS_MAX = -20.0, -12.0
TP_MAX = -0.5          # dBTP
SILENCE_MAX = 0.45     # 低于 -60 dBFS 的采样占比
SEAM_RATIO_MAX = 1.2   # 接缝跳变 ≤ 1.2× 内部 p99.9 跳变（离群点基准）
SEAM_ABS_MAX = 0.02    # 或接缝跳变 < 峰值的 2%（-34dBFS 级别，听不出来）
MIN_DUR = 1.0

# 已知素材缺陷（源头缺高频），不在流水线里造假补，明确记录并放行
KNOWN_ISSUES = {
    'mazda_rotary': '源片高转速段本身缺 2kHz 以上内容，10dB 高架也无法补出真实高频',
}


def decode(path, sr=44100):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le',
                          '-ac', '1', '-ar', str(sr), '-'],
                         capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def _biquad_hp(f0, q, fs):
    w0 = 2 * np.pi * f0 / fs
    a = np.sin(w0) / (2 * q)
    c = np.cos(w0)
    b = np.array([(1 + c) / 2, -(1 + c), (1 + c) / 2])
    d = np.array([1 + a, -2 * c, 1 - a])
    return b / d[0], d / d[0]


def _biquad_shelf(f0, q, gain_db, fs):
    A = 10 ** (gain_db / 40.0)
    w0 = 2 * np.pi * f0 / fs
    a = np.sin(w0) / (2 * q)
    c = np.cos(w0)
    sa = 2 * np.sqrt(A) * a
    b = np.array([A * ((A + 1) + (A - 1) * c + sa),
                  -2 * A * ((A - 1) + (A + 1) * c),
                  A * ((A + 1) + (A - 1) * c - sa)])
    d = np.array([(A + 1) - (A - 1) * c + sa,
                  2 * ((A - 1) - (A + 1) * c),
                  (A + 1) - (A - 1) * c - sa])
    return b / d[0], d / d[0]


def k_weight(x, fs=44100):
    b1, a1 = _biquad_hp(38.13547087602444, 0.5003270373238773, fs)
    b2, a2 = _biquad_shelf(1681.974450955533, 0.7071752369554196, 3.999843853973347, fs)
    y = sosfilt(np.array([[b1[0], b1[1], b1[2], 1.0, a1[1], a1[2]]]), x)
    return sosfilt(np.array([[b2[0], b2[1], b2[2], 1.0, a2[1], a2[2]]]), y)


def lufs(x, fs=44100):
    y = k_weight(x, fs)
    blk, hop = int(0.4 * fs), int(0.1 * fs)
    if len(y) < blk:
        return -70.0
    z = np.array([np.mean(y[i:i + blk] ** 2) for i in range(0, len(y) - blk + 1, hop)])
    l = -0.691 + 10 * np.log10(z + 1e-20)
    keep = l > -70.0
    if not keep.any():
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(z[keep])) - 10.0
    keep &= l > rel
    return float(-0.691 + 10 * np.log10(np.mean(z[keep]))) if keep.any() else -70.0


def true_peak(x, fs=44100):
    return float(20 * np.log10(np.max(np.abs(resample_poly(x, 4, 1))) + 1e-12))


def hf_ratio_db(x, fs=44100):
    f, p = welch(x, fs=fs, nperseg=min(4096, len(x)))
    m = (f > 1500) & (f < 10000)
    return float(10 * np.log10(np.sum(p[m]) / (np.sum(p) + 1e-20) + 1e-20))


def centroid(x, fs=44100):
    f, p = welch(x, fs=fs, nperseg=min(4096, len(x)))
    m = p > 0
    return float(np.sum(f[m] * p[m]) / np.sum(p[m])) if m.any() else 0.0


def seam_ratio(x):
    """循环接缝跳变 / 内部 p99.9 跳变。

    用离群分位而非 p95：鼓点/排气脉冲这类冲激信号内部本来就有大量大跳变，
    p95 会把正常瞬态当成噪声底，导致误报。p99.9 只描述"最尖的那批"，接缝跳变
    若真有问题（咔哒声）会明显超过它。
    """
    d = np.abs(np.diff(x))
    if len(d) < 400:
        return 99.0
    seam = abs(x[0] - x[-1])
    ref = np.percentile(d, 99.9) + 1e-9
    return float(seam / ref)


def check_band(path):
    x = decode(path)
    fs = 44100
    dur = len(x) / fs
    seam_abs = float(abs(x[0] - x[-1]) / (np.max(np.abs(x)) + 1e-9))
    r = {
        'dur': round(dur, 2),
        'lufs': round(lufs(x), 1),
        'tp': round(true_peak(x), 2),
        'centroid': round(centroid(x)),
        'hf': round(hf_ratio_db(x), 1),
        'seam': round(seam_ratio(x), 2),
        'seam_abs': round(seam_abs, 4),
        'silence': round(float(np.mean(np.abs(x) < 1e-3)), 3),
    }
    problems = []
    if dur < MIN_DUR:
        problems.append('过短')
    if not (LUFS_MIN <= r['lufs'] <= LUFS_MAX):
        problems.append(f"响度{r['lufs']}")
    if r['tp'] > TP_MAX:
        problems.append(f"峰值{r['tp']}")
    if r['silence'] > SILENCE_MAX:
        problems.append(f"静音{int(r['silence'] * 100)}%")
    if r['seam'] > SEAM_RATIO_MAX and r['seam_abs'] > SEAM_ABS_MAX:
        problems.append(f"接缝{r['seam']}/{r['seam_abs'] * 100:.1f}%")
    return r, problems


def check_integrity(manifest):
    """清单 ↔ 文件树一致性：不缺、不多、不留旧格式循环文件。"""
    fails = []
    ids = [p['id'] for p in manifest['packs'] if not p.get('synthOnly')]
    if len(ids) != len(set(ids)):
        fails.append('manifest: pack id 重复')
    expected = {os.path.join(pid, q, f'loop_{b}.flac')
                for pid in ids for q in ('hi', 'lo') for b in BANDS}
    on_disk = set()
    for path in glob.glob(os.path.join(ROOT, '*', '*', 'loop_*.*')):
        rel = os.path.relpath(path, ROOT)
        if rel.endswith('.flac'):
            on_disk.add(rel)
        else:
            fails.append(f'旧格式循环文件未清理: {rel}')
    for rel in sorted(expected - on_disk):
        fails.append(f'清单有、磁盘缺: {rel}')
    for rel in sorted(on_disk - expected):
        fails.append(f'磁盘有、清单无: {rel}')
    return fails, len(expected)


def main():
    manifest = json.load(open(os.path.join(ROOT, 'manifest.json')))
    rows, fails = [], []
    integrity_fails, n_exp = check_integrity(manifest)
    fails.extend(integrity_fails)
    print(f'清单完整性：{n_exp} 个循环文件')
    for p in manifest['packs']:
        if p.get('synthOnly'):
            continue
        pid = p['id']
        cents = {}
        hfs = {}
        for b in BANDS:
            for q in ('hi', 'lo'):
                path = os.path.join(ROOT, pid, q, f'loop_{b}.flac')
                if not os.path.exists(path):
                    fails.append(f'{pid}/{q}/{b}: 缺文件')
                    continue
                r, problems = check_band(path)
                if q == 'hi':
                    cents[b] = r['centroid']
                    hfs[b] = r['hf']
                if problems:
                    fails.append(f'{pid}/{q}/{b}: ' + ','.join(problems))
                rows.append(dict(pack=pid, q=q, band=b, **r))
        # 亮度趋势：高档的高频能量占比必须高于中档（怠速允许有机械噪声，不强制递减）
        if 'mid' in hfs and 'high' in hfs and hfs['high'] < hfs['mid'] - 1.0:
            if pid in KNOWN_ISSUES:
                print(f'  ! {pid}: 亮度已知缺陷，放行（{KNOWN_ISSUES[pid]}）')
            else:
                fails.append(f"{pid}: 高档不够亮 mid={hfs['mid']}dB high={hfs['high']}dB")
    json.dump(rows, open('/tmp/audio_check.json', 'w'), ensure_ascii=False, indent=1)
    bad = len(fails)
    print(f'检查 {len(rows)} 个 band 文件，问题 {bad} 条')
    for f in fails:
        print('  ✗', f)
    if '--json' in sys.argv:
        json.dump({'rows': rows, 'fails': fails},
                  open(sys.argv[sys.argv.index('--json') + 1], 'w'),
                  ensure_ascii=False, indent=1)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
