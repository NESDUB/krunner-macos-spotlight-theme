#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Static hygiene checks; deliberately not called an integration or GUI test."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
files = [*root.glob("*.cpp"), *root.glob("*.h"), *root.glob("qml/*.qml")]
assert files, "No code files"
for p in files:
    data = p.read_text()
    assert "SPDX-License-Identifier:" in data, f"Missing license notice: {p}"
    assert not re.search(r"/home/(?:nes|dwayne)/|/Users/", data), f"Private path: {p}"
assert (root / "LICENSES/GPL-2.0-or-later.txt").is_file()
assert (root / "LICENSES/LGPL-2.0-or-later.txt").is_file()
qml = (root / "qml/RunCommand.qml").read_text()
result = (root / "qml/SpotlightResult.qml").read_text()
view = (root / "view.cpp").read_text()
assert "root.activatePrimaryResultAction()" in qml
assert "results.runAction(0)" in qml
assert "visible: index >= 0" in result
assert "index >= 0" in result
assert 'anchors.right: parent.right' in result
assert "glassPath" in view and "cornerFactor" in view
assert "readEntry(\"FreeFloating\", true)" in view
assert "availablePanelWidth" in qml
print(f"Static source checks passed ({len(files)} C++/QML files). Not a GUI build test.")
