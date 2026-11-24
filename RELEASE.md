# 发布流程

前置：已登录有仓库写权限的 `gh`、Xcode Command Line Tools、Sparkle 签名工具，以及登录钥匙串中的既有发布私钥。不要导出或提交私钥。

1. 更新 `build.sh` 的默认版本、`CHANGELOG.md` 和 `release-notes/X.Y.Z.md`，完成测试后合并到 main。
2. 检出与远程 main 一致的提交，保持工作区干净，运行：

```bash
./scripts/release.sh 1.10.0
```

脚本构建到 `build/`，运行回归检查，打包并验证 Sparkle 签名和内嵌公钥，然后创建版本标签。标签 CI 先运行构建和测试，再生成**草稿 Release**。

脚本用最终签名包替换草稿附件，上传 `SHA256SUMS`，使用对应版本的发布说明公开 Release。下载地址公开后，才更新仓库的 `appcast.xml` 和 Release 附件，避免更新源指向未公开的包。

已存在的标签会停止自动发布，避免覆盖已发布附件。手工恢复时，先检查现有 Release、附件 SHA-256 和 CI 状态；对最终 zip 重新签名并核对内嵌公钥。appcast 的签名和长度必须对应最终附件。

Homebrew tap 为可选步骤：默认不修改其他本地仓库。需要时设置 `UPDATE_TAP=1`，并确保 `~/Documents/homebrew-tool-sidebar` 是正确的 tap 检出目录。

Apple Developer ID 签名与公证可通过 `SIGN_IDENTITY` / `NOTARY_PROFILE` 配置，见 [NOTARIZATION.md](NOTARIZATION.md)。未配置时产物为 ad-hoc 签名，发布说明必须如实标明未公证。
