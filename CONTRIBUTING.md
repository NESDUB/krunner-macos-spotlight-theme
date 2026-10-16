# Contributing

Please start with an issue describing the Plasma, KF6/Qt, architecture,
compositor/session and screen scale used. Provide minimal reproduction steps.
Prefer small changes with tests. Do not remove KDE copyright/SPDX notices or
copy assets from proprietary Apple components. UI screenshots must be cropped to
the launcher and use neutral data. Design changes must retain KRunner native
providers, Enter and action-Tab behavior. Changes affecting geometry require
actual before/after captures and pixel comparisons under the same scale.

Before opening a pull request:

```bash
python3 -m unittest discover -s tests -v
python3 tools/check_source.py
python3 tools/manage.py status
```

Maintainers may require live KDE/Wayland and X11 QA before merging. Do not claim
that CI static checks prove runtime behavior, or distribute snapshots collected
from private machines. All code contributions should be compatible with the
file-level SPDX licenses (GPL-2.0-or-later / LGPL-2.0-or-later).

## CI template

The checked-in `.github/workflow-templates/checks.yml` runs tests and source
checks. Move it into `.github/workflows/checks.yml` to enable GitHub Actions
using credentials authorized to create workflows. The initial publisher's OAuth
credential did not have workflow scope, so the template is shipped inactive.
Run the same checks locally with `python3 -m unittest discover -s tests -v`
and `python3 tools/check_source.py`.
