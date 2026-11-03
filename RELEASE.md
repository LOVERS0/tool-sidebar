# 发布流程（自动化）

前置：本机已 `gh auth login`，已安装 Xcode CLT，Sparkle `vendor/bin/sign_update` 可用，私钥在登录钥匙串；Homebrew tap 仓库在 `~/Documents/homebrew-tool-sidebar`。

## 一条命令

```bash
# 1) 先把 build.sh 的默认版本改好并推送到 main（CI 按 tag 构建）
# 2) 发布：
./scripts/release.sh 1.9.0
```

脚本会：

1. `./build.sh` 构建 universal app；
2. 打包 `ToolSidebar.zip` 并用 Sparkle `sign_update` 签名；
3. 在 main 当前 HEAD 创建 `vX.Y.Z` tag，等待 GitHub Actions 构建出 Release；
4. 用本地构建的 zip 覆盖 Release 资产（确保与本地一致）；
5. 生成新的 `appcast.xml`（保留旧版本条目），提交到 main 并上传为 Release 资产；
6. 更新 `~/Documents/homebrew-tool-sidebar` 的 cask 版本与 sha256。

## 手动兜底

如果脚本失败，按 `README`/`RELEASE.md` 里的步骤手动执行；关键是 **appcast 必须用 `sign_update` 对最终 zip 重新签名**。

## 公证

见 [NOTARIZATION.md](NOTARIZATION.md)。公证后的 zip 才能让普通用户双击打开。
