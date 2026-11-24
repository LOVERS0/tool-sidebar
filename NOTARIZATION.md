# Apple 公证（Notarization）怎么搞

公开分发时，可使用 Apple Developer Program 账号、Developer ID Application 证书和 `notarytool` 为应用签名、公证。

项目默认构建为 ad-hoc 签名，尚未经过 Apple 公证。Sparkle 的更新包签名用于验证更新来源，不能替代 Apple 公证。

## 1. 准备

1. 注册 **Apple Developer Program**（个人或组织，资格与费用以 Apple 官方说明为准），等待审核通过。
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
VERSION=1.10.0 ./build.sh
```

`build.sh` 会：
1. `codesign --options runtime --timestamp`；
2. 打包 zip 并 `xcrun notarytool submit --wait`；
3. `xcrun stapler staple`；
4. `spctl --assess` 验证。

手动验证：

```bash
spctl -a -vvv -t execute "build/小工具侧边栏.app"
xcrun stapler validate "build/小工具侧边栏.app"
```

## 4. CI 公证（可选）

在 GitHub Actions 里需要：
- Secret：`DEVELOPER_ID_P12`（base64 的 .p12）、`DEVELOPER_ID_PASSWORD`、`NOTARY_APPLE_ID`、`NOTARY_TEAM_ID`、`NOTARY_PASSWORD`；
- 步骤：导入证书到临时 keychain → 用 Developer ID 签名 → `notarytool` 提交 → `stapler staple` → 上传 zip。

当前 `.github/workflows/build.yml` 仅构建 ad-hoc 签名包，未配置自动公证。

## 5. 未配置公证时的分发

在 README、官网和 Release 中标明当前包未公证。用户首次打开若被系统拦截，应先核实下载来源，再按「系统设置 → 隐私与安全」中的提示处理。

发布时同时提供 SHA-256 校验和，并对最终更新 zip 使用既有 Sparkle 密钥签名。不要把这两项检查描述为已经完成 Apple 公证。
