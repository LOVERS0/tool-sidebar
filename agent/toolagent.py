#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
小工具侧边栏 · 本地安装 agent
================================
从 GitHub 搜索 / 下载 macOS 开源工具，做自检（SHA-256、签名、公证），
然后安装到 ~/Applications 并写入目录（收录），供侧边栏 App 读取。

用法：
  toolagent.py install <owner/repo | 完整 URL | 搜索词> [--check-only] [--group 组名]
  toolagent.py search <搜索词>
  toolagent.py list
  toolagent.py autostart status|on|off <App 路径>

输出：最后一行 stdout 为 JSON 结果；过程日志走 stderr。
"""

import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime

HOME = os.path.expanduser("~")
APPS_DIR = os.path.join(HOME, "Applications")
CACHE_DIR = os.path.join(HOME, "Library", "Caches", "ToolSidebar")
CATALOG_DIR = os.path.join(HOME, "Library", "Application Support", "小工具侧边栏")
CATALOG_PATH = os.path.join(CATALOG_DIR, "catalog.json")
LAUNCH_AGENT = os.path.join(HOME, "Library", "LaunchAgents", "com.a1.toolsidebar.plist")
MIRROR = "https://ghproxy.net/"
UA = {"User-Agent": "ToolSidebar-Agent/1.0 (macOS)"}


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def emit(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def http_get(url, dest=None):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=90) as resp:
        if dest:
            with open(dest, "wb") as f:
                shutil.copyfileobj(resp, f)
            return dest
        return resp.read()


def github_token():
    token_file = os.path.expanduser("~/.config/tool-sidebar/github_token")
    if os.path.exists(token_file):
        try:
            with open(token_file, "r", encoding="utf-8") as f:
                token = f.read().strip()
            if token:
                return token
        except Exception:  # noqa: BLE001
            pass
    return os.environ.get("GITHUB_TOKEN", "").strip()


def gh_api(path):
    headers = dict(UA)
    token = github_token()
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request("https://api.github.com" + path, headers=headers)
    with urllib.request.urlopen(req, timeout=90) as resp:
        return json.loads(resp.read())


def download(url, dest):
    try:
        http_get(url, dest)
        return "direct"
    except Exception as exc:  # noqa: BLE001
        log("直连下载失败：%s，尝试镜像" % exc)
        http_get(MIRROR + url, dest)
        return "mirror"


def parse_repo(arg):
    arg = arg.strip()
    m = re.match(r"https?://github\.com/([^/\s]+)/([^/\s#?]+)", arg)
    if m:
        return m.group(1), m.group(2)[:-4] if m.group(2).endswith(".git") else m.group(2)
    if re.match(r"^[\w.-]+/[\w.-]+$", arg):
        owner, repo = arg.split("/", 1)
        return owner, repo
    return None



DIRECT_MAP = {
    "窗口管理": "rxhanson/Rectangle",
    "窗口吸附": "rxhanson/Rectangle",
    "剪贴板": "p0deje/Maccy",
    "菜单栏": "jordanbaird/Ice",
    "菜单栏管理": "jordanbaird/Ice",
    "压缩": "aonez/Keka",
    "解压": "aonez/Keka",
    "查重": "qarmin/czkawka",
    "系统监控": "exelban/stats",
    "传输": "localsend/localsend",
    "跨设备传文件": "localsend/localsend",
    "日历": "sfsam/Itsycal",
    "窗口切换": "lwouis/alt-tab-macos",
}

CJK_MAP = {
    "窗口管理": "window manager",
    "窗口": "window",
    "剪贴板": "clipboard",
    "菜单栏": "menu bar",
    "压缩": "archiver",
    "解压": "archiver",
    "查重": "duplicate finder",
    "系统监控": "system monitor",
    "传输": "file transfer",
    "笔记": "notes",
    "写作": "writing",
    "排版": "typesetting",
    "日历": "calendar",
    "下载": "downloader",
    "截图": "screenshot",
}


def normalize_query(query):
    text = query
    for cn, en in CJK_MAP.items():
        text = text.replace(cn, " " + en + " ")
    return " ".join(text.split())

def search_repos(query, limit=10):
    normalized = normalize_query(query)
    q = urllib.parse.quote(normalized + " macos")
    data = gh_api("/search/repositories?q=%s&sort=stars&order=desc&per_page=20" % q)
    items = [item for item in (data.get("items") or []) if not item.get("archived")]
    if not items:
        q2 = urllib.parse.quote(normalized)
        data = gh_api("/search/repositories?q=%s&sort=stars&order=desc&per_page=20" % q2)
        items = [item for item in (data.get("items") or []) if not item.get("archived")]
    if not items:
        return None
    ql = query.strip().lower()

    def score(item):
        name = (item.get("name") or "").lower()
        desc = (item.get("description") or "").lower()
        text = name + " " + desc
        value = 0.0
        if name == ql:
            value += 100
        elif ql in name:
            value += 50
        if "macos" in text or "mac os" in text or "os x" in text:
            value += 30
        if "mac" in text and "macos" not in text:
            value += 8
        if "linux" in text and "macos" not in text:
            value -= 10
        value += min(item.get("stargazers_count", 0) / 10000.0, 10)
        return value

    items.sort(key=score, reverse=True)
    return items[:limit]


def search_repo(query):
    items = search_repos(query)
    return items[0] if items else None


def is_mac_asset(name):
    if not re.search(r"\.(dmg|zip)$", name, re.I):
        return False
    if re.search(r"\.(sig|sha256|sha512|asc|md5|txt|json|yml|yaml)$", name, re.I):
        return False
    if re.search(r"(windows|win64|win32|linux|\.deb|\.rpm|appimage)", name, re.I):
        return False
    if name.lower().endswith(".dmg"):
        return True
    return bool(re.search(r"(mac|macos|darwin|osx|apple|universal)", name, re.I))


def pick_asset(assets):
    scored = []
    for asset in assets:
        if not is_mac_asset(asset["name"]):
            continue
        name = asset["name"]
        score = 0
        if name.lower().endswith(".dmg"):
            score += 8
        elif name.lower().endswith(".zip"):
            score += 4
        if re.search(r"(arm64|aarch64|universal|silicon)", name, re.I):
            score += 3
        if re.search(r"(mac|macos|darwin|osx)", name, re.I):
            score += 2
        if re.search(r"(x86_64|intel|amd64)", name, re.I):
            score -= 1
        scored.append((score, asset))
    if not scored:
        # 兜底：没有平台标识的 zip 也接受（很多 Mac App 这样命名）
        for asset in assets:
            name = asset["name"]
            if not re.search(r"\.(zip|dmg)$", name, re.I):
                continue
            if re.search(r"(windows|win64|win32|linux|\.deb|\.rpm|appimage)", name, re.I):
                continue
            scored.append((0, asset))
    if not scored:
        return None
    scored.sort(key=lambda x: -x[0])
    return scored[0][1]


def find_checksum(assets, filename):
    for asset in assets:
        name = asset["name"].lower()
        if not re.search(r"(sha256|checksum|checksums|sha256sums)", name):
            continue
        if not name.endswith((".txt", ".sha256", ".sha256sum", ".sums")):
            continue
        try:
            text = http_get(asset["browser_download_url"]).decode("utf-8", "ignore")
        except Exception:  # noqa: BLE001
            continue
        for line in text.splitlines():
            if filename in line:
                m = re.search(r"\b([a-fA-F0-9]{64})\b", line)
                if m:
                    return m.group(1).lower()
    return None


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def find_app(root):
    direct = [d for d in os.listdir(root) if d.endswith(".app")]
    if direct:
        return os.path.join(root, direct[0])
    for dirpath, dirnames, _ in os.walk(root):
        for d in dirnames:
            if d.endswith(".app"):
                return os.path.join(dirpath, d)
        if dirpath.count(os.sep) - root.count(os.sep) > 2:
            dirnames[:] = []
    return None


def read_bundle_info(app_path):
    plist = os.path.join(app_path, "Contents", "Info.plist")
    info = {}
    if os.path.exists(plist):
        try:
            with open(plist, "rb") as f:
                info = plistlib.load(f)
        except Exception:  # noqa: BLE001
            pass
    return {
        "bundle_id": info.get("CFBundleIdentifier"),
        "name": info.get("CFBundleDisplayName") or info.get("CFBundleName"),
        "version": info.get("CFBundleShortVersionString") or info.get("CFBundleVersion"),
    }


def verify_app(app_path):
    result = {}
    r = subprocess.run(["codesign", "--verify", "--deep", "--strict", app_path],
                       capture_output=True, text=True)
    result["codesign_ok"] = r.returncode == 0
    r2 = subprocess.run(["spctl", "--assess", "--type", "execute", "-vv", app_path],
                        capture_output=True, text=True)
    result["notarized"] = r2.returncode == 0
    r3 = subprocess.run(["codesign", "-dv", "--verbose=4", app_path],
                        capture_output=True, text=True)
    team = re.search(r"TeamIdentifier=(\S+)", r3.stderr)
    result["team_id"] = team.group(1) if team else None
    return result


def extract_app(asset_path, workdir):
    name = asset_path.lower()
    if name.endswith(".dmg"):
        mp = subprocess.run(["hdiutil", "attach", "-nobrowse", "-readonly", asset_path],
                            capture_output=True, text=True)
        if mp.returncode != 0:
            raise RuntimeError("挂载 DMG 失败")
        mount = None
        for line in mp.stdout.splitlines():
            if "/Volumes/" in line:
                mount = line.split("\t")[-1].strip()
        if not mount:
            raise RuntimeError("找不到 DMG 挂载点")
        try:
            return find_app(mount), mount
        except Exception:
            subprocess.run(["hdiutil", "detach", mount, "-quiet"], capture_output=True)
            raise
    if name.endswith(".zip"):
        r = subprocess.run(["ditto", "-x", "-k", asset_path, workdir], capture_output=True)
        if r.returncode != 0:
            raise RuntimeError("解压 zip 失败")
        app = find_app(workdir)
        if not app:
            raise RuntimeError("压缩包里没有 .app")
        return app, None
    if name.endswith((".tar.gz", ".tgz")):
        r = subprocess.run(["ditto", "-x", "-k", asset_path, workdir], capture_output=True)
        if r.returncode != 0:
            raise RuntimeError("解压 tar.gz 失败")
        app = find_app(workdir)
        if not app:
            raise RuntimeError("压缩包里没有 .app")
        return app, None
    raise RuntimeError("不支持的包格式")


def load_catalog():
    if os.path.exists(CATALOG_PATH):
        try:
            with open(CATALOG_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:  # noqa: BLE001
            pass
    return {"tools": []}


def save_catalog(data):
    os.makedirs(CATALOG_DIR, exist_ok=True)
    with open(CATALOG_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def cmd_search(query):
    item = search_repo(query)
    if not item:
        emit({"ok": False, "error": "没有搜到合适的仓库"})
        return
    emit({
        "ok": True,
        "repo": item["full_name"],
        "stars": item["stargazers_count"],
        "description": item.get("description") or "",
        "url": item["html_url"],
    })


def cmd_install(target, check_only=False, group="已收录"):
    try:
        _cmd_install(target, check_only, group)
    except Exception as exc:  # noqa: BLE001
        emit({"ok": False, "target": target, "error": "安装失败：%s" % exc})


def _cmd_install(target, check_only=False, group="已收录"):
    direct = DIRECT_MAP.get(target.strip())
    parsed = parse_repo(direct if direct else target)
    release = None
    if parsed:
        owner, repo = parsed
        full = "%s/%s" % (owner, repo)
    else:
        candidates = search_repos(target)
        if not candidates:
            emit({"ok": False, "error": "没有搜到「%s」对应的 GitHub 仓库" % target})
            return
        full = None
        for item in candidates[:6]:
            name = item["full_name"]
            try:
                candidate_release = gh_api("/repos/%s/releases/latest" % name)
            except Exception:  # noqa: BLE001
                continue
            if pick_asset(candidate_release.get("assets") or []):
                full = name
                release = candidate_release
                break
        if not full:
            emit({
                "ok": False,
                "error": "搜到了仓库，但没有可自动安装的 macOS 包（只支持 dmg / zip）",
                "candidates": [c["full_name"] for c in candidates[:6]],
            })
            return

    log("仓库：%s" % full)
    if release is None:
        try:
            release = gh_api("/repos/%s/releases/latest" % full)
        except Exception:  # noqa: BLE001
            release = None

    assets = (release or {}).get("assets") or []
    asset = pick_asset(assets)
    release_url = (release or {}).get("html_url") or "https://github.com/%s/releases" % full
    if not asset:
        emit({
            "ok": False,
            "repo": full,
            "error": "这个仓库没有可直接安装的 macOS 包",
            "release_url": release_url,
        })
        return

    os.makedirs(CACHE_DIR, exist_ok=True)
    dest = os.path.join(CACHE_DIR, asset["name"])
    log("下载：%s（%.1f MB）" % (asset["name"], asset["size"] / 1048576.0))
    via = download(asset["browser_download_url"], dest)
    digest = sha256_file(dest)
    expected = find_checksum(assets, asset["name"])
    checksum_ok = None
    if expected:
        checksum_ok = (expected == digest)

    workdir = tempfile.mkdtemp(prefix="toolsidebar-")
    mount = None
    try:
        app_path, mount = extract_app(dest, workdir)
        if not app_path:
            raise RuntimeError("没有找到 .app")
        info = read_bundle_info(app_path)
        verify = verify_app(app_path)
        app_name = info.get("name") or full.split("/")[1]
        version = info.get("version") or (release or {}).get("tag_name", "")

        result = {
            "ok": True,
            "repo": full,
            "name": app_name,
            "version": version,
            "release_url": release_url,
            "asset": asset["name"],
            "sha256": digest,
            "checksum_verified": checksum_ok,
            "codesign_ok": verify["codesign_ok"],
            "notarized": verify["notarized"],
            "team_id": verify["team_id"],
            "download_via": via,
            "group": group,
        }

        if check_only:
            result["message"] = "自检完成（未安装）"
            if checksum_ok is False:
                result["ok"] = False
                result["message"] = "SHA-256 校验失败"
            emit(result)
            return

        if not verify["codesign_ok"]:
            result["ok"] = False
            result["message"] = "代码签名校验失败，已停止安装"
            emit(result)
            return

        os.makedirs(APPS_DIR, exist_ok=True)
        final_path = os.path.join(APPS_DIR, os.path.basename(app_path))
        if os.path.exists(final_path):
            result["path"] = final_path
            result["already_installed"] = True
            result["message"] = "已经安装过"
            emit(result)
            return

        subprocess.run(["ditto", app_path, final_path], check=True)
        subprocess.run(["xattr", "-dr", "com.apple.quarantine", final_path], capture_output=True)
        result["path"] = final_path
        result["already_installed"] = False
        result["message"] = "安装完成，已通过自检并收录"

        catalog = load_catalog()
        entry = {
            "id": "repo:" + full,
            "name": app_name,
            "subtitle": "%s · %s" % (full, version),
            "icon": "shippingbox",
            "group": group,
            "path": final_path,
            "repo": full,
            "version": version,
            "sha256": digest,
            "installedAt": datetime.now().isoformat(timespec="seconds"),
        }
        catalog["tools"] = [t for t in catalog.get("tools", []) if t.get("repo") != full]
        catalog["tools"].append(entry)
        save_catalog(catalog)
        emit(result)
    finally:
        if mount:
            subprocess.run(["hdiutil", "detach", mount, "-quiet"], capture_output=True)
        shutil.rmtree(workdir, ignore_errors=True)


def cmd_autostart(action, app_path):
    if action == "status":
        emit({"ok": True, "enabled": os.path.exists(LAUNCH_AGENT)})
        return
    uid = os.getuid()
    if action == "on":
        if not app_path:
            emit({"ok": False, "error": "缺少 App 路径"})
            return
        os.makedirs(os.path.dirname(LAUNCH_AGENT), exist_ok=True)
        plist = {
            "Label": "com.a1.toolsidebar",
            "ProgramArguments": [app_path],
            "RunAtLoad": True,
            "ProcessType": "Interactive",
        }
        with open(LAUNCH_AGENT, "wb") as f:
            plistlib.dump(plist, f)
        subprocess.run(["launchctl", "bootstrap", "gui/%d" % uid, LAUNCH_AGENT],
                       capture_output=True, text=True)
        emit({"ok": True, "enabled": True})
        return
    if action == "off":
        subprocess.run(["launchctl", "bootout", "gui/%d" % uid, LAUNCH_AGENT],
                       capture_output=True, text=True)
        if os.path.exists(LAUNCH_AGENT):
            os.remove(LAUNCH_AGENT)
        emit({"ok": True, "enabled": False})
        return
    emit({"ok": False, "error": "未知操作：%s" % action})


def main(argv):
    if not argv:
        emit({"ok": False, "error": "缺少命令"})
        return 2
    cmd = argv[0]
    if cmd == "search" and len(argv) >= 2:
        cmd_search(argv[1])
        return 0
    if cmd == "list":
        emit(load_catalog())
        return 0
    if cmd == "autostart" and len(argv) >= 2:
        app_path = argv[2] if len(argv) >= 3 else ""
        cmd_autostart(argv[1], app_path)
        return 0
    if cmd == "install" and len(argv) >= 2:
        check_only = "--check-only" in argv
        group = "已收录"
        if "--group" in argv:
            idx = argv.index("--group")
            if len(argv) > idx + 1:
                group = argv[idx + 1]
        cmd_install(argv[1], check_only=check_only, group=group)
        return 0
    emit({"ok": False, "error": "未知命令"})
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
