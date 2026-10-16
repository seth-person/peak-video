# Peak

A native Mac app for saving YouTube videos as MP4 while preserving the best available source quality.

## Install 1.0

Download **Peak-1.0.0-arm64.dmg** from this repository's Releases page, open it, and drag Peak into Applications. A standard **.pkg installer** is also provided.

**This release requires an Apple Silicon Mac and macOS 27 or later.** It bundles yt-dlp, FFmpeg, ffprobe, Deno, and their native libraries. Homebrew, Python, Node, and Terminal are not required to use the app.

This private build is ad-hoc signed, not signed with an Apple Developer ID or notarized. If macOS blocks the downloaded app or installer, attempt to open it, then use **System Settings → Privacy & Security → Open Anyway** for that specific item. Do not disable Gatekeeper globally.

## Use

1. Paste a YouTube video, Shorts, or completed livestream URL.
2. Optionally click **Preview video** to see the selected resolution, frame rate, duration, and estimated size when available.
3. Keep **Maximum quality** selected for the highest available streams. Leave the resolution limit at **Best available** to allow 4K, 8K, or whatever the source offers.
4. Choose a destination, then click **Download MP4** (⌘Return).
5. Use **Show in Finder** when it finishes.

Downloads go to `~/Downloads/Peak` by default. The app remembers your chosen folder. Download progress is per stream: video and audio usually download separately, followed by the MP4 merge. Cancelled partial downloads remain in the destination and are resumed when possible on retry.

### Quality and playback

**Maximum quality** selects the best available video-only and audio-only streams and merges/remuxes them into MP4 without re-encoding. Ranking prioritizes source resolution, frame rate, HDR, codec, audio channels, and bitrate. Peak cannot improve the source or access formats YouTube does not make available to the downloader.

MP4 is a container, not a codec. The best source may use AV1 or VP9 video and Opus audio; some versions of QuickTime and some editors cannot play these combinations. Use a player that supports those codecs, or select **Wide compatibility**, which requests H.264 video and AAC audio. Compatibility mode may be limited to 1080p or lower and fails clearly if compatible source streams are unavailable. It does not silently transcode or fall back to incompatible codecs.

Filenames include the video ID and quality preset so changing modes or resolution limits does not reuse a different preset's existing download. Existing completed files are not overwritten. If you want to re-fetch the same preset after YouTube changes the available formats, move or rename its previous file first.

### Scope and limitations

* One video at a time. A video link containing a playlist parameter downloads only that video. Playlist-only links are rejected.
* Live and upcoming streams are excluded. Completed streams depend on YouTube making their downloadable formats available.
* Public, accessible videos only in 1.0. No browser-cookie import, sign-in UI, DRM circumvention, or paid-content access.
* YouTube can rate-limit or block requests. Errors appear in the app; the Details panel includes downloader diagnostics. Try again later if YouTube asks for sign-in or blocks a request.
* No automatic updater in 1.0. A future app release can bundle an updated extractor if YouTube changes.
* Allow space for both source streams and the merged output during processing.
* Download videos you own or have permission to save.

## Privacy and implementation

Peak runs tools locally. Video traffic goes directly to YouTube and its media hosts; Peak has no backend, analytics, or account. Your links and downloaded media are not uploaded to GitHub. The app deliberately ignores global yt-dlp configurations, disables remote component fetching, accepts only validated YouTube video URLs, and passes arguments directly to `Process` without shell interpolation.

The UI is SwiftUI, with a separate `PeakCore` module for URL validation, format selection, metadata/progress parsing, and subprocess management. Cancellation terminates the downloader process tree, including active merge processes. Closing the app during an operation asks whether to keep downloading or cancel and quit.

## Build from source

The app source targets macOS 14+, but the **binary release's minimum OS is the highest requirement of its bundled dependencies**. This 1.0 build uses macOS 27 Homebrew binaries and therefore requires macOS 27.

On an Apple Silicon Mac with Apple's Command Line Tools or Xcode:

```sh
brew install ffmpeg deno
swift run PeakCoreChecks
python3 scripts/package.py
```

`package.py` downloads the official pinned yt-dlp macOS standalone binary and verifies its SHA-256, builds the app, copies all required Homebrew libraries into the bundle, rewrites their load paths, gathers license notices, checks the signatures and tool launch behavior, and produces the DMG, PKG, dependency manifest, and checksums under `dist/`.

The application has no Swift package dependencies. The standalone test executable avoids requiring XCTest, which is unavailable in some Command Line Tools installations. Build-only commands:

```sh
swift build --product Peak -c release
swift run PeakCoreChecks
# Optional network smoke test (downloads two short public test videos):
swift run PeakCoreChecks --integration /path/to/Peak.app/Contents/Resources/Tools /tmp/peak-smoke
```

The loose executable from `swift build` needs the bundled tools; run the `.app` produced by the packaging script for the complete experience. Use `--ytdlp /path/to/yt-dlp_macos` and `--build-dir /path/to/build` to reuse existing downloads/build artifacts.

### Release maintenance

Update the pinned yt-dlp version and SHA-256 in `scripts/package.py` together. Record the Homebrew binary versions through the generated dependency manifest; those dependencies are local build inputs rather than immutable downloads. Verify both quality modes, cancellation, MP4 codec information with ffprobe, and the app launched from the packaged disk image before publishing.

No Developer ID identity is needed for a private local build. For a future notarized distribution, sign every bundled executable/library and the app with a valid Developer ID Application identity using appropriate runtime entitlements, sign the installer with Developer ID Installer, submit to Apple's notary service, and staple the accepted ticket. Do not commit signing keys or credentials.

See [THIRD_PARTY.md](THIRD_PARTY.md) for bundled component licenses and source references.
