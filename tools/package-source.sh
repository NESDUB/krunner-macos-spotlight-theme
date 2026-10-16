#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
cd "$(dirname "$0")/.."
repo="$PWD"
name=krunner-macos-spotlight-0.1.0
out="${1:-$repo/dist}"
mkdir -p "$out"
# Reproducible tarball on GNU tar (used on supported Fedora).
# Use a stable timestamp unless SOURCE_DATE_EPOCH is explicitly provided.
epoch="${SOURCE_DATE_EPOCH:-1792108800}"
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
  --exclude=build --exclude=dist --exclude='.git' \
  --exclude='__pycache__' --exclude='*.pyc' \
  --transform="s,^,$name/," -cf - \
  CMakeLists.txt main.cpp view.cpp view.h \
  x11windowscreenrelativepositioner.cpp x11windowscreenrelativepositioner.h \
  dbus qml tools tests docs LICENSES .github .gitignore \
  README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md \
  | gzip -n > "$out/$name.tar.gz"
( cd "$out" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256" )
printf 'Created %s/%s.tar.gz\n' "$out" "$name"
