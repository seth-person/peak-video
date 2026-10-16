# Peak

A local YouTube downloader for Mac and Windows. Save the highest available video quality as **MP4**, or choose audio-only **WAV** and **MP3**. Trim a downloaded or existing video with a visual thumbnail timeline.

## Install 1.2

Download the installer for your machine from [Releases](https://github.com/seth-person/peak-video/releases/tag/v1.2.0):

| Machine | Installer | Requirement |
| --- | --- | --- |
| Apple Silicon Mac | `Peak-1.2.0-arm64.dmg` or `.pkg` | macOS 27+ |
| Intel Mac | `Peak-1.2.0-x86_64.dmg` or `.pkg` | macOS 14+ |
| Windows PC | `Peak-1.2.0-windows-x64.exe` | Windows 10/11, 64-bit x64 |

Mac: open the DMG and drag Peak to Applications, or use the PKG. Windows: run the installer; it installs for your user and adds a Start menu shortcut and uninstaller. All builds include yt-dlp, FFmpeg, ffprobe and Deno. Windows includes its .NET runtime. No separate dependency setup is needed.

These builds do not have commercial signing certificates. Mac apps are ad-hoc signed and not notarized; if blocked, attempt to open the specific app/installer, then use **System Settings → Privacy & Security → Open Anyway**. Windows may show an unknown-publisher/SmartScreen prompt. Verify the release and its SHA-256 checksums before opening. Do not disable system-wide protections.

## Use

1. Paste a YouTube video, Shorts, or completed livestream URL.
2. Select **MP4 · Video**, **WAV · Audio**, or **MP3 · Audio**.
3. For MP4, choose Maximum quality or Wide compatibility and an optional resolution limit.
4. Optionally preview, choose a save folder, then click **Download**.
5. Use **Show in Finder/Explorer** when complete, or **Trim video** for MP4.
6. In the trim editor, drag the mint start/end handles and click the timeline to inspect a frame. Use frame-step buttons or start/end seconds for finer control, then **Save trimmed MP4**. You can also choose **Open video to trim…** for an existing local video.

Downloads default to `Downloads/Peak`; your chosen folder is remembered. Progress measures the current source stream. MP4 usually downloads separate video/audio streams before merging. Cancelling stops the downloader and conversion processes; partial downloads can resume on retry. Existing completed files are not overwritten. Filenames include the video ID and format/quality preset.

## Quality

**MP4 — Maximum quality:** selects the best available video and audio streams, then merges/remuxes without re-encoding. No resolution cap by default, allowing 4K, 8K or whatever the source provides. Ranking prioritizes resolution, frame rate, HDR and codec quality. MP4 is a container; AV1/VP9 video or Opus audio may require a compatible player.

**MP4 — Wide compatibility:** H.264 video plus AAC audio. YouTube may offer these only at 1080p or below. If unavailable, Peak reports an error rather than silently choosing other codecs.

**WAV:** downloads the best available audio, then decodes to uncompressed **24-bit PCM**, preserving the source sample rate and channel layout. Files are large. YouTube audio is already compressed; WAV does not restore lost information or create a lossless original.

**MP3:** downloads the best available audio, then converts to **320 kbps MP3**. MP3 conversion is lossy. Source sample rate/channel layout are preserved where supported by MP3.

Audio-only modes do not download video when an audio-only stream is available. Video quality and resolution settings do not affect audio modes.

## Video trimming

The editor shows 12 thumbnails across the source, a large scrubbed-frame preview, a playhead, adjustable handles, millisecond time fields and selection duration. Times snap to the nearest frame. Frame steps use the average source frame rate; variable-frame-rate sources can have uneven frame spacing. The end time is exclusive. Preview generation stays local and is cancelled when you scrub again or close the editor.

Precise cuts re-encode to high-quality H.264 (CRF 16, slow preset) and AAC at the original resolution. HDR inputs use 10-bit HEVC with source color tags; previews are approximate and dynamic HDR metadata is not guaranteed to survive export. Trimming is lossy, unlike the original maximum-quality download. The original file is preserved, exports require a new filename, and cancelled exports remove their partial output. This is a single-range trim editor; it does not crop the picture, join clips, or add transitions.

## Scope and privacy

One video at a time; playlist-only URLs are rejected. Public accessible videos and finished livestreams are supported. Live/upcoming streams, cookie import, sign-in, paid-content access and DRM circumvention are outside this release. YouTube may rate-limit or block requests; diagnostics appear under Details. No automatic updater: future releases can bundle extractor updates.

Peak runs locally, with media traffic going directly to YouTube and its media hosts. There is no Peak server, analytics or account. Links and downloaded files are not uploaded to GitHub. Tools ignore global yt-dlp settings, disable remote component fetching, accept validated YouTube URLs, and receive arguments directly without shell interpolation. Download only media you own or have permission to save.

## Build and test

Mac UI: SwiftUI; core logic: Swift. Windows UI: C# WinForms on .NET 10. Source is in `Sources/` and `windows/Peak/`.

```sh
# Mac core checks (no XCTest dependency)
swift run PeakCoreChecks
# Apple Silicon package; local Homebrew dependencies determine minimum OS
brew install ffmpeg deno
python3 scripts/package.py --arch arm64
# Intel package, including cross-compilation on an Apple Silicon Mac
python3 scripts/package.py --arch x86_64
# Synthetic trim test: timing, selected first frame, codecs, thumbnails and preservation
swift run PeakCoreChecks --trim-integration /path/to/Peak.app/Contents/Resources/Tools /tmp/peak-trim-test
# Optional live test: MP4 in both modes, WAV, and MP3
swift run PeakCoreChecks --integration /path/to/Peak.app/Contents/Resources/Tools /tmp/peak-test
```

The source targets macOS 14+. Apple Silicon releases currently bundle macOS 27 Homebrew binaries and therefore require macOS 27. Intel packages use standalone x86_64 dependencies. Packaging validates hashes, load paths, signatures and tool startup. Use `--ytdlp`, `--build-dir` and `--dependency-cache` to reuse local inputs.

On Windows, install .NET SDK 10.0.402 and NSIS, then run:

```powershell
./scripts/package-windows.ps1
```

The Windows Actions workflow builds the self-contained executable and installer, verifies URL/format logic, bundled-tool startup, WAV/MP3 codecs and bitrate, process cancellation, silent installation, installed-app tests, main-window and trim-editor rendering, accurate non-keyframe trimming, thumbnail generation, original-file preservation and uninstallation. Build artifacts are available from the workflow run. Windows installer tests do not depend on YouTube access from cloud runners.

Pinned Windows/Intel downloads are in `scripts/dependencies.json`; yt-dlp macOS is pinned in `scripts/package.py`. Update versions and checksums together. Homebrew dependency paths and hashes are recorded per build. `dist/` contains installers and manifests; binaries are excluded from Git source.

See [THIRD_PARTY.md](THIRD_PARTY.md) for component notices. Signing keys and credentials are never committed.
