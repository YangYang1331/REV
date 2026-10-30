#!/usr/bin/env bash
# 清掉本地产物，把工作区恢复到"只有源码 + 素材"的状态。
# 不会动 assets/、android/key.properties、签名文件。
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf build .dart_tool test/failures
rm -f pubspec.yaml.bak_for_car android/app/build.gradle.bak_for_car
flutter pub get >/dev/null

echo "已清理：build/ .dart_tool/ test/failures/ 临时备份文件"
du -sh . 2>/dev/null | awk '{print "当前目录：" $1}'
