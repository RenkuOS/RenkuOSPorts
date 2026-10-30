#!/bin/bash
# Usage: bfsq.sh <image> <offset> <fs_shell command>...  (one command per arg)
# Runs fs_shell commands against the BFS partition of a Haiku image. Run it from
# the generated build directory, with LD_LIBRARY_PATH=objects/linux/lib. The
# shell's output, including any ls listing, goes to $BFSQ_OUT.
T=objects/linux/x86_64/release/tools
img=$1; off=$2; shift 2
f=/tmp/bfsq-$$; mkfifo $f-to $f-from
sleep 3<$f-from 1 & exec 6>$f-from 3<$f-from
sleep 5<$f-to 1 & exec 4>$f-to 5<$f-to
rm -f $f-to $f-from
$T/bfs_shell/bfs_shell -n --start-offset $off $img 3>&5 4<&6 > ${BFSQ_OUT:-/tmp/bfsq-shell.out} 2>&1 &
for c in "$@"; do echo "## $c"; eval "$T/fs_shell/fs_shell_command 3<&3 4>&4 5>&- 6>&- $c"; done
$T/fs_shell/fs_shell_command 3<&3 4>&4 5>&- 6>&- sync
$T/fs_shell/fs_shell_command 3<&3 4>&4 5>&- 6>&- quit
wait
