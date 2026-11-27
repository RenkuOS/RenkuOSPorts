#!/bin/bash
# Usage: publish-repo.sh <out-dir>
# Builds a package repository from the newest version of each package in
# $BUILD_ROOT/phase1-packages/bootstrap and writes two archives to <out-dir>:
#   renkuosports-arm64-repo.tar       repo, repo.info, repo.sha256, packages/
#   renkuosports-arm64-debuginfo.tar  the _debuginfo packages, which images
#                                     do not need
# with a .sha256 file for each. A GitHub release file can hold at most 2 GiB,
# and the two halves are about 0.7 GB each today.
#
# PACKAGE_REPO is Haiku's package_repo host tool, from any Haiku build
# (objects/linux/x86_64/release/tools/package_repo/package_repo), with its
# objects/linux/lib in LD_LIBRARY_PATH. REPO_BASEURL is where the unpacked
# repository will be served.
set -e
R=${BUILD_ROOT:-$HOME/haiku-build}
OUT=$R/phase1-packages/bootstrap
dest=$1
[ -n "$dest" ] || { echo "usage: $0 <out-dir>"; exit 1; }
[ -x "$PACKAGE_REPO" ] || { echo "set PACKAGE_REPO to the package_repo host tool"; exit 1; }
[ -n "$REPO_BASEURL" ] || { echo "set REPO_BASEURL"; exit 1; }
W=$R/publish
rm -rf $W; mkdir -p $W/repo/packages $W/debuginfo $dest

# Package files are <name>-<version>-<revision>-<arch>.hpkg, and neither the
# version nor the name contains a "-". Keep the newest version of each name.
for f in $(ls $OUT/*.hpkg | sort -V); do
	b=${f##*/}
	echo "${b%-*-*-*.hpkg} $f"
done | awk '{ newest[$1] = $2 } END { for (n in newest) print newest[n] }' | sort > $W/files
while read f; do
	case $f in
	*_debuginfo-*) ln $f $W/debuginfo/ 2> /dev/null || cp $f $W/debuginfo/ ;;
	*) ln $f $W/repo/packages/ 2> /dev/null || cp $f $W/repo/packages/ ;;
	esac
done < $W/files

# package_repo requires every package's vendor to match the repository's, and
# HaikuPorter writes "Haiku Project".
cat > $W/repo/repo.info << EOF
name RenkuOSPorts
vendor "Haiku Project"
summary "RenkuOSPorts packages for arm64"
priority 1
baseurl $REPO_BASEURL
identifier tag:renkuos.org,2026:repositories/renkuosports/arm64
architecture arm64
EOF
(cd $W/repo && "$PACKAGE_REPO" create -q repo.info packages/*.hpkg)
(cd $W/repo && sha256sum repo | cut -d" " -f1 > repo.sha256)

tar -cf $dest/renkuosports-arm64-repo.tar -C $W/repo repo repo.info repo.sha256 packages
tar -cf $dest/renkuosports-arm64-debuginfo.tar -C $W debuginfo
(cd $dest && for t in renkuosports-arm64-repo.tar renkuosports-arm64-debuginfo.tar; do
	sha256sum $t > $t.sha256
done)
echo "repository: $(ls $W/repo/packages | wc -l) packages, debuginfo: $(ls $W/debuginfo | wc -l)"
ls -l $dest
