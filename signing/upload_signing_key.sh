#!/usr/bin/env bash
# 在"构建过历史包的云电脑"上运行：定位正式签名密钥(3f16feb)并提交到私有仓库。
set -euo pipefail

WANT_PREFIX="3f16feb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ">> 在常见路径中查找 SHA-256 前缀为 ${WANT_PREFIX} 的密钥..."

CANDIDATES=(
  "$HOME/.config/.android/debug.keystore"
  "$HOME/.android/debug.keystore"
)
# 额外：把 home 下能找到的 debug.keystore 也纳入
while IFS= read -r f; do
  CANDIDATES+=("$f")
done < <(find "$HOME" -maxdepth 4 -type f -name "*.keystore" 2>/dev/null)

FOUND=""
for ks in "${CANDIDATES[@]}"; do
  [ -f "$ks" ] || continue
  fp="$(keytool -list -v -keystore "$ks" -storepass android 2>/dev/null \
        | grep -iE "SHA256:" | head -1 | tr -d ' ' | sed 's/^SHA256://')"
  echo "   - $ks  -> ${fp:0:12}..."
  if [[ "$fp" == ${WANT_PREFIX}* ]]; then
    FOUND="$ks"
    break
  fi
done

if [ -z "$FOUND" ]; then
  echo "!! 未找到指纹前缀 ${WANT_PREFIX} 的密钥。"
  echo "   请确认这台机器确实构建过历史包，或手动把 keystore 放到 signing/rev-debug.keystore。"
  exit 1
fi

echo ">> 命中正式密钥: $FOUND"
cp "$FOUND" "$REPO_DIR/signing/rev-debug.keystore"

cat > "$REPO_DIR/signing/key.properties" <<'PROPS'
storePassword=android
keyPassword=android
keyAlias=androiddebugkey
storeFile=signing/rev-debug.keystore
PROPS

# 同步一份到 android/ 供本地直接构建
cp "$REPO_DIR/signing/key.properties" "$REPO_DIR/android/key.properties"

# 校验签名确实是目标指纹
FINAL_FP="$(keytool -list -v -keystore "$REPO_DIR/signing/rev-debug.keystore" \
            -storepass android 2>/dev/null | grep -iE "SHA256:" | head -1)"
echo ">> 已保存 signing/rev-debug.keystore，$FINAL_FP"

cd "$REPO_DIR"
git add -f signing/rev-debug.keystore signing/key.properties
git add signing/README.md signing/upload_signing_key.sh 2>/dev/null || true
git commit -m "signing: 取回正式发布签名密钥(3f16feb)并加入私有仓库" || echo "（无新改动可提交）"
echo ">> 推送到 GitHub 私有仓库..."
git push origin main
echo ">> 完成。以后任何机器克隆本仓库即可调取签名。"
