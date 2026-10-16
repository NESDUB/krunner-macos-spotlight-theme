# SPDX-License-Identifier: GPL-2.0-or-later
"""Filesystem and service mocks; no live desktop or program launches."""
import importlib.util
import json
import os
from pathlib import Path
import platform
import tempfile
import types
import unittest
from unittest import mock

MODULE = Path(__file__).resolve().parents[1] / "tools/manage.py"
spec = importlib.util.spec_from_file_location("manage", MODULE)
manage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manage)


def fake_elf(arch=None, suffix=b"a"):
    arch = arch or platform.machine()
    machine = {"x86_64": 62, "aarch64": 183}[arch]
    buf = bytearray(80)
    buf[:4] = b"\x7fELF"
    buf[18:20] = machine.to_bytes(2, "little")
    return bytes(buf) + suffix


class ManagerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        home = Path(self.tmp.name)
        self.p = {
            "storage": home / ".local/share/krunner-spotlight",
            "binary": home / ".local/share/krunner-spotlight/bin/krunner-spotlight",
            "previous": home / ".local/share/krunner-spotlight/backups/previous-binary",
            "state": home / ".local/share/krunner-spotlight/state.json",
            "service": home / ".config/systemd/user/plasma-krunner.service.d" / manage.DROPIN,
        }
        self.calls = []
        self.inject_failure = False
        self.foreign = False
        self.user_unit = False
        self.no_session = False
        self.patchers = [
            mock.patch.object(manage, "paths", return_value=self.p),
            mock.patch.object(manage, "run", side_effect=self.fake_run),
            mock.patch.object(manage, "check_host", side_effect=self.fake_check),
        ]
        for p in self.patchers:
            p.start()
            self.addCleanup(p.stop)
        self.a = home / "build-a"
        self.a.write_bytes(fake_elf(suffix=b"first"))
        self.b = home / "build-b"
        self.b.write_bytes(fake_elf(suffix=b"second"))

    def fake_run(self, *command, check=True):
        self.calls.append(command)
        if command[-1] == "cat":
            pass
        if command == ("systemctl", "--user", "cat", manage.UNIT):
            cat = "# /usr/lib/systemd/user/plasma-krunner.service\n[Service]\nExecStart=/usr/bin/krunner --daemon\n"
            if self.user_unit:
                cat = "# /home/user/.config/systemd/user/plasma-krunner.service\n[Service]\nExecStart=/usr/bin/other\n"
            if self.foreign:
                cat += "# /home/user/.config/systemd/user/plasma-krunner.service.d/50-other.conf\n[Service]\nExecStart=\nExecStart=/usr/bin/other\n"
            return types.SimpleNamespace(stdout=cat, stderr="")
        if self.inject_failure and command == ("systemctl", "--user", "restart", manage.UNIT) and check:
            raise OSError("simulated systemd restart failure")
        return types.SimpleNamespace(stdout="", stderr="")

    def fake_check(self):
        if self.foreign or self.user_unit:
            manage.service_status()  # actually parses fake cat and detects conflict
        if self.no_session:
            raise manage.InstallError("no user systemd")
        return {}

    def test_fresh_install_update_rollback_uninstall(self):
        manage.install(types.SimpleNamespace(binary=str(self.a)))
        first = self.a.read_bytes()
        self.assertEqual(self.p["binary"].read_bytes(), first)
        self.assertEqual(self.p["service"].read_text(), manage.SERVICE_TEXT)
        self.assertFalse(self.p["previous"].exists())
        manage.install(types.SimpleNamespace(binary=str(self.b)), updating=True)
        self.assertEqual(self.p["binary"].read_bytes(), self.b.read_bytes())
        self.assertEqual(self.p["previous"].read_bytes(), first)
        manage.rollback()
        self.assertEqual(self.p["binary"].read_bytes(), first)
        self.assertFalse(self.p["previous"].exists())
        manage.uninstall()
        for k in ("binary", "service", "state", "previous"):
            self.assertFalse(self.p[k].exists(), k)
        self.assertIn(("systemctl", "--user", "daemon-reload"), self.calls)

    def test_repeated_install_refused(self):
        manage.install(types.SimpleNamespace(binary=str(self.a)))
        with self.assertRaisesRegex(manage.InstallError, "Already installed"):
            manage.install(types.SimpleNamespace(binary=str(self.a)))

    def test_update_without_install_refused(self):
        with self.assertRaisesRegex(manage.InstallError, "Not installed"):
            manage.install(types.SimpleNamespace(binary=str(self.b)), updating=True)

    def test_conflicting_override_refused_without_writes(self):
        self.foreign = True
        with self.assertRaisesRegex(manage.InstallError, "Existing KRunner ExecStart"):
            manage.install(types.SimpleNamespace(binary=str(self.a)))
        self.assertFalse(self.p["state"].exists())

    def test_custom_user_unit_refused(self):
        self.user_unit = True
        with self.assertRaisesRegex(manage.InstallError, "replacement user units"):
            manage.install(types.SimpleNamespace(binary=str(self.a)))
        self.assertFalse(self.p["state"].exists())

    def test_unmanaged_file_protected(self):
        self.p["service"].parent.mkdir(parents=True)
        self.p["service"].write_text("# foreign")
        with self.assertRaisesRegex(manage.InstallError, "Unmanaged"):
            manage.install(types.SimpleNamespace(binary=str(self.a)))
        self.assertEqual(self.p["service"].read_text(), "# foreign")

    def test_modified_dropin_refuses_update_and_uninstall(self):
        manage.install(types.SimpleNamespace(binary=str(self.a)))
        self.p["service"].write_text("# deliberately modified\n")
        with self.assertRaisesRegex(manage.InstallError, "drop-in has changed"):
            manage.install(types.SimpleNamespace(binary=str(self.b)), updating=True)
        with self.assertRaisesRegex(manage.InstallError, "drop-in has changed"):
            manage.uninstall()

    def test_wrong_architecture_refused(self):
        other = "aarch64" if platform.machine() == "x86_64" else "x86_64"
        self.b.write_bytes(fake_elf(other))
        with self.assertRaisesRegex(manage.InstallError, "architecture"):
            manage.install(types.SimpleNamespace(binary=str(self.b)))
        self.assertFalse(self.p["service"].exists())

    def test_missing_elf_refused(self):
        self.b.write_bytes(b"this is not an ELF binary")
        with self.assertRaisesRegex(manage.InstallError, "non-ELF"):
            manage.install(types.SimpleNamespace(binary=str(self.b)))

    def test_no_session_refused(self):
        self.no_session = True
        with self.assertRaisesRegex(manage.InstallError, "no user systemd"):
            manage.install(types.SimpleNamespace(binary=str(self.a)))
        self.assertFalse(self.p["binary"].exists())

    def test_restart_failure_restores_install_state(self):
        self.inject_failure = True
        with self.assertRaisesRegex(OSError, "simulated systemd"):
            manage.install(types.SimpleNamespace(binary=str(self.a)))
        for k in ("binary", "service", "state", "previous"):
            self.assertFalse(self.p[k].exists(), k)

    def test_restart_failure_on_update_restores_previous_version(self):
        manage.install(types.SimpleNamespace(binary=str(self.a)))
        old_state = self.p["state"].read_bytes()
        self.inject_failure = True
        with self.assertRaisesRegex(OSError, "simulated systemd"):
            manage.install(types.SimpleNamespace(binary=str(self.b)), updating=True)
        self.assertEqual(self.p["state"].read_bytes(), old_state)
        self.assertEqual(self.p["binary"].read_bytes(), self.a.read_bytes())
        self.assertFalse(self.p["previous"].exists())

    def test_uninstall_restart_failure_restores_managed_override(self):
        manage.install(types.SimpleNamespace(binary=str(self.a)))
        self.inject_failure = True
        with self.assertRaisesRegex(OSError, "simulated systemd"):
            manage.uninstall()
        self.assertEqual(self.p["service"].read_text(), manage.SERVICE_TEXT)
        self.assertTrue(self.p["state"].exists())

if __name__ == "__main__":
    unittest.main()
