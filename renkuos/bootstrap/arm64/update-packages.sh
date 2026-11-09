#!/bin/bash
# Usage: update-packages.sh [<port>...]
# Rebuilds the arm64 packages whose recipes changed on bootstrap/arm64 since the
# last successful run, the way HaikuPorter's buildmaster "update" does: it diffs
# the tree from the commit in $BUILD_ROOT/processed_rev, asks HaikuPorter which
# active ports the changed files belong to, and builds those in the guest. With
# ports on the command line, it builds those instead. processed_rev moves on
# only when every port built, so a failed port is tried again on the next run.
#
# Only ports we already build, or that the nightly list names, are rebuilt.
# Takes the environment of prepare-nightly.sh and phase1b-run.sh, plus:
#   HAIKUPORTER  haikuporter.py from a HaikuPorter checkout, run on this host
#                to map files to ports
#   LICENSES     a checkout of github.com/waddlesplash/haiku-licenses, which
#                HaikuPorter checks recipes against
#   PORTS_LIST   the nightly port list (default $BUILD_ROOT/phase2/nightly-ports.txt)
#   RECIPES_LIST the nightly recipe list (default .../phase2/nightly-recipes.txt)
#   SOURCE_PORTS ports to make source packages of (default: zlib zstd, which an
#                arm64 Haiku build unpacks for its zlib and zstd build features)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
R=${BUILD_ROOT:-$HOME/haiku-build}
OUT=$R/phase1-packages/bootstrap
TREE=${PORTS_TREE:?set PORTS_TREE to the RenkuOSPorts checkout}
PORTS_LIST=${PORTS_LIST:-$R/phase2/nightly-ports.txt}
RECIPES_LIST=${RECIPES_LIST:-$R/phase2/nightly-recipes.txt}
SOURCE_PORTS=${SOURCE_PORTS-zlib zstd}
W=$R/update
mkdir -p $W

git -C "$TREE" fetch -q origin bootstrap/arm64
new=$(git -C "$TREE" rev-parse FETCH_HEAD)
old=$(cat $R/processed_rev 2> /dev/null) ||
	{ echo "no $R/processed_rev: write the commit the packages were built from"; exit 1; }
git -C "$TREE" checkout -q --detach $new

# A source port gets a new source package when it is rebuilt or has none yet.
sources() {
	for p in $SOURCE_PORTS; do
		if grep -q -x -F $p $W/ports || ! ls $OUT/${p}_source-[0-9]*-source.hpkg > /dev/null 2>&1; then
			echo $p
		fi
	done > $W/sources
}

# Tell a GitHub workflow to publish. $R/unpublished stays until a publish
# succeeds, so packages that built in a run whose upload failed go out later.
built() { touch $R/unpublished; [ -z "$GITHUB_OUTPUT" ] || echo "built=yes" >> "$GITHUB_OUTPUT"; }
[ ! -e $R/unpublished ] || built

if [ $# -gt 0 ]; then
	printf '%s\n' "$@" > $W/ports
	sources
else
	[ $old = $new ] && { echo "no new commits on bootstrap/arm64"; exit 0; }
	# No ALLOW_UNTESTED, as in the guest: an untested newer recipe, such as gcc 15,
	# is not the active version there.
	cat > $W/haikuports.conf << EOF
TREE_PATH="$TREE"
PACKAGER="RenkuOS arm64 runner <noreply@renkuos.org>"
TARGET_ARCHITECTURE="arm64"
EOF
	hp() { (cd "$TREE" && python3 "${HAIKUPORTER:?set HAIKUPORTER}" --config=$W/haikuports.conf \
		--licenses="${LICENSES:?set LICENSES}" --no-package-obsoletion "$@"); }
	hp --repository-update --quiet > $W/repository-update.log 2>&1
	git -C "$TREE" diff-tree -r --name-only --diff-filter=ACMTR $old $new > $W/files
	# It prints each port as <name>-<version>, and versions have no "-".
	: > $W/versioned
	if [ -s $W/files ]; then
		hp --no-repository-update --ports-for-files --active-versions-only \
			$(cat $W/files) > $W/versioned 2> $W/ports-for-files.log
	fi
	sed 's/-[^-]*$//' $W/versioned | sort -u > $W/changed
	# Ours: a port with a package on the host, or one the nightly list names.
	ls $OUT | sed -E 's/-[^-]+-[^-]+-[^-]+\.hpkg$//' | sort -u | cat - "$PORTS_LIST" |
		sort -u | comm -12 - $W/changed > $W/ports
	echo "changed ports: $(wc -l < $W/changed), ours: $(wc -l < $W/ports)"
	sources
	if [ ! -s $W/ports ] && [ ! -s $W/sources ]; then
		echo $new > $R/processed_rev
		exit 0
	fi
fi
echo "building: $(tr '\n' ' ' < $W/ports)"
[ ! -s $W/sources ] || echo "source packages: $(tr '\n' ' ' < $W/sources)"

# The guest cannot download, so fetch the sources of every recipe of these
# ports, including one that a version bump has just added.
git -C "$TREE" ls-files '*.recipe' | awk -F/ 'NR == FNR { p[$1]; next }
	{ n = $NF; sub(/-[^-]*\.recipe$/, "", n) } n in p' <(cat $W/ports $W/sources) - |
	cat - "$RECIPES_LIST" | sort -u > $W/recipes
PORTS_REF=$new REBUILD=1 SOURCES_LIST=$W/sources $HERE/prepare-nightly.sh $W/ports $W/recipes
$HERE/phase1b-run.sh
ended=$(grep "^boot " $R/phase1b.status | tail -1 | cut -d" " -f3)
[ "$ended" = end ] || { echo "the guest did not finish: $ended"; exit 1; }

# The boot script lists every port whose marker shows two failed tries. It also
# ends early, without that list, when it cannot set up the tree or HaikuPorter.
serial=$(ls -t ${GEN_DIR:-$R/wt-phase1/gen.arm64-bootstrap}/phase1b/serial-boot*.log | head -1)
line=$(grep -a "PHASE1 failed:" $serial | tail -1 | tr -d '\r')
[ -n "$line" ] || { echo "the guest built nothing: $(grep -a "PHASE1" $serial | tail -2 | head -1 | tr -d '\r')"; exit 1; }
# Publish what built, even if some ports failed.
built
# Count only the ports this run built.
failed=$(echo "${line#*failed:}" | tr ' ' '\n' |
	grep -x -F -f <(cat $W/ports; sed 's/$/_source/' $W/sources) | tr '\n' ' ')
if [ -n "$failed" ]; then
	echo "failed: $failed"
	exit 1
fi
[ $# -gt 0 ] || echo $new > $R/processed_rev
echo "all built"
