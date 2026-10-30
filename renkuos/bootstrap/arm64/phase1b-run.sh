#!/bin/bash
# Phase 1 bootstrap: boot work.image (a one-time copy of pristine.image) until the
# UserBootscript reports "PHASE1 end". A crashed or silent guest is rebooted on the
# same image, and --do-bootstrap resumes from the packages it already built.
# Only this script's own QEMU is touched (by PID).
# Environment: BUILD_ROOT, GEN_DIR, SMP (vCPUs, default 8), GUEST_MB, JOBS.
HERE=$(cd "$(dirname "$0")" && pwd)
R=${BUILD_ROOT:-$HOME/haiku-build}
G=${GEN_DIR:-$R/wt-phase1/gen.arm64-bootstrap}
D=$G/phase1b
S=$R/phase1b.status
OUT=$R/phase1-packages/bootstrap
OFF=$((73728 * 512))
export LD_LIBRARY_PATH=$G/objects/linux/lib
cd $G
mkdir -p $OUT
: > $S

export BFSQ_OUT=/tmp/bfsq-phase1b.out
bfsq() { timeout 600 $HERE/bfsq.sh $D/work.image $OFF "$@" > /dev/null 2>&1; }

# Copy packages the host does not have yet off the image (QEMU must be off).
harvest() {
	bfsq "ls /myfs/home/haikuports/packages"
	local cmds=()
	for p in $(grep -a -o "[^ ]*\.hpkg$" $BFSQ_OUT); do
		[ -e $OUT/$p ] || cmds+=("cp /myfs/home/haikuports/packages/$p :$OUT/$p")
	done
	cmds+=("cp /myfs/home/phase1.log :$OUT/phase1.log")
	[ ${#cmds[@]} -gt 0 ] && bfsq "${cmds[@]}"
	echo "harvest $(ls $OUT/*.hpkg 2> /dev/null | wc -l) packages on host" >> $S
}

[ -e $D/work.image ] || cp --sparse=always $D/pristine.image $D/work.image
for boot in $(seq 1 20); do
	sed -e "s/HOST_EPOCH/$(date +%s)/" -e "s/JOBS/${JOBS:-12}/" $D/UserBootscript > $D/UserBootscript.now
	bfsq "cp -f :$D/UserBootscript.now /myfs/home/config/settings/boot/UserBootscript"
	[ -f $D/serial.log ] && mv $D/serial.log $D/serial-prev.log
	cp /usr/share/AAVMF/AAVMF_VARS.fd $D/vars.fd
	qemu-system-aarch64 -M virt,gic-version=3 -cpu max -smp ${SMP:-8} -m ${GUEST_MB:-12288} \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.fd \
		-drive if=pflash,format=raw,file=$D/vars.fd \
		-drive file=$D/work.image,format=raw,if=none,id=d0 \
		-device ramfb -display none \
		-chardev socket,id=s0,path=$D/serial.sock,server=on,wait=off,logfile=$D/serial.log \
		-serial chardev:s0 -monitor unix:$D/mon.sock,server,nowait -netdev user,id=n0 \
		-device virtio-blk-device,drive=d0 -device virtio-net-device,netdev=n0 \
		-device qemu-xhci -device usb-kbd > $D/qemu.out 2>&1 < /dev/null &
	qpid=$!
	echo "boot $boot pid $qpid $(date +%F_%T)" >> $S
	last=-1; still=0; result=
	while sleep 120; do
		if grep -aq "PHASE1 end" $D/serial.log; then result=end; break; fi
		kill -0 $qpid 2> /dev/null || { result=qemu-exited; break; }
		size=$(wc -c < $D/serial.log)
		[ "$size" = "$last" ] && still=$((still + 1)) || { still=0; last=$size; }
		# A heartbeat comes every 10 minutes once the bootscript runs.
		if [ $still -ge 20 ]; then result=silent-40min; break; fi
	done
	echo "boot $boot $result $(date +%F_%T)" >> $S
	cp $D/serial.log $D/serial-boot$boot.log
	if kill -0 $qpid 2> /dev/null; then
		# The bootscript syncs after every port; an unclean stop costs at most
		# the port in progress.
		[ $result = end ] && sleep 60
		kill $qpid; wait $qpid
	fi
	harvest
	[ $result = end ] && break
done
echo "EXIT" >> $S
