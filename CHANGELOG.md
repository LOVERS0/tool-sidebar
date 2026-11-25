# Changelog

## 1.11.0 — 2026-11-25
- Missing apps without an explicit source no longer guess a GitHub repository for installation.
- Remove the built-in online translator, offline substitution window, translation network code, and translator screenshot. Legacy translation CLI flags now return a removal message instead of opening the GUI.
- Remove install-all and automatic batch installation during configuration import. Restore missing repositories as uninstalled catalog entries while preserving existing local app metadata.
- Remove the auxiliary Accessibility settings shortcut, permission guesses on launch errors, clipboard-copy command support and four non-app defaults (Typst, doocs/md, avoid-ai-writing, MarkItDown).
- Keep search, favorites, categories, keyboard shortcuts, the floating ball, configuration backups and individual app installation/update/removal. Preserve old backup compatibility.
- Simplify the menu and refresh documentation and the native sidebar screenshot.

## 1.10.0 — 2026-11-24
- Reuse list rows while searching; add All / Installed / Favorites filters and favorite actions.
- Show explicit Open / Install / Update / Get / Visit / Copy actions and larger subtitles. Move launch-at-login and Quit into the menu.
- Resolve installed apps from both Applications folders and recorded Bundle IDs before applying custom display names.
- Select downloads for the host architecture, including Apple Silicon under Rosetta.
- Stage and validate updates before replacing the installed app; restore the previous app on commit failure.
- Keep macOS quarantine metadata and stop automatic installation when Gatekeeper assessment fails.
- Use Sparkle exclusively for application updates; the old direct-replacement CLI now directs users to Sparkle.
- Drain subprocess stdout/stderr concurrently, cancel timed-out network tasks, ignore callbacks from cancelled install sessions, and save settings/catalog files atomically.
- Build into `build/` by default without replacing the installed app. Add regression checks to CI.
- Translate full online input in UTF-8-sized segments; cancel superseded requests on editing, resubmission, direction changes and window close.
- Reject HTTP/service errors as translation results and label dictionary fallback. Bound the translation cache and synchronize the CLI result.
- Resize the translator with Auto Layout, add ⌘↩, input feedback and accessible labels.
- Refresh native screenshots and Chinese/English README with current behavior and installation requirements.

## 1.9.2
- Remove developer jargon from user-facing copy: “本地安装 agent” → “正在安装 / 安装助手”；“agent 没有返回结果” → “安装器没有返回结果”.
- English UI: “Local install agent” → “Built-in installer”; “agent harness” → “AI workspace”.

## 1.9.1
- Fix launch-at-login: LaunchAgent now launches via `/usr/bin/open -g -a` instead of pointing at the `.app` directory (which launchd couldn't execute).
- Single-instance lock (flock) for normal GUI launch.
- Update checks now compare versions numerically: never offer an older release as an "update" (e.g. 1.9.1 → 1.9.0).
- Shorter translator status text and English subtitle to avoid truncation.

## 1.9.0
- Bilingual UI: English automatically on non-Chinese systems; tool names, subtitles, groups, menus, batch and translator are localized.
- Localized bundle display name via `en.lproj` / `zh-Hans.lproj`.
- `scripts/release.sh`: build → sign → tag → wait for CI → upload → appcast → Homebrew in one command.
- `build.sh` accepts `SIGN_IDENTITY` / `NOTARY_PROFILE` for Developer ID signing and notarization.
- Added `NOTARIZATION.md` and `RELEASE.md`.

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
