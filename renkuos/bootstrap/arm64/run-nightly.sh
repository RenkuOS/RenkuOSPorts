#!/bin/bash
# Usage: run-nightly.sh <nightly-ports.txt> <nightly-recipes.txt>
# Runs the arm64 nightly in the Phase 1 work image. If flex or mkdepend has not
# been built yet, a first pass builds just those two, because prepare-nightly.sh
# can only put them in the system packages once they exist. Then the image is
# prepared again and the full list runs. Takes the same environment as
# prepare-nightly.sh and phase1b-run.sh.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
R=${BUILD_ROOT:-$HOME/haiku-build}
OUT=$R/phase1-packages/bootstrap
ports=$(realpath "$1"); recipes=$(realpath "$2")
[ -f "$ports" ] && [ -f "$recipes" ] || { echo "usage: $0 <nightly-ports.txt> <nightly-recipes.txt>"; exit 1; }
# phase1b-run.sh logs "boot <n> end" when the boot script reached its end, and
# another result when it gave up.
ended() { grep "^boot " $R/phase1b.status 2> /dev/null | tail -1 | cut -d" " -f3; }

missing=
for p in flex mkdepend; do
	ls $OUT/$p-[0-9]*-arm64.hpkg > /dev/null 2>&1 || missing="$missing $p"
done
if [ -n "$missing" ]; then
	seed=$R/nightly-seed-ports.txt
	echo $missing | tr " " "\n" > $seed
	# All the sources, because flex brings in its own dependencies.
	$HERE/prepare-nightly.sh $seed "$recipes"
	$HERE/phase1b-run.sh
	[ "$(ended)" = end ] || { echo "the first pass did not finish"; exit 1; }
	for p in $missing; do
		ls $OUT/$p-[0-9]*-arm64.hpkg > /dev/null 2>&1 || { echo "the first pass did not build $p"; exit 1; }
	done
fi
$HERE/prepare-nightly.sh "$ports" "$recipes"
$HERE/phase1b-run.sh
