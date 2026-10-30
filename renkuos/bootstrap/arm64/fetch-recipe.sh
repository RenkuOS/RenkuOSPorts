#!/bin/bash
# Usage: fetch-recipe.sh <recipe>...
# Pre-seeds <recipe dir>/download the way HaikuPorter expects (tarball plus
# .uri file), since the bootstrap guest has no wget and no TLS.
for recipe in "$@"; do
	dir=$(dirname "$recipe")
	base=$(basename "$recipe" .recipe)
	portVersion=${base##*-}
	vars=$(portVersion=$portVersion bash -c '
		secondaryArchSuffix= effectiveTargetArchitecture=arm64 targetArchitecture=arm64
		portVersionedName='"$base"' portName='"${base%-*}"'
		defineDebugInfoPackage() { :; }
		getPackagePrefix() { :; }
		. "'"$recipe"'" > /dev/null 2>&1
		for n in "" _2 _3 _4 _5 _6; do
			u=SOURCE_URI$n c=CHECKSUM_SHA256$n f=SOURCE_FILENAME$n
			[ -n "${!u}" ] && echo "${!u}|${!c}|${!f}"
		done')
	mkdir -p "$dir/download"
	while IFS="|" read -r uri sum name; do
		u=${uri%%#*}
		[ -n "$name" ] || name=${u##*/}
		out="$dir/download/$name"
		if [ ! -f "$out" ] || ! echo "$sum  $out" | sha256sum -c --quiet 2> /dev/null; then
			curl -fsSL --retry 3 -o "$out" "$u" || { echo "FAIL fetch $u"; continue; }
		fi
		if echo "$sum  $out" | sha256sum -c --quiet 2> /dev/null; then
			echo "$uri" > "$out.uri"
			echo "OK $base $name"
		else
			echo "FAIL checksum $base $name"
		fi
	done <<< "$vars"
done
