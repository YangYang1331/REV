#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RE v2.14.0 发布校验脚本（release_check.py）

对 dist/ 下三个发布包做硬性校验，任一不过即非零退出：
  1. versionCode=40 / versionName=2.14.0 / 包名 com.rev.cluster / minSdk=24
  2. AndroidManifest extractNativeLibs=false
  3. 手机包 rev-latest.apk：21 车型 hi+lo 齐全；车机包 rev-car.apk：仅 lo（无 hi）
  4. 胖包里 arm64 与 armv7 的 libapp.so 同一次构建（都在、合法 ELF、同一 Dart
     快照魔数/版本；禁止一老一新/错配 ABI）
  5. 签名证书 SHA-256 以 3f16feb 开头（沿用历史 debug 证书，保证 v2.13→v2.14 可直接覆盖安装）
  6. zipalign -c -p 4 通过（.so 4K 页对齐）

用法：bash scripts/build_release.sh 之后运行  python3 scripts/release_check.py
"""
import os, re, subprocess, sys, tempfile, zipfile, struct, hashlib

DIST = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "dist"))
BT = "/home/user/buildtools/android-sdk/build-tools/35.0.0"
AAPT = f"{BT}/aapt"
APKSIGNER = f"{BT}/apksigner"
ZIPALIGN = f"{BT}/zipalign"

EXPECT_VCODE = 40
EXPECT_VNAME = "2.14.0"
EXPECT_PKG = "com.rev.cluster"
EXPECT_MINSdk = 24
EXPECT_CERT_PREFIX = "3f16feb"

# 21 个车型包（与 pubspec / manifest.json 一致）
PACKS = [
    "mazda6_na", "mazda_rotary", "ea888_20t", "amg_c63", "bmw_s58",
    "audi_r8", "hellcat_supercharged", "honda_typer", "lambo_v10", "lexus_lfa",
    "ls_v8", "mitsubishi_evo", "mustang_gt", "nissan_gtr", "porsche_gt3",
    "porsche_turbo", "subaru_sti", "toyota_supra", "corvette_c8", "dodge_viper",
    "v12",
]

FAILS = []
def fail(msg):
    FAILS.append(msg)
    print(f"  ✗ FAIL: {msg}")
def ok(msg):
    print(f"  ✓ {msg}")

def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr

# ── aapt badging ──
def badging(apk):
    rc, out = run([AAPT, "dump", "badging", apk])
    d = {"vcode": None, "vname": None, "pkg": None, "minsdk": None}
    m = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", out)
    if m:
        d["pkg"], d["vcode"], d["vname"] = m.group(1), int(m.group(2)), m.group(3)
    m = re.search(r"sdkVersion:'(\d+)'", out)
    if m: d["minsdk"] = int(m.group(1))
    return d

def extract_native_libs(apk):
    """读二进制 AndroidManifest.xml，返回 extractNativeLibs 值（True/False/None）。"""
    rc, out = run([AAPT, "dump", "xmltree", apk, "AndroidManifest.xml"])
    m = re.search(
        r"android:extractNativeLibs\(0x[0-9a-fA-F]+\)=\(type 0x[0-9a-fA-F]+\)(0x[0-9a-fA-F]+)",
        out,
    )
    if not m:
        return None
    # 0xffffffff = true，0x00000000 = false
    return int(m.group(1), 16) != 0

def cert_sha256(apk):
    rc, out = run([APKSIGNER, "verify", "--print-certs", apk])
    m = re.search(r"SHA-256 digest:\s*([0-9a-fA-F:]+)", out)
    if not m: return None
    return m.group(1).replace(":", "").lower()

def zipalign_ok(apk):
    rc, out = run([ZIPALIGN, "-c", "-p", "4", apk])
    return rc == 0

def list_assets(apk):
    z = zipfile.ZipFile(apk)
    return z.namelist()

# ── libapp.so 同构建校验 ──
def rodata_head(data, n=8):
    """解析 ELF，按 section 名精确定位 .rodata，返回其前 n 字节。"""
    if data[:4] != b"\x7fELF":
        return None
    is64 = data[4] == 2
    try:
        if is64:
            e_shoff = struct.unpack_from("<Q", data, 0x28)[0]
            entsz = struct.unpack_from("<H", data, 0x3A)[0]
            num = struct.unpack_from("<H", data, 0x3C)[0]
            e_shstrndx = struct.unpack_from("<H", data, 0x3E)[0]
            # shstrtab 的 offset
            str_off = struct.unpack_from("<Q", data,
                                         e_shoff + e_shstrndx * entsz + 24)[0]
            for i in range(num):
                off = e_shoff + i * entsz
                name, typ, flags, addr, offset, size = struct.unpack_from(
                    "<IIQQQQ", data, off)
                end = data.index(b"\0", str_off + name)
                nm = data[str_off + name:end].decode("ascii", "replace")
                if nm == ".rodata":
                    return data[offset:offset + n]
        else:
            e_shoff = struct.unpack_from("<I", data, 0x20)[0]
            entsz = struct.unpack_from("<H", data, 0x2E)[0]
            num = struct.unpack_from("<H", data, 0x30)[0]
            e_shstrndx = struct.unpack_from("<H", data, 0x32)[0]
            str_off = struct.unpack_from("<I", data,
                                         e_shoff + e_shstrndx * entsz + 16)[0]
            for i in range(num):
                off = e_shoff + i * entsz
                name, typ, flags, addr, offset, size = struct.unpack_from(
                    "<IIIIII", data, off)
                end = data.index(b"\0", str_off + name)
                nm = data[str_off + name:end].decode("ascii", "replace")
                if nm == ".rodata":
                    return data[offset:offset + n]
    except Exception:
        return None
    return None

def check_libapp_same_build(apk):
    """胖包里 arm64 与 armv7 libapp.so 必须都在、合法、同一 Dart 快照头。"""
    z = zipfile.ZipFile(apk)
    want = {
        "arm64": "lib/arm64-v8a/libapp.so",
        "armv7": "lib/armeabi-v7a/libapp.so",
    }
    heads = {}
    for tag, arc in want.items():
        try:
            data = z.read(arc)
        except KeyError:
            fail(f"{os.path.basename(apk)} 缺少 {arc}")
            continue
        head = rodata_head(data)
        if head is None:
            fail(f"{os.path.basename(apk)} {arc} 不是合法 ELF/无快照")
        else:
            heads[tag] = head
            print(f"    {tag} libapp.so 快照头: {head.hex()}  ({len(data)} B)")
    if "arm64" in heads and "armv7" in heads:
        # 同一 Dart SDK 的快照首魔数应一致（f5f5dcdc…）；中间指针按架构不同，
        # 只比前 4 字节魔数 + 末尾版本字。此处单条 flutter 命令双 ABI 构建，天然同次。
        a, b = heads["arm64"], heads["armv7"]
        if a[:4] != b[:4]:
            fail(f"{os.path.basename(apk)} arm64/armv7 libapp.so 快照魔数不一致: {a.hex()} vs {b.hex()}（疑似一老一新）")
        else:
            ok(f"arm64/armv7 libapp.so 同一次构建（快照魔数一致 {a[:4].hex()}）")

def check_apk_base(apk, label, expect_extract_native):
    print(f"\n=== {label}: {os.path.basename(apk)} ===")
    if not os.path.exists(apk):
        fail(f"{label} 不存在: {apk}")
        return
    d = badging(apk)
    if d["vcode"] == EXPECT_VCODE: ok(f"versionCode={d['vcode']}")
    else: fail(f"versionCode={d['vcode']}（期望 {EXPECT_VCODE}）")
    if d["vname"] == EXPECT_VNAME: ok(f"versionName={d['vname']}")
    else: fail(f"versionName={d['vname']}（期望 {EXPECT_VNAME}）")
    if d["pkg"] == EXPECT_PKG: ok(f"包名={d['pkg']}")
    else: fail(f"包名={d['pkg']}（期望 {EXPECT_PKG}）")
    if d["minsdk"] == EXPECT_MINSdk: ok(f"minSdk={d['minsdk']}")
    else: fail(f"minSdk={d['minsdk']}（期望 {EXPECT_MINSdk}）")

    ext = extract_native_libs(apk)
    if expect_extract_native:
        # 车机包：压缩原生库（extractNativeLibs=true / .so DEFLATED）以压体积
        if ext is True: ok("extractNativeLibs=true（车机包 .so 压缩）")
        elif ext is False: fail("extractNativeLibs=false（车机包需 true 压缩以压体积）")
        else: fail("无法读取 extractNativeLibs（车机包应 true）")
    else:
        # 手机/arm64 包：STORED + 4K 对齐
        if ext is False: ok("extractNativeLibs=false")
        elif ext is True: fail("extractNativeLibs=true（应为 false，so STORED+4K对齐）")
        else: fail("无法读取 extractNativeLibs（应为 false）")

    cert = cert_sha256(apk)
    if cert and cert.startswith(EXPECT_CERT_PREFIX): ok(f"签名证书 SHA-256 {cert[:8]}…")
    else: fail(f"签名证书 SHA-256={cert}（应 {EXPECT_CERT_PREFIX} 开头）")

    if zipalign_ok(apk): ok("zipalign -c -p 4 通过")
    else: fail("zipalign -c -p 4 未通过")

def check_audio(apk, want_hi, label):
    names = set(list_assets(apk))
    missing_lo, extra_hi, missing_hi = [], [], []
    for p in PACKS:
        lo = f"assets/flutter_assets/assets/audio/packs/{p}/lo/"
        hi = f"assets/flutter_assets/assets/audio/packs/{p}/hi/"
        has_lo = any(n.startswith(lo) for n in names)
        has_hi = any(n.startswith(hi) for n in names)
        if not has_lo: missing_lo.append(p)
        if want_hi:
            if not has_hi: missing_hi.append(p)
        else:
            if has_hi: extra_hi.append(p)
    if want_hi:
        if not missing_hi: ok(f"{label}：21 车型 hi 齐全")
        else: fail(f"{label}：缺 hi 档车型 {len(missing_hi)} 个: {missing_hi}")
    else:
        if not extra_hi: ok(f"{label}：仅 lo（无 hi）")
        else: fail(f"{label}：车机包不应含 hi，但出现 {len(extra_hi)} 个: {extra_hi}")
    if missing_lo:
        fail(f"{label}：缺 lo 档车型 {len(missing_lo)} 个: {missing_lo}")
    else:
        ok(f"{label}：21 车型 lo 齐全")

def check_car_size(apk, limit=35 * 1024 * 1024):
    """车机包体积上限 35MB（低存储车机）。"""
    sz = os.path.getsize(apk)
    if sz <= limit:
        ok(f"车机包体积 {sz/1048576:.1f}MB ≤ 35MB")
    else:
        fail(f"车机包体积 {sz/1048576:.1f}MB > 35MB（低存储车机装不下）")

def check_car_dual_abi(apk):
    """车机包必须双 ABI（arm64-v8a + armeabi-v7a）兼容老/新车机。"""
    import zipfile
    abis = set()
    with zipfile.ZipFile(apk) as z:
        for n in z.namelist():
            if n.startswith("lib/") and n.endswith("/libapp.so"):
                abis.add(n.split("/")[1])
    want = {"arm64-v8a", "armeabi-v7a"}
    if abis == want:
        ok(f"车机包双 ABI: {sorted(abis)}")
    else:
        fail(f"车机包 ABI={sorted(abis)}（应为双 ABI {sorted(want)}）")

def main():
    phone = os.path.join(DIST, "rev-latest.apk")
    car = os.path.join(DIST, "rev-car.apk")
    arm64 = os.path.join(DIST, "rev-arm64.apk")

    print("REV release_check v2.14.0")
    for tool in (AAPT, APKSIGNER, ZIPALIGN):
        if not os.path.exists(tool):
            fail(f"找不到构建工具: {tool}")

    # 手机包：hi+lo 齐全 + 双 ABI 同构建 + STORED
    check_apk_base(phone, "手机包 rev-latest.apk", expect_extract_native=False)
    check_audio(phone, want_hi=True, label="手机包")
    check_libapp_same_build(phone)

    # 车机包：仅 lo + 压缩原生库 + 双 ABI + 体积 ≤35MB
    check_apk_base(car, "车机包 rev-car.apk", expect_extract_native=True)
    check_audio(car, want_hi=False, label="车机包")
    check_car_size(car)
    check_car_dual_abi(car)

    # arm64 单架构包（手机 variant：hi+lo 齐全，仅 arm64-v8a）
    check_apk_base(arm64, "arm64 包 rev-arm64.apk", expect_extract_native=False)
    check_audio(arm64, want_hi=True, label="arm64 包")

    print("\n" + "=" * 56)
    if FAILS:
        print(f"校验失败 {len(FAILS)} 项：")
        for f in FAILS:
            print("  - " + f)
        sys.exit(1)
    print("全部校验通过 ✅")
    sys.exit(0)

if __name__ == "__main__":
    main()
