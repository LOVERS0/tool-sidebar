# Changelog

## 1.8.5
- Batch install now skips tools that only have manual downloads, and reports them as skipped instead of failed.
- Added `⋯ → GitHub 仓库 / 反馈…`.
- Cleaner file dialogs (`allowedContentTypes`).
- Sparkle appcast moved back to GitHub Pages (reliable again after `.nojekyll`).
- Repo: English README, landing page, issue templates, changelog.

## 1.8.4
- Installed curated tools no longer appear twice under “已收录”.
- Version normalization handles `release_3.3.0` / `v3.3.0`.
- Appcast served from the latest GitHub Release asset.

## 1.8.3
- Chinese names/descriptions survive installation (no more `owner/repo` subtitles).
- Appcast moved off the unstable jsDelivr path.

## 1.8.2
- Preserve Chinese subtitles and avoid duplicates.

## 1.8.1
- Auto-use `gh auth token` to avoid GitHub API rate limits; batch failures show reasons.

## 1.8.0
- Removed screen OCR translation; online translation is opt-in; default offline dictionary.
- Smaller binary, fewer permissions.

## 1.7.0
- MyMemory online translation, screen translation result panel, curated Easydict/Pot.

## 1.6.0
- Screen translation (OCR), translator window layout fixes.

## 1.5.1
- Sparkle appcast on GitHub Pages; native update fallback.

## 1.5.0
- Built-in CN↔EN translator, launch error alerts, accessibility hints.

## 1.4.1
- Floating ball, batch install, migration, custom categories, Sparkle.

## 1.0.0
- First release.
