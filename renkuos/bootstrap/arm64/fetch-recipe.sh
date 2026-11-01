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
			# A list of mirrors spans several lines, so put it on one.
			[ -n "${!u}" ] && echo "$(echo ${!u})|${!c}|${!f}"
		done')
	mkdir -p "$dir/download"
	while IFS="|" read -r uris sum name; do
		ok=
		for uri in $uris; do
			u=${uri%%#*}
			[ -n "$name" ] || name=${u##*/}
			out="$dir/download/$name"
			if [ ! -f "$out" ] || ! echo "$sum  $out" | sha256sum -c --quiet 2> /dev/null; then
				curl -fsSL --retry 3 -o "$out" "$u" || { echo "FAIL fetch $u"; continue; }
			fi
			if echo "$sum  $out" | sha256sum -c --quiet 2> /dev/null; then
				# HaikuPorter skips the download only if this matches a recipe URI.
				echo "$uri" > "$out.uri"
				echo "OK $base $name"
				ok=1
				break
			fi
			echo "FAIL checksum $base $name from $u"
		done
		[ -n "$ok" ] || echo "FAIL $base $name"
	done <<< "$vars"
done
