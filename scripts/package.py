#!/usr/bin/env python3
"""Build a self-contained Apple Silicon release from pinned yt-dlp + local Homebrew tools."""
import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.0.0"
YTDLP_VERSION = "2026.08.19"
YTDLP_SHA256 = "0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202"

def run(*args, **kwargs):
    return subprocess.check_output([str(a) for a in args], text=True, **kwargs).strip()

def dependencies(path):
    lines = run("otool", "-L", path).splitlines()[1:]
    return [line.strip().split(" (", 1)[0] for line in lines]

def package(args):
    if run("uname", "-m") != "arm64":
        raise SystemExit("This release script targets Apple Silicon.")
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    # Stage outside iCloud-synced Documents; Finder can reattach bundle metadata there.
    dist = Path(tempfile.mkdtemp(prefix="peak-package-"))
    print("Staging:", dist, flush=True)
    app = dist / "Peak.app"
    if app.exists():
        shutil.rmtree(app)
    contents = app / "Contents"
    resources = contents / "Resources"
    tools = resources / "Tools"
    macos = contents / "MacOS"
    licenses = resources / "Licenses"
    for folder in [tools, macos, licenses]:
        folder.mkdir(parents=True, exist_ok=True)

    build = Path(args.build_dir).resolve() if args.build_dir else ROOT / ".build"
    run("swift", "build", "--product", "Peak", "-c", "release", "--scratch-path", build, cwd=ROOT)
    shutil.copy2(build / "release" / "Peak", macos / "Peak")
    source = Path(args.ytdlp).resolve() if args.ytdlp else ROOT / "vendor" / "yt-dlp"
    if not source.exists():
        source.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(f"https://github.com/yt-dlp/yt-dlp/releases/download/{YTDLP_VERSION}/yt-dlp_macos", source)
    if hashlib.sha256(source.read_bytes()).hexdigest() != YTDLP_SHA256:
        raise SystemExit("yt-dlp checksum mismatch. Refusing to package.")
    shutil.copy2(source, tools / "yt-dlp")
    (tools / "yt-dlp").chmod(0o755)

    manifest = {"yt-dlp": {"version": YTDLP_VERSION, "sha256": YTDLP_SHA256}}
    copied = {}
    brew_packages = set()
    minimum_os = (14, 0)

    def bundle(source_path):
        nonlocal minimum_os
        original = Path(source_path).resolve()
        name = original.name
        if name in copied:
            if copied[name] != original:
                raise RuntimeError(f"Library name collision: {name}")
            return
        copied[name] = original
        target = tools / name
        shutil.copy2(original, target)
        target.chmod(0o755)
        manifest[name] = {"source": str(original), "sha256": hashlib.sha256(original.read_bytes()).hexdigest()}
        match = re.search(r"/Cellar/([^/]+/[^/]+)/", str(original))
        if match:
            brew_packages.add(Path("/opt/homebrew/Cellar") / match.group(1))
        load_commands = run("otool", "-l", original)
        for found in re.findall(r"\bminos (\d+(?:\.\d+)*)", load_commands):
            minimum_os = max(minimum_os, tuple(int(x) for x in found.split(".")[:2]))
        for dep in dependencies(original):
            if dep.startswith("/opt/homebrew/"):
                bundle(dep)
                replacement = "@loader_path/" + Path(dep).resolve().name
                run("install_name_tool", "-change", dep, replacement, target, stderr=subprocess.DEVNULL)
            elif not dep.startswith(("/usr/lib/", "/System/Library/")):
                raise RuntimeError(f"Unresolved dependency: {original}: {dep}")
        if name.endswith(".dylib"):
            run("install_name_tool", "-id", "@loader_path/" + name, target, stderr=subprocess.DEVNULL)
        run("codesign", "--force", "--sign", "-", target, stderr=subprocess.DEVNULL)

    for name in ["ffmpeg", "ffprobe", "deno"]:
        tool = shutil.which(name)
        if not tool:
            raise SystemExit(f"Install build dependency first: brew install {name}")
        bundle(tool)
    for package_root in sorted(brew_packages):
        destination = licenses / package_root.parent.name
        destination.mkdir(exist_ok=True)
        for item in package_root.iterdir():
            if item.is_file() and (item.name.lower().startswith(("license", "copying", "copyright", "authors")) or item.name in ["INSTALL_RECEIPT.json", "sbom.spdx.json"]):
                shutil.copy2(item, destination / item.name)
    for name, url in {
        "yt-dlp-LICENSE.txt": f"https://raw.githubusercontent.com/yt-dlp/yt-dlp/{YTDLP_VERSION}/LICENSE",
        "yt-dlp-THIRD_PARTY_LICENSES.txt": f"https://raw.githubusercontent.com/yt-dlp/yt-dlp/{YTDLP_VERSION}/THIRD_PARTY_LICENSES.txt",
    }.items():
        urllib.request.urlretrieve(url, licenses / name)
    shutil.copy2(ROOT / "THIRD_PARTY.md", resources / "THIRD_PARTY.md")
    (resources / "dependency-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    min_os = ".".join(map(str, minimum_os))
    with (contents / "Info.plist").open("wb") as stream:
        plistlib.dump({
            "CFBundleName": "Peak", "CFBundleDisplayName": "Peak", "CFBundleExecutable": "Peak",
            "CFBundleIdentifier": "io.github.seth-person.peak", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": VERSION, "CFBundleVersion": "1",
            "CFBundleIconFile": "Peak", "LSMinimumSystemVersion": min_os,
            "NSHighResolutionCapable": True, "NSHumanReadableCopyright": "Copyright © 2026 Seth Person",
        }, stream)
    iconset = dist / "Peak.iconset"
    iconset.mkdir(exist_ok=True)
    run("swift", ROOT / "scripts" / "icon.swift", iconset)
    run("iconutil", "-c", "icns", iconset, "-o", resources / "Peak.icns")
    # Strip Finder metadata inherited by copy2; codesign rejects these attributes.
    for attribute in ["com.apple.FinderInfo", "com.apple.ResourceFork"]:
        subprocess.run(["xattr", "-dr", attribute, str(app)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Signing the PyInstaller wrapper changes its layout; keep the official signature intact.
    run("codesign", "--force", "--sign", "-", app)
    run("codesign", "--verify", "--deep", "--strict", app)
    for tool in ["ffmpeg", "ffprobe", "deno", "yt-dlp"]:
        flag = "-version" if tool.startswith("ff") else "--version"
        print(run(tools / tool, flag, env={**os.environ, "PATH": "/usr/bin:/bin"}).splitlines()[0])
    # Ensure no shipped Mach-O depends on Homebrew at runtime.
    for name in copied:
        if any("/opt/homebrew/" in dep for dep in dependencies(tools / name)):
            raise RuntimeError(f"Nonportable dependency remains in {name}")
    payload = dist / "payload"
    if payload.exists():
        shutil.rmtree(payload)
    (payload / "Applications").mkdir(parents=True)
    shutil.copytree(app, payload / "Applications" / "Peak.app", symlinks=True)
    component = dist / "Peak-component.pkg"
    run("pkgbuild", "--root", payload, "--identifier", "io.github.seth-person.peak", "--version", VERSION,
        "--install-location", "/", "--ownership", "recommended", component)
    distribution = dist / "Distribution.xml"
    distribution.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
<title>Peak {VERSION}</title>
<options customize="never" require-scripts="false" hostArchitectures="arm64"/>
<allowed-os-versions><os-version min="{min_os}"/></allowed-os-versions>
<choices-outline><line choice="peak"/></choices-outline>
<choice id="peak" visible="false"><pkg-ref id="io.github.seth-person.peak"/></choice>
<pkg-ref id="io.github.seth-person.peak" version="{VERSION}" onConclusion="none">Peak-component.pkg</pkg-ref>
</installer-gui-script>
''')
    installer = dist / f"Peak-{VERSION}-arm64.pkg"
    run("productbuild", "--distribution", distribution, "--package-path", dist, installer)
    stage = dist / "dmg-stage"
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir()
    shutil.copytree(app, stage / "Peak.app", symlinks=True)
    (stage / "Applications").symlink_to("/Applications")
    (stage / "Install Peak.txt").write_text(f"Peak {VERSION}\n\nRequires Apple Silicon and macOS {min_os} or later.\n\nDrag Peak to Applications, then open it.\n\nThis private build is ad-hoc signed and not Apple-notarized. If macOS blocks it, use System Settings > Privacy & Security > Open Anyway after attempting to open Peak.\n\nDownloads save to ~/Downloads/Peak by default.\n")
    dmg = dist / f"Peak-{VERSION}-arm64.dmg"
    if dmg.exists():
        dmg.unlink()
    run("hdiutil", "create", "-volname", "Peak 1.0", "-srcfolder", stage, "-ov", "-format", "UDZO", dmg)
    shutil.copy2(resources / "dependency-manifest.json", dist / "dependency-manifest.json")
    (dist / "SHA256SUMS.txt").write_text("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in [installer, dmg]))
    for artifact in [installer, dmg, dist / "dependency-manifest.json", dist / "SHA256SUMS.txt"]:
        shutil.copyfile(artifact, output / artifact.name)
    shutil.rmtree(dist)
    print(f"Built {installer.name} and {dmg.name}; requires macOS {min_os}+")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ytdlp", help="Path to predownloaded, checksum-verified yt-dlp_macos")
    parser.add_argument("--build-dir")
    package(parser.parse_args())
