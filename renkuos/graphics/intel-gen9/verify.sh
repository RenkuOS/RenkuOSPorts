#!/bin/bash
# SPDX-License-Identifier: MIT
# Verify the installed Mi Air graphics stack; run in a graphical session.
set -euo pipefail

mode="${1:-hardware}"
if [[ $# -gt 1 || ( "$mode" != hardware && "$mode" != --software ) ]]; then
	printf 'Usage: bash %s [--software]\n' "$0" >&2
	exit 2
fi
if [[ $(uname -s) != Haiku || $(uname -m) != x86_64 ]]; then
	printf 'This check requires x86_64 RenkuOS/Haiku.\n' >&2
	exit 1
fi

# Exercise the normal loader search and the renderer selected by this check.
unset LIBRARY_PATH LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE
unset __EGL_VENDOR_LIBRARY_FILENAMES __EGL_VENDOR_LIBRARY_DIRS
unset EGL_HAIKU_TEST_RESIZE EGL_HAIKU_WINONLY EGL_HAIKU_NOFLIP
unset EGL_HAIKU_CLEARONLY EGL_HAIKU_SKIP_READ EGL_HAIKU_SKIP_FINISH
if [[ $mode == --software ]]; then
	export LIBGL_ALWAYS_SOFTWARE=1
	expected=llvmpipe
else
	expected='Mesa Intel(R) HD Graphics 515'
fi

logs=$(mktemp -d "$HOME/intel-gen9-check-XXXXXX")
printf 'Logs: %s\n' "$logs"
uname -a > "$logs/system.txt"
listimage > "$logs/loaded-images.txt"

if [[ $mode == hardware ]]; then
	intel-gen9-stress 4096 > "$logs/stress.txt" 2>&1
	cat "$logs/stress.txt"
	grep -qx PASS "$logs/stress.txt"
fi

for test in intel-gen9-fbo-test intel-gen9-texture-upload-test intel-gen9-present-test; do
	if ! "$test" > "$logs/$test.txt" 2>&1; then
		cat "$logs/$test.txt"
		exit 1
	fi
	cat "$logs/$test.txt"
	grep -F 'renderer=' "$logs/$test.txt" | grep -F "$expected"
	case "$test" in
		intel-gen9-fbo-test) grep -qx 'PASS failures=0' "$logs/$test.txt" ;;
		intel-gen9-texture-upload-test)
			grep -qx 'PASS: 32 texture uploads with two live contexts' "$logs/$test.txt" ;;
		intel-gen9-present-test)
			grep -qx 'PASS: 300 frame present, 0 mismatches; swaps=300 bitmaps=300' "$logs/$test.txt" ;;
	esac
done
printf 'PASS: %s pixel checks. Package/binary identity still needs the manual audit.\n' "$mode"
