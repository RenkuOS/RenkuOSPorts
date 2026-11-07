#!/bin/bash
# Usage: prepare-nightly.sh <nightly-ports.txt> <nightly-recipes.txt>
# Readies the Phase 1 work image for UserBootscript.nightly, with QEMU off. It
# writes the recipe tree, the port list, and every source into /boot/home, makes
# the system package changes the nightly ports need, and installs the nightly
# boot script. Ports that already built stay built. Run it again after changing
# the recipes or the port list, then start phase1b-run.sh as usual.
#
# PORTS_TREE is the RenkuOSPorts checkout to read recipes from (default: this
# one) and PORTS_REF the commit to pack (default: bootstrap/arm64).
# MAKEFILE_ENGINE is a makefile_engine-*-any.hpkg from any Haiku build.
# HAIKU_GEN, if set, is the generated directory of a regular (not
# @bootstrap-raw) arm64 build where `jam haiku.hpkg haiku_devel.hpkg` has run.
# ANY_PACKAGES is a directory of *-any.hpkg files, such as the download
# directory of an x86_64 build, for the packages the regular haiku requires that
# no arm64 build makes.
# REBUILD=1 builds every port in the list again, for a changed recipe: it
# clears the port's marker and moves its main package out of HaikuPorter's
# packages directory. Bump the recipe's REVISION, because the host keeps the
# first copy of each package file name.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
R=${BUILD_ROOT:-$HOME/haiku-build}
G=${GEN_DIR:-$R/wt-phase1/gen.arm64-bootstrap}
D=$G/phase1b
OUT=$R/phase1-packages/bootstrap
OFF=$((73728 * 512))
TREE=${PORTS_TREE:-$(cd "$HERE/../../.." && pwd)}
REF=${PORTS_REF:-bootstrap/arm64}
W=$R/nightly-prep
ports=$(realpath "$1"); recipes=$(realpath "$2")
[ -f "$ports" ] && [ -f "$recipes" ] || { echo "usage: $0 <nightly-ports.txt> <nightly-recipes.txt>"; exit 1; }
[ -f "$MAKEFILE_ENGINE" ] || { echo "set MAKEFILE_ENGINE to a makefile_engine-*-any.hpkg"; exit 1; }
pgrep -f "qemu-system-aarch64.*$D/" > /dev/null && { echo "QEMU is still running on $D"; exit 1; }

export LD_LIBRARY_PATH=$G/objects/linux/lib
PACKAGE=$G/objects/linux/x86_64/release/tools/package/package
export BFSQ_OUT=$W/bfsq.out
bfsq() { (cd $G && timeout 1800 $HERE/bfsq.sh $D/work.image $OFF "$@" > /dev/null 2>&1); }
newest() { ls $OUT/$1-[0-9]*-arm64.hpkg 2> /dev/null | sort -V | tail -1; }
rm -rf $W; mkdir -p $W

# HaikuPorter takes build tools from the system packages. The bootstrap flex is
# too old for doxygen, and the bootstrap bison's --version fails, so the real
# ones replace them once they are built: bison in Phase 1, and flex in the first
# nightly pass (see run-nightly.sh). mkdepend is what makefile_engine needs.
real=
for p in flex bison mkdepend; do
	[ -n "$(newest $p)" ] && real="$real $p"
done

# makefile_engine comes from Haiku's own build, which the bootstrap image leaves
# out. Recompress it with zlib, because the arm64 bootstrap package tool cannot
# read zstd and HaikuPorter would skip the package without saying why.
me=$W/$(basename "$MAKEFILE_ENGINE")
$PACKAGE recompress -q -z zlib "$MAKEFILE_ENGINE" "$me"

# The regular haiku package has the libraries the bootstrap one leaves out, such
# as libmail, libmedia, and libgame. Its kernel needs the EFI loader from the
# same build, because the loader and kernel share the kernel_args layout.
haiku= extra=
if [ -n "$HAIKU_GEN" ]; then
	hp=$HAIKU_GEN/objects/haiku/arm64/packaging/packages
	loader=$HAIKU_GEN/objects/haiku/arm64/release/system/boot/efi/haiku_loader.efi
	for f in $hp/haiku.hpkg $hp/haiku_devel.hpkg $loader; do
		[ -f $f ] || { echo "missing $f"; exit 1; }
	done
	haiku=$($PACKAGE list -i $hp/haiku.hpkg | sed -n "s/^\tversion: //p")
	[ -n "$haiku" ] || { echo "cannot read the version of $hp/haiku.hpkg"; exit 1; }
	for p in haiku haiku_devel; do cp $hp/$p.hpkg $W/$p-$haiku-arm64.hpkg; done
	esp=$(sfdisk -d $D/work.image | sed -n "s/.*start= *\([0-9]*\),.*type=ef.*/\1/p")
	[ -n "$esp" ] || { echo "no EFI system partition in $D/work.image"; exit 1; }

	# The regular haiku also requires fonts and wifi firmware that HaikuPorter
	# cannot resolve unless they are system packages. Haiku's build makes some,
	# such as mediatek_wifi_firmwares, and ANY_PACKAGES has the rest.
	for n in $($PACKAGE list -i $hp/haiku.hpkg | sed -n "s/^\trequires: \([a-z0-9_]*\)\([<>=].*\)\?$/\1/p"); do
		ls $OUT/$n-[0-9]*.hpkg > /dev/null 2>&1 && continue
		f=$hp/$n.hpkg
		[ -f $f ] || f=$(ls ${ANY_PACKAGES:-/nonexistent}/$n-[0-9]*-any.hpkg 2> /dev/null | sort -V | tail -1)
		[ -f "$f" ] || { echo "haiku requires $n: build it, or put it in ANY_PACKAGES"; exit 1; }
		v=$($PACKAGE list -i $f | sed -n "s/^\tversion: //p")
		$PACKAGE recompress -q -z zlib $f $W/$n-$v-any.hpkg
		extra="$extra $W/$n-$v-any.hpkg"
	done
fi

# fetch-recipe.sh skips files that are already there with the right checksum.
(cd "$TREE" && git diff --quiet "$REF" -- $(cat "$recipes")) ||
	echo "warning: the checkout differs from $REF in some recipes; sources follow the checkout"
(cd "$TREE" && xargs -a "$recipes" $HERE/fetch-recipe.sh)
(cd "$TREE" && tar -cf $W/nightly-downloads.tar $(for r in $(cat "$recipes"); do
	d=$(dirname $r)/download; [ -d $d ] && echo $d; done))
printf 'default_action kill\n' > $W/debug_server.settings
: > $W/locale.settings

SP=/myfs/system/packages H=/myfs/home
bfsq "ls $SP" "ls $H/config/settings"
# Keep the home listings apart: HaikuPorter's packages directory has the same
# file names as the packages checked for in /system/packages below.
HOME_OUT=$W/bfsq-home.out
BFSQ_OUT=$HOME_OUT bfsq "ls $H" "ls $H/haikuports/packages"

# The guest keeps the tree between runs and names the commit it is at in
# nightly-tree.<commit>. Send only the files that changed since then, because
# HaikuPorter parses every recipe that is newer than its dependency info again,
# and parsing all of them takes four hours in the emulated guest.
sha=$(git -C "$TREE" rev-parse "$REF^{commit}")
base=$(grep -a -o " nightly-tree\.[0-9a-f]\{40\}$" $HOME_OUT | head -1 | cut -d. -f2)
if [ -n "$base" ] && git -C "$TREE" cat-file -e "$base^{commit}" 2> /dev/null; then
	mapfile -d '' -t changed < <(git -C "$TREE" diff -z --no-renames --name-only \
		--diff-filter=d $base $sha -- . ':!renkuos')
	git -C "$TREE" diff -z --no-renames --name-only --diff-filter=D $base $sha -- . ':!renkuos' |
		tr '\0' '\n' > $W/renkuosports.removed
	if [ ${#changed[@]} -gt 0 ]; then
		git -C "$TREE" archive --format=tar -o $W/renkuosports.tar $sha -- "${changed[@]/#/:(literal)}"
	else
		tar -cf $W/renkuosports.tar -T /dev/null
	fi
	echo "tree: ${#changed[@]} files changed and $(wc -l < $W/renkuosports.removed) removed since ${base:0:9}"
else
	base=
	git -C "$TREE" archive --format=tar -o $W/renkuosports.tar $sha -- . ':!renkuos'
fi
echo $sha > $W/nightly-tree.next

cmds=("mkdir $H/removed-bootstrap")
for p in $real; do
	for f in $(grep -a -o "${p}_bootstrap-[^ ]*\.hpkg" $BFSQ_OUT); do
		cmds+=("cp $SP/$f $H/removed-bootstrap/$f" "rm $SP/$f")
	done
	f=$(newest $p)
	grep -a -q " ${f##*/}$" $BFSQ_OUT || cmds+=("cp :$f $SP/${f##*/}")
done
grep -a -q " ${me##*/}$" $BFSQ_OUT || cmds+=("cp :$me $SP/${me##*/}")
for p in ${haiku:+haiku haiku_devel}; do
	new=$p-$haiku-arm64.hpkg
	for f in $(grep -a -o " $p-r[^ ]*\.hpkg" $BFSQ_OUT); do
		[ $f = $new ] || cmds+=("cp $SP/$f $H/removed-bootstrap/$f" "rm $SP/$f")
	done
	grep -a -q " $new$" $BFSQ_OUT || cmds+=("cp :$W/$new $SP/$new")
done
for f in $extra; do
	grep -a -q " ${f##*/}$" $BFSQ_OUT || cmds+=("cp :$f $SP/${f##*/}")
done
# The regular haiku has FirstBootPrompt, and the launch_daemon starts it instead
# of the desktop, and so instead of the boot script, until the user has locale
# settings. An empty file is enough: the Locale Kit then uses en_US.
[ -n "$haiku" ] && ! grep -a -q " Locale settings$" $BFSQ_OUT &&
	cmds+=("cp :$W/locale.settings '$H/config/settings/Locale settings'")
if [ -n "$REBUILD" ]; then
	cmds+=("mkdir $H/removed-old")
	for p in $(cat "$ports"); do
		cmds+=("rm $H/nightly/$p")
		for f in $(awk -v d="$H/haikuports/packages:" '$0 == d { f = 1; next }
				/^\/myfs.*:$/ { f = 0 } f { print $NF }' $HOME_OUT | grep "^$p-[0-9].*\.hpkg$"); do
			cmds+=("cp $H/haikuports/packages/$f $H/removed-old/$f" "rm $H/haikuports/packages/$f")
		done
	done
fi
cmds+=("mkdir $H/config/settings/system/debug_server"
	"rm $H/config/settings/system/debug_server/settings"
	"cp :$W/debug_server.settings $H/config/settings/system/debug_server/settings"
	"rm $H/renkuosports.tar" "cp :$W/renkuosports.tar $H/renkuosports.tar"
	"rm $H/renkuosports.removed" "rm $H/nightly-tree.next" "cp :$W/nightly-tree.next $H/nightly-tree.next"
	"rm $H/nightly-ports.txt" "cp :$ports $H/nightly-ports.txt"
	"rm $H/nightly-downloads.tar" "cp :$W/nightly-downloads.tar $H/nightly-downloads.tar"
	"rm $H/nightly.tree" "rm $H/nightly.done")
[ -f $W/renkuosports.removed ] &&
	cmds+=("cp :$W/renkuosports.removed $H/renkuosports.removed")
bfsq "${cmds[@]}"

if [ -n "$haiku" ]; then
	mcopy -o -i "$D/work.image@@$((esp * 512))" $loader ::EFI/BOOT/BOOTAA64.EFI
	[ "$(mdir -i "$D/work.image@@$((esp * 512))" ::EFI/BOOT/BOOTAA64.EFI | awk '$1 == "BOOTAA64" { print $3 }')" = \
		"$(stat -c %s $loader)" ] || { echo "the EFI loader was not replaced"; exit 1; }
fi

# Check the result rather than trusting fs_shell's exit status.
bfsq "ls $SP" "ls $H" "ls $H/config/settings" "ls $H/config/settings/system/debug_server"
bad=
for f in $(for p in $real; do newest $p; done) $me $extra ${haiku:+$W/haiku-$haiku-arm64.hpkg $W/haiku_devel-$haiku-arm64.hpkg}; do
	grep -a -q " ${f##*/}$" $BFSQ_OUT || { echo "missing in image: ${f##*/}"; bad=1; }
done
for p in ${haiku:+haiku haiku_devel}; do
	[ $(grep -a -c " $p-r[^ ]*\.hpkg$" $BFSQ_OUT) = 1 ] || { echo "more than one $p package installed"; bad=1; }
done
for p in $real; do
	grep -a -q "${p}_bootstrap-" $BFSQ_OUT && { echo "${p}_bootstrap is still installed"; bad=1; }
done
for f in renkuosports.tar nightly-tree.next ${base:+renkuosports.removed} nightly-ports.txt \
		nightly-downloads.tar settings ${haiku:+"Locale settings"}; do
	grep -a -q " $f$" $BFSQ_OUT || { echo "missing in image: $f"; bad=1; }
done
[ -z "$bad" ] || exit 1
cp $HERE/UserBootscript.nightly $D/UserBootscript
echo "image ready, with real:$real${haiku:+, haiku $haiku}; start phase1b-run.sh"
