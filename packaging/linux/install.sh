#!/bin/sh
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Lays this extracted bundle out as the per-user install that can update itself
# (docs/decisions/0041): ~/.local/share/slim-m/<version>/, a `current` symlink,
# and a slim-m launcher on ~/.local/bin. Touches nothing outside the home directory.
set -eu

here=$(dirname "$(readlink -f "$0")")
version=$(basename "$here" | sed -n 's/^slim-m-client-\([0-9][0-9.]*\)$/\1/p')
if [ -z "$version" ]; then
  echo "run this from the extracted slim-m-client-<version> directory" >&2
  exit 1
fi

root="${XDG_DATA_HOME:-$HOME/.local/share}/slim-m"
bin="${HOME}/.local/bin"
mkdir -p "$root" "$bin"

rm -rf "$root/.unpack-$version"
cp -a "$here" "$root/.unpack-$version"
rm -rf "${root:?}/$version"
mv "$root/.unpack-$version" "$root/$version"

ln -sfn "$version" "$root/.current.new"
mv -T "$root/.current.new" "$root/current"
ln -sfn "$root/current/slim-m" "$bin/slim-m"

echo "installed slim-m $version in $root; start it with $bin/slim-m"
