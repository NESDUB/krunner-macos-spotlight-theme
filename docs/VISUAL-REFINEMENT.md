> Historical design/review notes. The subsequent Fedora build and live tests
> are recorded in [VALIDATION.md](VALIDATION.md), which supersedes the pending
> build/capture statements below.

# Optical refinement variant — 2026-10-16

This is a **source-level visual variant** based on the community candidate and
custom-v17. It is **not** a claim of visual fidelity or a new cross-distro
binary release. The owner reports that the previous candidate now builds on
Fedora Asahi ARM64 and all 13 installer tests pass. That success is for the
**previous candidate**: build and capture this revised variant separately.

## Measured vs. inferred differences

The only full-resolution Mac captures in the private handoff are three expanded
views (no empty/collapsed-state capture). Their measured geometry is a 640×467
logical panel, 56-unit header, 600-unit separator inset by 20, 620×56
selection inset by 10, first/second row step 58 and then 56, ~30.75/0.64
outer cubic, and ~21.4/0.665 highlight cubic. The earlier actual Linux v17
capture measured 10.34-unit highlight side inset, 56.55-unit highlight height,
and 124.69-unit second-result top against a 125-unit Mac target. These
measurements are from **the prior captures**, not this new build.

The remaining visible differences are mostly optical, not a request for a new
layout: macOS shows a more nuanced illuminated glass rim and, for typed app
results, a tiny contextual icon at the header's right plus an inline action
cue. The KDE rows previously used several toolkit/default text faces, so the
search and result typography could differ with the system theme. The Mac's
nearly black fill is **intentionally not** copied because the author approved
`#60363742` in both search states.

## Precisely what changed in source

| Refinement | Implementation | Potential runtime caveat |
|---|---|---|
| Curved top-edge rim | `GlassPanel.qml`: second outline-only continuous cubic, enabled for the main surface; **base fill unchanged** | Composite/antialias may differ with DPR and KWin blur |
| App context icon | `RunCommand.qml`: 26-unit trailing Kirigami icon from the **current native application result**, only at ≥520-unit panel width | Must verify currentItem model decoration, provider reorder and display on Fedora |
| Header action cue | Passive `↵ Open` badge placed after measured query text; hidden when there is insufficient space, an active completion, or no native application result | Check cursor, IME, long queries, accessibility and focus; Enter still performs native action |
| Typography coherence | `SpotlightResult.qml`: Noto Sans consistently with the existing search field; **font sizes untouched** | Compare actual font fallback / raster metrics; may be preferable to use the user's system font |

Not modified: the approved glass fill and before/after-typing stability;
row selection/hover colors; source panel width; header and separator geometry;
result row spacing, insets, detail and Tab anchor; 320-ms downward height
morph; native providers; Enter, Arrow and Tab handlers; removed-result
`index < 0` guards; accessibility row descriptions; user installer/rollback.

## Real KDE screenshots required before calling any change visually verified

Capture at **the same Fedora display scale** as a baseline candidate screenshot
and with this revised variant. Crop **only the launcher**; redact app/file
names and paths, or use neutral test data. Capture PNGs without resizing first.
A single still image cannot verify spring/hover animation or reveal timing.

1. **Idle/hover rail:** collapsed window before hover; at ~80/160/320/700 ms
   after hover; and after rail retract. Compare rail icons, bridge ghosting and
   capsule corners. The provided Mac reference does **not** establish idle
   geometry, so compare against your *approved KDE baseline*, not invented Mac
   measurements.
2. **App typed query, no selection/hover:** verify new 26-unit header icon,
   `↵ Open` chip alignment after one or two letters, rim visibility, same fill
   as idle and 20-unit separator insets. Use a short **non-private** app name.
3. **App query, gray first-row hover:** keep the pointer on the first result;
   confirm gray hover, icon identity and absence of any extra/fake Tab action.
4. **App query, Down to blue second result:** confirm the header icon follows
   the selected app; the selection is still 620×56 logical with a 10-unit inset
   and the Tab badge remains 10 units inside the row. Compare title/trailing
   descriptions and font ink with previous screenshot at the same scale.
5. **File results with long subtitle; calculator; 20+ character query; narrow
   panel (<520 units):** no header icon or Open hint for non-app results; no
   badge collision with text input or clipped cursor; no wrap, stale rows or
   unexpected change to primary Enter/Tab actions.
6. **Reordering and input:** repeat `import` → `s` ten times without removed
   delegate labels overlaying live results; verify typing/IME/composition,
   text selection and copy/paste, and keyboard-only navigation. Run `window`
   with six Down presses to check bottom clearance and all states.
7. **Blur disabled and scaling:** 100%, your Fedora Asahi fractional scale and
   200%, if possible. Capture the same panel over a contrasting light/dark
   background to compare outline glow without confusing wallpaper variations.

For after/before comparisons, normalize **both** images to the same 640-logical
panel width *after* identifying their own panel boundaries. Use panel width to
infer pixels per logical unit. Measure row bounds and text ink separately:
different fonts and DPRs legitimately move ink edges. Note whether each PNG
is a real screenshot, simulated crop, or reference. Prefer before/after
side-by-side crops without posting private Mac reference files.

## What cannot be validated by code/tests alone

- Subpixel top-rim illumination vs. KWin background blur, compositor blur mask
  edges and GPU quality/overdraw (requires stills on KDE/Wayland).
- Current native application icon availability/actual visual similarity and
  the position/legibility of the inline hint (requires app query PNGs).
- Font appearance, truncation, mixed-script text/IME at fractional scale
  (requires multiple queries and font/scaling capture).
- Reveal smoothness, hover ghosting, easing and perceived motion (requires
  short recording or frame-series, not one screenshot).
- Reduced motion, screen-reader focus, X11 and other Plasma versions (requires
  separate runtime/interaction tests, not just still screenshots).

## Verification status

- Existing 13 installer tests: re-run against this package.
- Three additional source-contract assertions check that approved paint,
  geometry and provider dispatch were not edited and new affordances remain
  contextual. **These are not screenshot or compile tests.**
- Native compilation and real new screenshots: **pending on the user's KDE
  machine**. No new runtime capture is shipped or implied.
