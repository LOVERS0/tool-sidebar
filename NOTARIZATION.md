# Apple 公证（Notarization）怎么搞

> 结论先说：**没有 Apple Developer Program 账号（$99/年）就没法真正公证。**
> ad-hoc 签名 + 未公证时，用户首次打开要右键 →「打开」，这是目前最大的安装门槛。

## 1. 准备

1. 注册 **Apple Developer Program**（个人/公司均可，$99/年），等待审核通过。
2. 在 [Apple Developer Certificates](https://developer.apple.com/account/resources/certificates) 创建 **Developer ID Application** 证书，下载 `.cer` 并导入钥匙串。
3. 确认钥匙串里有：
   ```bash
   security find-identity -v -p codesigning
   # 应看到 "Developer ID Application: Your Name (TEAMID)"
   ```
4. 生成 App 专用密码（用于公证）：
   - Apple ID 账号 → 登录与安全 → App 专用密码 → 生成一个；
   - 记下 Apple ID、Team ID（开发者账号 10 位 ID）、专用密码。

## 2. 本机一次性配置

```bash
xcrun notarytool store-credentials "toolsidebar-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID1234" \
  --password "app-specific-password"
```

## 3. 用 Developer ID 构建 + 公证

```bash
# codesign 用 Developer ID + hardened runtime，然后 notarytool 提交并 staple
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID1234)" \
NOTARY_PROFILE="toolsidebar-notary" \
VERSION=1.9.0 ./build.sh
```

`build.sh` 会：
1. `codesign --options runtime --timestamp`；
2. 打包 zip 并 `xcrun notarytool submit --wait`；
3. `xcrun stapler staple`；
4. `spctl --assess` 验证。

手动验证：

```bash
spctl -a -vvv -t install "$HOME/Applications/小工具侧边栏.app"
xcrun stapler validate "$HOME/Applications/小工具侧边栏.app"
```

## 4. CI 公证（可选）

在 GitHub Actions 里需要：
- Secret：`DEVELOPER_ID_P12`（base64 的 .p12）、`DEVELOPER_ID_PASSWORD`、`NOTARY_APPLE_ID`、`NOTARY_TEAM_ID`、`NOTARY_PASSWORD`；
- 步骤：导入证书到临时 keychain → 用 Developer ID 签名 → `notarytool` 提交 → `stapler staple` → 上传 zip。

当前 `.github/workflows/build.yml` 只做 ad-hoc 构建；配好账号后我可以补 CI 公证。

## 5. 没有账号时的替代方案

- README / 官网写清 **右键 → 打开**，并提供：
  ```bash
  xattr -dr com.apple.quarantine /Applications/ToolSidebar.app
  ```
- Homebrew 用户可 `brew install --cask --no-quarantine tool-sidebar`；
- 这是临时缓解，不是真正解决。
