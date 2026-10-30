#!/bin/bash
# Usage: run-bench.sh <smp>...  Boots bench.image once per vCPU count and
# appends the BENCH markers to results.txt. Touches only its own QEMU, by PID.
# It can run beside phase1b-run.sh: it uses a copy of pristine.image.
HERE=$(cd "$(dirname "$0")" && pwd)
R=${BUILD_ROOT:-$HOME/haiku-build}
G=${GEN_DIR:-$R/wt-phase1/gen.arm64-bootstrap}
B=$R/vcpu-bench
export BFSQ_OUT=/tmp/bfsq-bench.out
mkdir -p $B
OFF=$((73728 * 512))
export LD_LIBRARY_PATH=$G/objects/linux/lib
cd $G
[ -e $B/bench.image ] || cp --sparse=always $G/phase1b/pristine.image $B/bench.image
for n in "$@"; do
	sed -e "s/HOST_EPOCH/$(date +%s)/" -e "s/NCPU/$n/" $HERE/UserBootscript.bench > $B/UserBootscript.now
	timeout 600 $HERE/bfsq.sh $B/bench.image $OFF "cp -f :$B/UserBootscript.now /myfs/home/config/settings/boot/UserBootscript" > /dev/null 2>&1
	cp /usr/share/AAVMF/AAVMF_VARS.fd $B/vars.fd
	rm -f $B/serial-$n.log
	t0=$(date +%s)
	qemu-system-aarch64 -M virt,gic-version=3 -cpu max -smp $n -m 3072 \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.fd \
		-drive if=pflash,format=raw,file=$B/vars.fd \
		-drive file=$B/bench.image,format=raw,if=none,id=d0 \
		-device ramfb -display none -nic none -serial file:$B/serial-$n.log \
		-device virtio-blk-device,drive=d0 > $B/qemu-$n.out 2>&1 < /dev/null &
	qpid=$!
	r=timeout
	for i in $(seq 360); do
		sleep 10
		grep -aq "BENCH end" $B/serial-$n.log && { r=ok; break; }
		kill -0 $qpid 2> /dev/null || { r=qemu-exited; break; }
	done
	kill $qpid 2> /dev/null; wait $qpid
	echo "smp $n $r boot-to-end $(( $(date +%s) - t0 )) $(grep -a "^BENCH" $B/serial-$n.log | grep -v hello | tr -d '\r' | tr '\n' ' ')" >> $B/results.txt
done
echo "DONE" >> $B/results.txt
