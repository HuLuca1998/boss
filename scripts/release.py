#!/usr/bin/env python3
"""Local signed release: build -> verify -> ZIP+SHA256 -> tag -> draft -> publish."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "BossAssistant"
REPO = "HuLuca1998/boss"

def run(*args, capture=False, env=None):
    return subprocess.run(args, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None, env=env).stdout

def next_version(value):
    major, minor, patch = map(int, value.removeprefix("v").split("."))
    if patch < 9:
        return f"{major}.{minor}.{patch + 1}"
    if minor < 9:
        return f"{major}.{minor + 1}.0"
    return f"{major + 1}.0.0"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", nargs="?", help="x.y.z; defaults to the committed VERSION")
    parser.add_argument("notes", nargs="?", type=Path)
    parser.add_argument("--prepare-only", action="store_true", help="Build and verify artifacts without publishing")
    args = parser.parse_args()
    committed = (APP / "VERSION").read_text().strip()
    version = args.version or committed
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version):
        raise SystemExit("版本号必须为 x.y.z，不带 v")
    if version != committed:
        raise SystemExit("先修改并提交 BossAssistant/VERSION 和 BUILD_NUMBER，保证源码与安装包一致")
    if run("git", "status", "--porcelain", capture=True).strip():
        raise SystemExit("工作区有未提交改动，请先检查并提交")
    tag = "v" + version
    existing = run("git", "tag", "--list", tag, capture=True).strip()
    if existing:
        raise SystemExit(f"{tag} 已存在，拒绝重复发布；如上次发布中断，请按发布文档恢复")
    tags = run("git", "tag", "--list", "v*", "--sort=-version:refname", capture=True).splitlines()
    if tags and version != next_version(tags[0]):
        print(f"提示：参考项目默认下一版为 {next_version(tags[0])}，本次使用已明确指定并提交的 {version}")
    notes = args.notes or ROOT / "docs" / "releases" / f"{version}.md"
    notes = notes.resolve()
    if not notes.is_file():
        raise SystemExit(f"缺少版本说明：{notes}")
    output = APP / "build" / "release" / version
    if output.exists():
        raise SystemExit(f"构建目录已存在：{output}；检查旧产物后移走再试")
    for test in ["keyboard-runtime.cjs", "assistance-runtime.cjs", "location-runtime.cjs"]:
        run("node", str(APP / "Tests" / test))
    run("zsh", str(ROOT / "scripts/test-update.sh"))
    with tempfile.TemporaryDirectory(prefix="boss-cache-tests-") as folder:
        tests = str(Path(folder) / "game-cache-tests")
        run("swiftc", str(APP / "Sources/GameCachePolicy.swift"), str(APP / "Tests/GameCachePolicyTests.swift"), "-o", tests)
        run(tests, str(APP / "Resources"))
    env = dict(os.environ, APP_OUT=str(output), APP_VERSION=version)
    run("zsh", str(APP / "build.sh"), env=env)
    bundle = output / "首领助手.app"
    run(str(bundle / "Contents/Helpers/BossAssistantUpdater"), "verify", str(bundle), version)
    archive = output / f"BossAssistant-{version}-macos-arm64.zip"
    run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(bundle), str(archive))
    run(str(bundle / "Contents/Helpers/BossAssistantUpdater"), "verify-archive", str(archive))
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = archive.with_name(archive.name + ".sha256")
    checksum.write_text(f"{digest}  {archive.name}\n")
    print(f"已生成：{archive.name}\nSHA256：{digest}")
    if args.prepare_only:
        print("仅准备产物；未创建 tag、推送或发布")
        return
    run("gh", "auth", "status")
    actual = run("gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner", capture=True).strip()
    if actual != REPO:
        raise SystemExit(f"origin 指向 {actual}，预期 {REPO}；未推送或发布")
    run("git", "tag", "-a", tag, "-m", f"首领助手 {version}")
    run("git", "push", "origin", "HEAD:main", tag)
    run("gh", "release", "create", tag, str(archive), str(checksum), "--repo", REPO,
        "--draft", "--verify-tag", "--title", f"首领助手 {version}", "--notes-file", str(notes))
    run("gh", "release", "edit", tag, "--repo", REPO, "--draft=false", "--latest")
    print(f"发布完成：https://github.com/{REPO}/releases/tag/{tag}")

if __name__ == "__main__":
    main()
