#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Conservative per-user deployment of a locally built, version-matched KRunner.

No system paths, shortcuts, KRunner providers or user's krunnerrc are modified.
Never run with sudo. All filesystem changes are confined to two user paths.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile

EXPECTED_PLASMA = "6.7.5"
ROOT = Path(__file__).resolve().parent.parent
DROPIN = "90-krunner-spotlight.conf"
UNIT = "plasma-krunner.service"
MARKER = "# Managed by KRunner Spotlight (tools/manage.py). Do not edit in place."
SERVICE_TEXT = (f"{MARKER}\n[Service]\nEnvironment=QML_DISABLE_DISK_CACHE=1\n"
                "ExecStart=\nExecStart=%h/.local/share/krunner-spotlight/bin/krunner-spotlight --daemon\n")

class InstallError(RuntimeError):
    pass


def paths():
    home = Path.home()
    storage = home / ".local/share/krunner-spotlight"
    return {
        "storage": storage,
        "binary": storage / "bin/krunner-spotlight",
        "previous": storage / "backups/previous-binary",
        "state": storage / "state.json",
        "service": home / ".config/systemd/user" / f"{UNIT}.d" / DROPIN,
    }


def run(*cmd, check=True):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=check)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def atomic_write(dest, data, mode=0o600):
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=dest.parent, prefix=f".{dest.name}.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, dest)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def read_state(p):
    if not p["state"].exists():
        return None
    s = json.loads(p["state"].read_text())
    if s.get("schema") != 1:
        raise InstallError("Unknown installer state schema; no changes made")
    return s


def service_status():
    try:
        result = run("systemctl", "--user", "cat", UNIT)
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        raise InstallError(f"Cannot inspect {UNIT} with user systemd: {e}") from e
    if "ExecStart=" not in result.stdout:
        raise InstallError(f"Unexpected {UNIT} definition (no ExecStart): refuse to override")
    # systemctl cat prints each unit/drop-in preceded by '# /absolute/path'.
    current_source = None
    foreign_exec = []
    user_unit_files = []
    for line in result.stdout.splitlines():
        if line.startswith("# /"):
            current_source = line[2:]
            if current_source.endswith("/" + UNIT) and not current_source.startswith((
                "/usr/lib/systemd/user/", "/lib/systemd/user/")):
                user_unit_files.append(current_source)
        elif line.strip().startswith("ExecStart=") and current_source and current_source.endswith(".conf"):
            if not current_source.endswith("/" + DROPIN):
                foreign_exec.append(current_source)
    conflicts = sorted(set(foreign_exec + user_unit_files))
    if conflicts:
        raise InstallError("Existing KRunner ExecStart override(s) or replacement user units "
                           "must be reviewed first: " + ", ".join(conflicts))


def check_host(require_supported=True):
    info = {"system": platform.system(), "architecture": platform.machine(),
            "session": os.environ.get("XDG_SESSION_TYPE", "unknown"),
            "plasma_version": None, "expected_plasma": EXPECTED_PLASMA}
    try:
        r = run("plasmashell", "--version")
        m = re.search(r"\b(\d+\.\d+\.\d+)\b", r.stdout + r.stderr)
        if m:
            info["plasma_version"] = m.group(1)
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass
    if require_supported:
        if info["system"] != "Linux":
            raise InstallError("Only Linux is supported")
        if info["plasma_version"] != EXPECTED_PLASMA:
            raise InstallError(f"This snapshot targets Plasma {EXPECTED_PLASMA}; found "
                               f"{info['plasma_version'] or 'unknown'}. Do not install across versions")
        if info["session"] not in ("wayland", "x11"):
            raise InstallError("Run from a Plasma Wayland/X11 desktop session (XDG_SESSION_TYPE)")
        service_status()
    return info


def build(args):
    check_host()
    for exe in ("cmake", "c++"):
        if not shutil.which(exe):
            raise InstallError(f"Missing {exe}; install Plasma 6.7.5 Qt/KF6 build dependencies")
    build_dir = ROOT / "build"
    commands = [("cmake", "-S", str(ROOT), "-B", str(build_dir), "-DCMAKE_BUILD_TYPE=Release"),
                ("cmake", "--build", str(build_dir), "--parallel", str(args.jobs))]
    for cmd in commands:
        print("+", " ".join(cmd), flush=True)
        subprocess.run(cmd, check=True)
    print("Built:", build_dir / "krunner-spotlight")


def ensure_eligible(p, state):
    service = p["service"]
    binary = p["binary"]
    if state is None and (service.exists() or binary.exists()):
        raise InstallError("Unmanaged Spotlight binary/drop-in already exists: do not overwrite it")
    if state:
        if not (service.exists() and binary.exists()):
            raise InstallError("Managed installation is incomplete; use documented manual recovery")
        if service.read_text() != SERVICE_TEXT:
            raise InstallError("Managed service drop-in has changed; refusing to clobber edits")
        if sha256(binary.read_bytes()) != state["current_sha256"]:
            raise InstallError("Installed binary changed externally; refusing to overwrite")


def install(args, updating=False):
    p = paths()
    check_host()
    current = read_state(p)
    if updating and current is None:
        raise InstallError("Not installed. Use install instead")
    if not updating and current is not None:
        raise InstallError("Already installed. Use update instead")
    ensure_eligible(p, current)
    candidate = Path(args.binary).resolve() if args.binary else ROOT / "build/krunner-spotlight"
    if not candidate.is_file():
        raise InstallError(f"Missing {candidate}; run build first")
    data = candidate.read_bytes()
    if data[:4] != b"\x7fELF":
        raise InstallError("Refusing non-ELF binary")
    elf_machine = int.from_bytes(data[18:20], "little")
    expected_machine = {"x86_64": 62, "aarch64": 183}.get(platform.machine())
    if expected_machine is None or elf_machine != expected_machine:
        raise InstallError("Binary architecture does not match this Linux machine")
    service = p["service"]
    # Preserve all managed files in memory for a best-effort transactional rollback.
    original = {k: path.read_bytes() if path.exists() else None for k, path in p.items()
                if k in ("binary", "service", "state", "previous")}
    try:
        if updating:
            atomic_write(p["previous"], original["binary"], 0o700)
        atomic_write(p["binary"], data, 0o700)
        atomic_write(service, SERVICE_TEXT.encode(), 0o644)
        new_state = {"schema": 1, "current_sha256": sha256(data),
                     "previous_sha256": sha256(original["binary"]) if updating else None,
                     "plasma_version": EXPECTED_PLASMA,
                     "architecture": platform.machine(),
                     "managed_service": str(service)}
        atomic_write(p["state"], (json.dumps(new_state, indent=2) + "\n").encode())
        run("systemctl", "--user", "daemon-reload")
        run("systemctl", "--user", "restart", UNIT)
    except Exception:
        for name in ("binary", "service", "state", "previous"):
            if original[name] is None:
                p[name].unlink(missing_ok=True)
            else:
                atomic_write(p[name], original[name], 0o700 if name in ("binary", "previous") else 0o600)
        run("systemctl", "--user", "daemon-reload", check=False)
        run("systemctl", "--user", "restart", UNIT, check=False)
        raise
    print("Installed custom KRunner in user home; stock /usr/bin/krunner untouched.")


def uninstall():
    p = paths()
    state = read_state(p)
    if state is None:
        print("No managed installation found. Nothing changed.")
        return
    ensure_eligible(p, state)
    old = {k: p[k].read_bytes() if p[k].exists() else None for k in ("binary", "service", "state", "previous")}
    try:
        p["service"].unlink()
        run("systemctl", "--user", "daemon-reload")
        run("systemctl", "--user", "restart", UNIT)
    except Exception:
        atomic_write(p["service"], old["service"], 0o644)
        run("systemctl", "--user", "daemon-reload", check=False)
        run("systemctl", "--user", "restart", UNIT, check=False)
        raise
    for name in ("binary", "previous", "state"):
        p[name].unlink(missing_ok=True)
    print("Custom drop-in removed and stock KRunner restarted. Other overrides/settings untouched.")


def rollback():
    p = paths()
    check_host()
    state = read_state(p)
    if not state or not state.get("previous_sha256"):
        raise InstallError("No previous managed version available for rollback")
    ensure_eligible(p, state)
    if not p["previous"].is_file():
        raise InstallError("Previous binary backup missing")
    previous = p["previous"].read_bytes()
    if sha256(previous) != state["previous_sha256"]:
        raise InstallError("Previous binary checksum does not match state")
    old = p["binary"].read_bytes()
    try:
        atomic_write(p["binary"], previous, 0o700)
        run("systemctl", "--user", "restart", UNIT)
    except Exception:
        atomic_write(p["binary"], old, 0o700)
        run("systemctl", "--user", "restart", UNIT, check=False)
        raise
    state.update(current_sha256=sha256(previous), previous_sha256=None)
    atomic_write(p["state"], (json.dumps(state, indent=2) + "\n").encode())
    p["previous"].unlink(missing_ok=True)
    print("Previous locally managed build restored.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    for name in ("check", "status", "uninstall", "rollback", "build", "install", "update"):
        cmd = sub.add_parser(name)
        if name == "build":
            cmd.add_argument("--jobs", type=int, default=2)
        if name in ("install", "update"):
            cmd.add_argument("--binary", help="Use a locally tested ELF build instead of build/krunner-spotlight")
    args = parser.parse_args()
    if os.geteuid() == 0:
        raise InstallError("Run unprivileged; never use sudo/root")
    if args.action == "check":
        print(json.dumps(check_host(require_supported=False), indent=2))
        check_host()
        print("Session/service compatible with this snapshot; build/runtime still require testing.")
    elif args.action == "status":
        p = paths()
        s = read_state(p)
        print(json.dumps({"managed": bool(s), "state": s,
                          "binary_exists": p["binary"].exists(),
                          "dropin_exists": p["service"].exists()}, indent=2))
    elif args.action == "build": build(args)
    elif args.action == "install": install(args)
    elif args.action == "update": install(args, updating=True)
    elif args.action == "uninstall": uninstall()
    elif args.action == "rollback": rollback()

if __name__ == "__main__":
    try:
        main()
    except (InstallError, OSError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
