# Peak 1.0.0

Initial release of a native Mac YouTube-to-MP4 downloader.

* Maximum-quality video and audio selection with lossless MP4 merging/remuxing.
* Optional H.264/AAC compatibility mode and resolution limits.
* Video preview, progress, cancellation/resume, folder selection, and Finder reveal.
* Self-contained yt-dlp, FFmpeg, ffprobe, and Deno bundle. No Homebrew installation required to use Peak.
* Private, local operation without a backend or analytics.

## Downloads

* **Peak-1.0.0-arm64.dmg** — drag Peak into Applications.
* **Peak-1.0.0-arm64.pkg** — standard Mac installer.
* **SHA256SUMS.txt** — hashes for both installers.
* **dependency-manifest.json** — bundled tool versions, origins, and input hashes.

**Requires Apple Silicon and macOS 27+.** The app is ad-hoc signed and not Apple-notarized. If macOS blocks it, use System Settings → Privacy & Security → Open Anyway after attempting to open the downloaded item.

Maximum-quality MP4s may contain AV1/VP9 and Opus; playback depends on your player. Compatibility mode requests H.264/AAC and may offer lower resolution. One public video per operation; no playlists, active livestreams, browser-cookie import, or automatic updater in 1.0.

Use for videos you own or have permission to download. YouTube availability and rate limits still apply.
