#!/bin/bash
# Usage: fetch-repo.sh <served-dir>
# Runs on the server that hosts the arm64 package repository. It downloads
# renkuosports-arm64-repo.tar from the arm64-packages release when the release
# has a new one, checks it, and unpacks it. Run it from cron after the nightly
# build, which starts at 03:00 UTC; it does nothing when the release has not
# changed.
#
# <served-dir> is the path the web server serves at the repository's baseurl.
# The script makes it a symlink to <served-dir>.d/<checksum>, and switches the
# link in one step, so clients never see half a repository. It keeps the
# previous copy for clients still downloading from it, and deletes older ones.
#
# RELEASE_URL overrides where the files come from (default: the arm64-packages
# release of RenkuOS/RenkuOSPorts).
set -e
link=${1%/}
[ -n "$link" ] || { echo "usage: $0 <served-dir>"; exit 1; }
[ ! -e "$link" ] || [ -L "$link" ] ||
	{ echo "$link exists and is not a symlink: move it out of the way first"; exit 1; }
url=${RELEASE_URL:-https://github.com/RenkuOS/RenkuOSPorts/releases/download/arm64-packages}
tar=renkuosports-arm64-repo.tar
store=$link.d
# The link is relative, so the served tree can move.
rel=${store##*/}
mkdir -p "$store"
chmod a+rx "$store"
# A run that overlaps a slow one leaves the work to it.
exec 9> "$store/.lock"
flock -n 9 || exit 0

tmp=$(mktemp -d "$store/.fetch-XXXXXX")
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/$tar.sha256" "$url/$tar.sha256"
sum=$(cut -d" " -f1 "$tmp/$tar.sha256")
[[ $sum =~ ^[0-9a-f]{64}$ ]] || { echo "bad checksum file from $url"; exit 1; }
if [ "$(readlink "$link")" = "$rel/$sum" ] && [ -f "$store/$sum/repo" ]; then
	exit 0
fi

curl -fsSL -o "$tmp/$tar" "$url/$tar"
(cd "$tmp" && sha256sum -c --quiet "$tar.sha256")
mkdir "$tmp/repo"
tar -xf "$tmp/$tar" -C "$tmp/repo"
for f in repo repo.info repo.sha256 packages; do
	[ -e "$tmp/repo/$f" ] || { echo "$tar has no $f"; exit 1; }
done
# repo.sha256 is the checksum Haiku's package kit checks the repo file against.
[ "$(sha256sum "$tmp/repo/repo" | cut -d" " -f1)" = "$(cat "$tmp/repo/repo.sha256")" ] ||
	{ echo "repo does not match repo.sha256"; exit 1; }
chmod -R a+rX "$tmp/repo"
rm -rf "$store/$sum"
mv "$tmp/repo" "$store/$sum"

old=$(readlink "$link" || true)
ln -sfn "$rel/$sum" "$tmp/link"
mv -T "$tmp/link" "$link"
for d in "$store"/*; do
	[ "$d" = "$store/$sum" ] || [ "${d##*/}" = "${old##*/}" ] || rm -rf "$d"
done
echo "$link: $(ls "$store/$sum/packages" | wc -l) packages, $sum"
