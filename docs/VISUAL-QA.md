# Visual comparison and validation plan

The handed-off three macOS samples were all **expanded-results screenshots** at
1712 × 1366 (2× logical scale). There was *no* collapsed-state Mac screenshot;
do not infer its precise geometry from these samples. The supplied Linux output
was an earlier Fedora Asahi capture at ~1.45× raster scale. Those images remain
private references and are not redistributed here.

Measured macOS reference geometry (logical units):

| Surface property | Measured target |
|---|---:|
| Outer panel | 640 × 467 |
| Header / separator | 56 / 1 |
| Separator side inset | 20 |
| Row selection | 620 × 56 |
| Highlight side inset | 10 |
| First / later row steps | 58 / 56 |
| Highlight effective cubic radius / factor | ~21.4 / 0.665 |
| Panel effective cubic radius / factor | ~30.75 / 0.64 |
| Search icon size / left inset | 23 / 20 |
| Leading app icon | ~29 |
| Native reference RGB blue selection / gray fill | (78,123,223) / (43,43,43) |

The previous Fedora Asahi capture measured ~10.34-point selection side insets,
56.55-point selection height and ~124.69-point second-row top, compared to a
125-point Mac target. Those results belong to **the prior v17 build**, not this
candidate's unverified runtime.

The new C++ mask follows the same cubic-control geometry as the QML surface.
This addresses one explainable mismatch: ordinary rounded masks can leave blur
and interactive bounds outside the visible continuous corners. **No claim of
pixel improvement is made until fresh captures validate it.**

## Real GUI test matrix (release blocking)

On every listed native target, capture only the KRunner window using neutral
placeholder names, synthetic user-owned files and non-private app names. Avoid
any full desktop wallpaper, real documents, usernames or home paths.

1. Collapsed default window; hover reveal rail; rail retract animation.
2. First typed query, unselected results, gray hovered first result, blue
   keyboard-selected second result; capture all at the same display scale.
3. Many app/file items, long titles and descriptions, subtitles, calculator,
   query/provider reordering and results with/without a provider Tab action.
4. Repeat **`import` → `s`** at least ten times in the same open window;
   ensure no removed Kamoso/Ghostty/KMail Import Wizard/Sieve Editor text draws
   over the current result. Observe `index == -1` delegates if debugging.
5. Query **`window`**, then **six Down presses**. Check pixel-derived last blue
   row bottom clearance against its side clearances.
6. Test Enter, Up/Down, empty-query Tab, Tab with first action, Tab without any
   action, Esc. Never execute a provider's destructive action during purely
   visual verification.
7. Repeat under Wayland / X11 (if available), 100% / fractional / 200% scaling,
   narrow screens, compositor blur disabled, software renderer and screen reader.
8. Capture animation frames (e.g. 0/80/160/320 ms) and compare height,
   opacity, border/blur alignment and clipping. Run the previously documented
   opt-in `KRUNNER_SPOTLIGHT_PREVIEW` mechanism only in a throwaway test account.
   It requires building with `-DKRUNNER_SPOTLIGHT_DEVELOPER_PREVIEW=ON`; it is
   compiled out of regular binaries.

Normalize images to the same logical width (640 point panel); use the actual
captured outer-panel pixel width to infer each scale factor. Quantify bounding
boxes, relative title tops, selection inset, panel/header ratio, and compare
first/last animation frames. Font raster ink depends on family and scaling;
never infer UI geometry solely from QML numbers. Clearly label *actual captured*
results versus any illustrations.

Do **not** commit the handoff's Mac screenshots, Linux captures with private file
paths, exact filenames or source measurement JSON containing home directories.
