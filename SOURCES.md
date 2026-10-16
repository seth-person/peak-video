# Bundled software source references

Peak invokes these tools as separate processes. Peak's MIT license applies to its application source, not to the independently licensed bundled executables and libraries.

| Component | Source and build information |
| --- | --- |
| yt-dlp 2026.08.19 | [Tagged source, dependency declarations, and release build workflows](https://github.com/yt-dlp/yt-dlp/tree/2026.08.19); [standalone executable notices](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/THIRD_PARTY_LICENSES.txt) |
| FFmpeg 9.0.2 | [Tagged source](https://github.com/FFmpeg/FFmpeg/tree/n9.0.2); [source archive](https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz) |
| Intel FFmpeg and linked codecs | [Evermeet build configuration and library versions/source links](https://evermeet.cx/ffmpeg/); [exact build information](https://evermeet.cx/ffmpeg/info/ffmpeg/9.0.2) |
| Windows FFmpeg and linked codecs | [Gyan build information and library list](https://www.gyan.dev/ffmpeg/builds/); [release source revision](https://github.com/FFmpeg/FFmpeg/commit/946fcce07b) |
| Deno 2.9.7 | [Tagged source, dependency lockfiles, and build instructions](https://github.com/denoland/deno/tree/v2.9.7) |
| .NET 10 runtime | [Runtime source and third-party notices](https://github.com/dotnet/runtime/tree/v10.0.10); [Windows Forms source](https://github.com/dotnet/winforms/tree/v10.0.10) |
| NSIS 3.10 installer stub | [Source and license](https://nsis.sourceforge.io/Download) |

Apple Silicon packages use Homebrew FFmpeg 9.0.2_1 and its native dependencies. The release's `dependency-manifest-arm64.json` identifies each original binary version and SHA-256. The app includes Homebrew `INSTALL_RECEIPT.json`, available `sbom.spdx.json`, and license files under `Contents/Resources/Licenses`. The SBOMs identify source packages and checksums; [Homebrew formula history](https://github.com/Homebrew/homebrew-core) provides their build recipes.

Mac packaging changes the load paths of Homebrew dynamic libraries to make the bundle portable and ad-hoc signs the copied binaries. Those transformations are implemented in `scripts/package.py`; the original hashes are retained in the manifest. Intel and Windows archive URLs/hashes are pinned in `scripts/dependencies.json`.
