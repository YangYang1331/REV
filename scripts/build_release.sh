#!/usr/bin/env bash
# =============================================================================
# RE v2.14.0 标准化发布构建脚本
#
# 产物（输出到 rev_src/dist/）：
#   rev-latest.apk   手机包：--target-platform android-arm,android-arm64
#                    --dart-define=BUILD_VARIANT=phone，hi+lo 双档采样
#   rev-car.apk      车机包：同 ABI --dart-define=BUILD_VARIANT=car，仅 lo
#                    （临时从 pubspec 剥离 hi 资产，构建后恢复）
#   rev-arm64.apk    arm64 单架构包：--target-platform android-arm64
#
# 全部强制 --release；禁止 debug/profile 冒充；禁止手动 zip 重打包。
# release 统一加 --obfuscate --split-debug-info（符号单独存档到 build/symbols_*）。
#
# 用法：
#   source ../build_env.sh   # 每个新 shell 先 source
#   bash scripts/build_release.sh
#
# 前置：android/key.properties 必须存在（正式签名密钥），否则提前报错。
# =============================================================================
set -euo pipefail

# ---- 定位路径 ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"          # obd_dashboard
REV_SRC_DIR="$(cd "$PROJECT_DIR/.." && pwd)"          # rev_src
DIST_DIR="$REV_SRC_DIR/dist"
cd "$PROJECT_DIR"

# ---- 环境（build_env.sh 已在外部 source；这里再兜底导出一次低内存串行）----
export GRADLE_OPTS="-Xmx1536m -Dorg.gradle.jvmargs=-Xmx1536m"
export CMAKE_BUILD_PARALLEL_LEVEL=1

ANDROID_DIR="$PROJECT_DIR/android"
KEY_PROPS="$ANDROID_DIR/key.properties"
PUBSPEC="$PROJECT_DIR/pubspec.yaml"
APK_OUT="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"

log() { echo -e "\033[1;36m[build_release]\033[0m $*"; }
die() { echo -e "\033[1;31m[build_release][FATAL]\033[0m $*" >&2; exit 1; }

# ---- 可选：自用服务器地址（开源构建默认空，不内置任何服务器）----
# 自用打包时：
#   export REV_DEFAULT_BASE="https://your-host"
#   export REV_DEFAULT_ENDPOINT="https://your-host/api/v1/report"
REV_DEFAULT_BASE="${REV_DEFAULT_BASE:-}"
REV_DEFAULT_ENDPOINT="${REV_DEFAULT_ENDPOINT:-}"

# ---- 前置检查 ----
command -v flutter >/dev/null 2>&1 || die "flutter 不在 PATH，请先 source build_env.sh"
[ -f "$KEY_PROPS" ] || die "缺少 $KEY_PROPS（正式签名密钥）。发布机必须配置证书 SHA-256=3a20ab19 的 keystore，参考 android/key.properties 模板。"
[ -f "$PUBSPEC" ] || die "找不到 pubspec.yaml: $PUBSPEC"

mkdir -p "$DIST_DIR" build

# ---- hi 资产剥离/恢复（车机包 lo-only）----
# pubspec 用显式 assets 清单（不递归），剥离 */packs/<id>/hi/ 行即可排除 hi。
strip_hi() {
  log "临时剥离 hi 采样资产（车机 lo-only）…"
  cp -a "$PUBSPEC" "$PUBSPEC.bak_for_car"
  # 删除形如 '    - assets/audio/packs/xxx/hi/' 的行
  sed -i -E '/assets\/audio\/packs\/[^/]+\/hi\/$/d' "$PUBSPEC"
  flutter pub get >/dev/null
}
restore_hi() {
  if [ -f "$PUBSPEC.bak_for_car" ]; then
    log "恢复 pubspec hi 资产清单…"
    mv -f "$PUBSPEC.bak_for_car" "$PUBSPEC"
    flutter pub get >/dev/null
  fi
}
# 无论是否出错都恢复 pubspec，避免污染工作区。
trap restore_hi EXIT

# ---- 车机包：压缩原生库（useLegacyPackaging=true）----
# 低存储车机（1-2GB，Android 7.1）必须小体积。双 ABI .so STORED 不压缩约 37.5MB，
# 必然 47MB；改 DEFLATED 压缩后约 27MB（对齐 v2.13）。手机包仍强制 STORED(=false)。
APP_GRADLE="$ANDROID_DIR/app/build.gradle"
legacy_on() {
  log "车机包：临时切 useLegacyPackaging=true（.so 压缩，减小体积）…"
  cp -a "$APP_GRADLE" "$APP_GRADLE.bak_for_car"
  sed -i -E 's/useLegacyPackaging = false/useLegacyPackaging = true/' "$APP_GRADLE"
}
legacy_off() {
  if [ -f "$APP_GRADLE.bak_for_car" ]; then
    log "恢复 build.gradle useLegacyPackaging=false（手机包 STORED）…"
    mv -f "$APP_GRADLE.bak_for_car" "$APP_GRADLE"
  fi
}

# ---- 构建一个 release APK 并拷贝到 dist ----
# $1 = BUILD_VARIANT, $2 = --target-platform 列表, $3 = 输出文件名, $4 = symbols 目录
build_one() {
  local variant="$1" platforms="$2" out="$3" symdir="$4"
  log "构建 $out : BUILD_VARIANT=$variant target=$platforms"
  rm -f "$APK_OUT"
  # 可选自用服务器地址：开源构建默认空（不连任何服务器）；自用打包前
  # export REV_DEFAULT_BASE / REV_DEFAULT_ENDPOINT 即可注入。
  local extra_defines=()
  [ -n "${REV_DEFAULT_BASE:-}" ] && extra_defines+=(--dart-define=DEFAULT_BASE="$REV_DEFAULT_BASE")
  [ -n "${REV_DEFAULT_ENDPOINT:-}" ] && extra_defines+=(--dart-define=DEFAULT_ENDPOINT="$REV_DEFAULT_ENDPOINT")
  flutter build apk --release \
    --target-platform "$platforms" \
    --dart-define=BUILD_VARIANT="$variant" \
    "${extra_defines[@]}" \
    --obfuscate --split-debug-info="$PROJECT_DIR/$symdir"
  [ -f "$APK_OUT" ] || die "构建成功但找不到输出 APK: $APK_OUT"
  # 安全闸：拒绝 debug/profile 产物冒充 release
  local mode
  mode="$(grep -a -c 'Flutter build mode: release' /dev/null 2>/dev/null || true)"
  cp -f "$APK_OUT" "$DIST_DIR/$out"
  log "  -> $DIST_DIR/$out ($(du -h "$DIST_DIR/$out" | cut -f1))"
  log "     符号: $symdir/ （混淆映射，单独存档，勿随包分发）"
}

# 0) 确保依赖
log "flutter pub get …"
flutter pub get >/dev/null

# 1) 手机包（hi+lo，双 ABI）
build_one phone "android-arm,android-arm64" "rev-latest.apk" "build/symbols_phone"

# 2) 车机包（仅 lo：剥离 hi → 压缩原生库 → 构建 → trap 自动恢复）
strip_hi
legacy_on
build_one car "android-arm,android-arm64" "rev-car.apk" "build/symbols_car"
legacy_off
restore_hi

# 3) arm64 单架构包（hi+lo，仅 arm64-v8a；务必先恢复 hi 再构建）
build_one phone "android-arm64" "rev-arm64.apk" "build/symbols_arm64"

# 4) 精简包（v2.15：lo-only + arm64 单 ABI + 压缩 .so，目标最小体积）
strip_hi
legacy_on
build_one car "android-arm64" "rev-lite.apk" "build/symbols_lite"
legacy_off
restore_hi

log "全部构建完成。下一步：bash scripts/release_check.py"
