# Peak 1.2.0

- Visual video trimming on Mac and Windows: thumbnail timeline, draggable start/end handles, scrubbed-frame preview, frame stepping, exact time fields and selection duration.
- Trim immediately after an MP4 download or open an existing local video.
- Save a separate MP4 with precise cuts, progress and cancellation. Originals and existing files are preserved.
- High-quality H.264/AAC exports at source resolution; HDR inputs use 10-bit HEVC with source color tags. Trimming re-encodes and is lossy; HDR preview colors are approximate and dynamic HDR metadata is not guaranteed.
- Includes maximum-quality MP4 downloads, 24-bit PCM WAV and 320 kbps MP3 audio modes.
- Apple Silicon and Intel Mac DMG/PKG installers, plus a self-contained Windows x64 installer.

Requirements: Apple Silicon macOS 27+, Intel macOS 14+, or Windows 10/11 x64. Tools and runtimes are bundled. Mac builds are ad-hoc signed and not notarized; the Windows installer is unsigned.

Validation: synthetic non-keyframe trim tests check duration, selected first-frame quality, video/audio codecs, resolution, thumbnails, bounds and original preservation. Native Windows CI tests installation, installed-app checks, both windows rendering and uninstall. Intel binaries are exercised under Rosetta on Apple Silicon, not on physical Intel hardware.

WAV cannot restore detail lost in YouTube's compressed audio. MP3 conversion is lossy. Public accessible videos only; YouTube can block or rate-limit requests. Download media you own or have permission to save.
