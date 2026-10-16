# Reproducible local build and dependency policy

The upstream fork snapshot is built with CMake from this repository. It links
against locally installed KDE Plasma 6.7.5, KF6 and Qt 6 libraries. It is **not**
a portable binary or generic KRunner skin. The project version `6.7.5` is the
upstream compatibility target, **not** a promise that different Plasma versions
work. This optical refinement passed a native release build and live KDE visual
checks on Fedora Asahi ARM64; all 16 automated tests passed. Installation,
update, rollback and uninstall were also exercised with the actual user service.
See [validation details](VALIDATION.md).

For Fedora Asahi Remix 44, consult the matching Fedora package manager for the
`*-devel` modules listed in the root `CMakeLists.txt` rather than copying an
untested package-install command. The original known-working host had:

- Fedora Asahi Remix 44 / aarch64 / Wayland
- Plasma Workspace 6.7.5; `plasma-milou` 6.7.5
- Qt 6.11.2; KF6 6.31; Kirigami 6.31
- LayerShellQt 6.7.5
- GCC 16.2.1 and CMake 4.3.0

For Fedora 44 with matching package repositories, the development packages below
were present on the tested host. Installing dependencies requires administrator
access; building and installing the launcher itself must run as your normal user.

```bash
sudo dnf install cmake gcc-c++ extra-cmake-modules \
  qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qttools-devel \
  kf6-kio-devel kf6-ki18n-devel kf6-kdbusaddons-devel kf6-kcrash-devel \
  kf6-krunner-devel kf6-kwindowsystem-devel kf6-kconfig-devel kf6-kservice-devel \
  libplasma-devel plasma-activities-devel plasma-workspace-devel \
  layer-shell-qt-devel kf6-kirigami plasma-milou
```

Check your own versions:

```bash
plasmashell --version
uname -m
printf '%s\n' "$XDG_SESSION_TYPE"
python3 tools/manage.py check
```

Build explicitly, without installing:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel 2
```

Optional developer-only diagnostic binary (not a public release binary):

```bash
cmake -S . -B build-debug -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DKRUNNER_SPOTLIGHT_DEVELOPER_PREVIEW=ON
cmake --build build-debug --parallel 2
```

The normal build excludes capture/event-injection diagnostics at compile time.
`KRUNNER_SPOTLIGHT_PREVIEW` and related environment variables only work with
that optional diagnostic build. Captures must be reviewed for personal data.

Then validate the local executable on the target (run as a normal user, never
with root access). Do not start a second KRunner service while the live one is
running. A properly isolated test user/session or a temporary manual restart
can be used for integration QA. Systemd integration is described in the README.

Only the user's binary and owned unit drop-in are installed; CMake has no
system-wide `install` target. The source archive carries no prebuilt ELF.

The `tools/package-source.sh` script makes a source tarball plus SHA-256 file.
This is **not** a signed or runtime-validated release. CI runs static checks and
manager unit tests; GUI, ABI, renderer and packaging QA require desktop runners.
