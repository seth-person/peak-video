# Peak 1.1.0

- New audio-only mode: 24-bit PCM WAV and 320 kbps MP3, both starting with the best available audio stream.
- Separate Intel Mac DMG and PKG installers, alongside updated Apple Silicon installers.
- New native Windows app and self-contained x64 installer, with Start menu shortcut and uninstaller.
- MP4 retains maximum-quality stream copying and H.264/AAC compatibility options.
- Format-specific filenames, progress, cancellation, and Finder/Explorer reveal.

Requirements: Apple Silicon macOS 27+, Intel macOS 14+, or Windows 10/11 x64. Tools and runtimes are bundled. The Mac builds are ad-hoc signed and not notarized; the Windows installer is unsigned.

WAV is an uncompressed decode of YouTube's compressed audio, not a restored lossless original. MP3 conversion is lossy. Public accessible videos only; YouTube can block or rate-limit requests.
