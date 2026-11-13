# Experimental Intel Gen9 graphics stack

This package set is for x86_64 RenkuOS and trusted graphics clients. The original
hardware tests used Haiku hrev60232 and Intel HD Graphics 515 (8086:191e).
The packaged standalone driver is a new build. It still needs a cold-boot test
on this hardware. Suspend, reset recovery and untrusted GPU command submission
are not supported. The driver license review remains open in RenkuOS PR #98.

## Install

Save all packages from the current graphics stack before you make changes.
Keep a bootable Haiku USB drive available. Install the driver in the HOME
package location. It has the same path as the system intel_extreme driver;
the home location supplies the override without changing the system package.

From the directory that contains the new hpkg files:

```
pkgman install -H ./intel_extreme_gen9-2026.10.16-2-x86_64.hpkg
pkgman install ./libglvnd-1.7.0-6-x86_64.hpkg ./mesa_iris-25.3.6-3-x86_64.hpkg
```

The Mesa package conflicts with the old Mesa renderer packages. Review the
transaction before accepting it. If an installed mesa_devel package prevents
the change, replace it with the matching libglvnd_devel package. Do not remove
unrelated applications to force the transaction through.

Existing non-packaged experimental files take precedence over packages.
Move these to a backup directory before you test the packaged stack:

- ~/config/non-packaged/add-ons/kernel/drivers/bin/intel_extreme
- /boot/system/non-packaged/add-ons/opengl/egl_vendor.d/libEGL_mesa.so*
- Any non-packaged copy of 50_mesa.json or libglvnd libraries from earlier tests.

Keep the paths and checksums with the backup. Do not delete a file unless you
know it belongs to an earlier experiment. Power the machine off fully, then
turn it on. A warm restart was not sufficient during the original driver tests.

## Check

```
intel-gen9-stress
intel-gen9-fbo-test
intel-gen9-texture-upload-test
intel-gen9-present-test
```

The stress test must pass 4096 submissions. The window checks must report no
pixel errors. Run the window checks in a graphical session. To compare the
software path, use LIBGL_ALWAYS_SOFTWARE=1 with the same application.

## Roll back

```
pkgman uninstall -H intel_extreme_gen9
pkgman uninstall mesa_iris
```

Restore the previous graphics packages from the saved hpkg files. Restore
only the non-packaged overrides you deliberately want to keep. Cold boot.
If the graphical session cannot start, use the boot loader safe mode or the
Haiku USB drive to move intel_extreme_gen9 out of ~/config/packages. The stock
system driver remains in its original Haiku package.

## Build

Use this HaikuPorts branch. Build libglvnd first, then intel_extreme_gen9 and
mesa_iris. ALLOW_UNTESTED must be yes. Keep the driver and source package with
the binaries. The recipes pin source archives and include every port patch,
the libdrm headers, and the pre-generated Intel shaders. They do not depend on
files from an agent's /tmp directory. The shader README describes regeneration.

Use a low compiler job count. Build outside the live machine when possible.
The kernel package requires exactly r1~beta6_hrev60072_580. Build and test the
driver again before changing this ABI pin for a new RenkuOS revision;
this port uses private kernel interfaces and does not promise a stable ABI.

## BGRA texture uploads (revision 2)

Revision 2 fixes a texture-map crash exposed by the Cryo Dune port. Iris now
updates valid_buffer_range only for buffer resources, whose range mutex is
initialized. Texture resources do not initialize that mutex.

Run `intel-gen9-texture-upload-test` after installation. It uploads BGRA data
to an RGBA texture 32 times and verifies the result with FBO readback. The
reported renderer must identify Intel for a hardware check. Use
`LIBGL_ALWAYS_SOFTWARE=1 intel-gen9-texture-upload-test` for the software check.
The old library aborts on the hardware test on HD 515.
