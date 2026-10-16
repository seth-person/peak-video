# Third-party software

Peak bundles these tools for local execution. Their licenses are independent of Peak's application source.

* **yt-dlp 2026.08.19**: https://github.com/yt-dlp/yt-dlp — Unlicense for project source; its standalone macOS executable includes third-party code and is distributed under the terms described in its THIRD_PARTY_LICENSES.txt (including GPLv3+ components).
* **FFmpeg / ffprobe**: https://ffmpeg.org — this Homebrew build enables GPL and version 3 components. See the packaged COPYING.GPLv3, LICENSE.md, exact build configuration (`ffmpeg -version`), Homebrew receipt, and dependency manifest.
* **Deno**: https://github.com/denoland/deno — MIT, with third-party components under their respective licenses.
* Native codec and supporting libraries bundled from Homebrew are listed with their exact original paths and SHA-256 values in `dependency-manifest.json`. Available license files, receipts and software bills of materials are included under `Peak.app/Contents/Resources/Licenses`.

Homebrew formula sources and source download references: https://github.com/Homebrew/homebrew-core/tree/main/Formula

This private build is for the repository owner's local use. Before redistributing third-party binaries outside your own organization, satisfy their corresponding-source and notice obligations; source links alone do not replace any applicable corresponding-source obligation.
