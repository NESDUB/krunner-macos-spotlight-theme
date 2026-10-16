> Historical design/review notes. The subsequent Fedora build and live tests
> are recorded in [VALIDATION.md](VALIDATION.md), which supersedes the pending
> build/capture statements below.

# Engineering review — 2026-10-16

> **Later status:** the user has reported a successful Fedora Asahi ARM64
> compilation and 13 passing installer tests for the **previous community
> candidate**. The subsequent optical refinement variant has additional QML
> changes and three source-contract checks; it needs its **own** native build
> and visual captures. See [visual refinement](VISUAL-REFINEMENT.md). The
> historical checks below describe the previous candidate when first created.


## Scope of code changes since the validated v17 baseline

1. `view.cpp`: the KDE compositor blur/input mask now follows the same
   continuous-corner Bézier control points as the `GlassPanel.qml` ShapePath,
   rather than using `QPainterPath::addRoundedRect` for every item. A separate
   rounded-rect fallback is retained for circular accessory button backgrounds.
2. `view.cpp`: absence of a `FreeFloating` config key defaults to true; an
   existing explicit user value still overrides this default. No key is changed.
3. `qml/RunCommand.qml`: surface width is capped by the actual native window's
   available inner width for narrow screens; normal full-size and expanded
   dimensions are unchanged. The primary Tab action guards a stale index.
4. `qml/SpotlightResult.qml`: removed delegate click/hover events cannot change
   currentIndex or run a provider. The existing `index < 0` hiding is retained.
5. Preview morph captures use `QStandardPaths::TempLocation`; all screenshot,
   trace and synthetic input diagnostics are compiled out unless the developer
   explicitly sets `KRUNNER_SPOTLIGHT_DEVELOPER_PREVIEW=ON`.
6. A redundant Qt6 `find_package` call was removed from CMake.

## Differences from macOS that cannot honestly be called exact

- SwiftUI/macOS 26 `GlassEffectContainer`, coalescence and proprietary blur
  response are not available on Linux. Qt Quick Shape and KDE KWin blur are
  approximations; no copied SF Symbols or Apple shaders are included.
- Native KRunner providers and their action names are not equivalent to Apple's
  privileged Spotlight application actions or app-scoped search.
- Icon assets, font fallback, color management, antialiasing and KDE scaling
  may change ink bounds relative to the supplied Mac @2x images.
- The Mac screenshot's nearly black fill contrasts with the approved user's
  translucent gray glass color. This difference is intentional and preserved.
- The three provided screenshots contain expanded result lists only; exact
  collapsed-rail styling cannot be validated from them.

## Verified here

- Reviewed provided 3 Mac original screenshots and Linux comparison captures.
- Reviewed handoff source and the independent SwiftUI reference implementation.
- Compared recorded Mac @2x measurements against v17 Linux measurement notes.
- 13 isolated management tests pass (mocked user systemd / filesystem).
- Static per-file copyright, private path, layout and action assertions pass.
- Source archive excludes all screenshots, old binary and private measurement
  JSON. SHA-256 packaged checksums and archive contents were verified.

## Not verified / blocking public binary release

- No Fedora Asahi aarch64 GUI session available here: cannot execute actual
  custom build, animate KDE Qt scenes or capture new runtime images.
- The current Debian container is missing KDE ECM/Qt6/Plasma headers, so this
  revised source has **not** passed a successful native C++ compile.
- No live systemd user service is changed; installation has not been executed
  on the actual host.
- X11, fractional DPI, other Plasma releases, accessibility and no-blur fallbacks
  remain untested on the revised build.
- Private repository history and attachments were not approved for visibility
  change. Existing repository remains private; no release published.

## Proposed publishable GitHub metadata (pending approval/testing)

Repository: `NESDUB/krunner-spotlight` (retain URL to preserve incoming links)

Description: `Unofficial macOS Spotlight-inspired native KRunner interface for KDE Plasma 6. Source-built with safe per-user install and restore.`

Topics: `kde`, `plasma6`, `krunner`, `spotlight`, `linux`, `qtquick`, `qml`,
`desktop-customization`, `wayland`.

A clean-history new public repository is preferable if review of the existing
private history finds secrets or identifying information. Do not change repo
visibility solely on the strength of these static checks.
