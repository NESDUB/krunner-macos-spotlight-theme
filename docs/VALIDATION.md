# v0.1.0 validation — 2026-10-16

## Tested environment

Fedora Asahi Remix 44 / aarch64 / KDE Wayland; Plasma 6.7.5, Qt 6.11.2,
KDE Frameworks 6.31.0. Native Release build with developer diagnostics OFF.

## Completed

- Native C++/QML compilation and startup with installed providers.
- 13 mocked installer lifecycle/conflict/failure tests and 3 static visual contracts.
- Actual manager install of the previous candidate, update to optical refinement,
  checksum verification, rollback with checksum verification, update again and
  uninstall. User service was active after uninstall; stock KRunner was restored.
- Pre-existing legacy ExecStart override correctly refused before migration.
  For the controlled test, that override was backed up outside the unit directory;
  it was restored after the test, along with the approved refined binary.
- Rapid repeated restarts hit systemd's start-rate limit during final restoration.
  Clearing that limit and starting the service restored normal operation; recovery
  is documented. This was not a reproducible launcher crash.
- App header icon tracks keyboard selection; Open cue remains passive.
- Native app/file/calculator queries and long input rendered without collisions.
- Ten repeated import -> s changes ended with no overlapping stale labels.
- window + six Down presses: left/right/bottom clear gaps 14/13/13 source pixels.
- File Tab badge right inset: 10 logical points.
- The owner reviewed the installed refinement and approved its appearance.

## Still untested

Other Plasma versions, x86_64, X11, narrow displays, alternative scaling and font
fallback, screen readers, IME and complete keyboard/provider-action integration.
The sampled animation diagnostic was focus/provider-timing sensitive; it is not
proof of perceptual smoothness. No claim of pixel-exact macOS Liquid Glass.

Public screenshots show neutral app-only results and idle state over Tahoe Night,
cropped from live compositor captures to exclude personal desktop items. Private Mac references,
full desktop captures, local filenames and development history are not published.
