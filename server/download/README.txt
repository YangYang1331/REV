把构建产物放到本目录，供看板“应用内更新 / 下载”使用：

  rev-latest.apk          手机包（hi+lo，双 ABI）
  rev-car.apk             车机包（lo，双 ABI）
  rev-arm64.apk           arm64 单架构包（hi+lo）
  rev-lite.apk            精简包（lo，arm64）
  rev-ios.ipa             未签名 iOS 包（用全能签/Sideloadly 重签）
  REV-Flutter-source.zip  源码包

文件不在时对应下载链接会返回 404，不影响看板与上报。
