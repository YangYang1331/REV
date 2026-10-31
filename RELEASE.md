# REV 发版一页纸（以后出新版本照这个来）

## 你只要做一件事
改完代码后，在本工程目录执行：

```bash
git add -A && git commit -m "说明改了什么" && git push
```

推上去后，GitHub Actions 会自动在 macOS 云跑器上编译，约 3–5 分钟。

## 怎么拿新 IPA
1. 打开仓库 https://github.com/YangYang1331/rev-cluster/actions
2. 点最新那条绿色勾的运行记录；
3. 页面下方 **Artifacts → REV-ios-ipa**，下载解压就是新的 `REV.ipa`；
4. 用全能签导入证书 → 签名 → 装到 iPhone。

## 关键信息
- 包名：`com.rev.cluster`　桌面名：REV
- 仓库：私有仓库 `YangYang1331/rev-cluster`
- 触发：push 到 main 自动构建；也可在 Actions 页手动 Run workflow
- 产物：未签名 IPA（签名在全能签里做）

## 常见问题
- 构建红叉：进运行记录看红色那一步的日志，把报错发我即可。
- 想让我代跑：直接说"帮我出新版本"，我来推送+下载+发你。
