# SPDX-License-Identifier: GPL-2.0-or-later
"""Non-rendering visual invariants; Fedora screenshots are still required."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class VisualContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = (ROOT / 'qml/RunCommand.qml').read_text()
        cls.row = (ROOT / 'qml/SpotlightResult.qml').read_text()
        cls.panel = (ROOT / 'qml/GlassPanel.qml').read_text()

    def test_approved_glass_and_selection_are_unchanged(self):
        self.assertIn('surfaceColor: "#60363742"', self.root)
        self.assertIn('surfaceColor: row.selectionShown ? "#4e7bdf" : row.hovered ? "#575962" : "transparent"', self.row)
        self.assertIn('radius: 21.375', self.row)
        self.assertIn('cornerFactor: 0.665', self.row)
        self.assertIn('Layout.bottomMargin: 10.75', self.root)
        self.assertIn('Layout.leftMargin: 10', self.root)
        self.assertIn('Layout.rightMargin: 10', self.root)

    def test_refinements_are_noninteractive_and_contextual(self):
        self.assertIn('rimLight: true', self.root)
        self.assertIn('property bool rimLight: false', self.panel)
        self.assertIn('readonly property bool showApplicationContext:', self.root)
        self.assertIn('results.currentItem.applicationResult', self.root)
        self.assertIn('root.currentApplicationItem.model.decoration', self.root)
        self.assertIn('text: "↵ Open"', self.root)
        self.assertIn('Accessible.ignored: true', self.root)
        self.assertIn('currentApplicationItem !== null', self.root)
        self.assertIn('queryField.cursorPosition === queryField.text.length', self.root)
        self.assertIn('typedQueryMetrics.advanceWidth', self.root)
        self.assertIn('!queryField.inputMethodComposing', self.root)

    def test_provider_and_removed_delegate_behavior_is_preserved(self):
        self.assertIn('root.activatePrimaryResultAction()', self.root)
        self.assertIn('results.runAction(0)', self.root)
        self.assertIn('results.runCurrentIndex(event)', self.root)
        self.assertIn('visible: index >= 0', self.row)
        self.assertIn('enabled: index >= 0', self.row)
        self.assertIn('row.selectionShown && row.hasPrimaryAction', self.row)
        self.assertIn('anchors.right: parent.right', self.row)


if __name__ == '__main__':
    unittest.main()
