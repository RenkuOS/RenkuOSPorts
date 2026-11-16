# Intel HD 515 acceleration on RenkuOS

This is an experimental, complete package set for the Xiaomi Mi Air 12.5:
Intel HD Graphics 515, PCI `8086:191e`, x86_64. It is for trusted graphics
clients. It does not provide GPU command isolation, reset recovery,
suspend/resume, Vulkan, or hardware video decoding.

## Components

| Port | Purpose |
|---|---|
| `intel_extreme_gen9` | Display driver and private Gen9 render node; installs the 4096-submission test. |
| `libglvnd` | Haiku OpenGL kit and EGL/GL dispatch. Required for `BGLView` and GLTeapot to reach the vendor. |
| `mesa_iris` | Mesa 25.3.6 iris, llvmpipe fallback, Haiku EGL window/pbuffer support, libdrm shim, and pixel tests. |
| `llvm21_libs` | LLVM runtime for this Mesa build; built by the existing LLVM 21 port. |

GLTeapot also needs the existing `glu` package. Development uses
`libglvnd_devel`. All source inputs of the three changed ports are either
in this tree or fetched from the checksummed source archives in the recipes.
No private build directory, draft release, prebuilt kernel, or local library
override is a source input.

The driver recipe fetches the complete source import from
RenkuOS/Source#98, pinned to commit
`544c5b738194a5b228e8a7951fcdba8af50f87d6`. This does not require that PR to
merge first. Its source and license notices are retained. Mesa includes
the required pre-generated Intel shader inputs; their source and generation
procedure are in `sys-libs/mesa_iris/additional-files/README.shaders.md`.

The Mesa changes include independent render/compute contexts, window
presentation/readback fixes, and the buffer-only valid-range update that
fixes BGRA texture uploads used by the Cryo Dune port.
The follow-up lifetime patch closes the caller's render descriptor, avoids
publishing partial EGL display state, and handles frontend allocation failure.
Those additional lifetime changes have patch-application validation only;
they are not part of the installed vendor used for the hardware results.

## Build on RenkuOS

Configure HaikuPorter to use this checkout as `TREE_PATH`, set your
`PACKAGER`, and set `ALLOW_UNTESTED="yes"`. Build natively on x86_64 RenkuOS
with matching `haiku` and `haiku_devel` packages. Install HaikuPorter's normal
build prerequisites and use its dependency resolver for the other tools.

The driver recipe deliberately requires **exactly**
`r1~beta6_hrev60072_580` for both `haiku` and `haiku_devel` (build00074).
It uses private kernel interfaces. Do not loosen this requirement merely to
make a package install on a different build. Rebuild and cold-boot test it
against that build first. User-space recipes use `haiku`; HaikuPorter adds
the build SDK's version requirement when it creates the binary packages.
Rebuild them on RenkuOS rather than editing an old hpkg's metadata.

Build in this order:

```sh
haikuporter libglvnd
haikuporter intel_extreme_gen9
haikuporter mesa_iris
```

Use a low job count for Mesa on this 4 GB laptop, or use a separate native
RenkuOS build machine. A full build of these revised recipes on RenkuOS is
still pending; the hardware results below are for the identified existing
binaries, not for newly built packages.

## Install and migrate from the prototype

Save the current package files and a checksum/path list of your overrides.
Keep a bootable USB available for rollback. Close GL applications. Existing
non-packaged libraries and drivers take precedence over installed packages.
Move only identified prototype files to a backup outside the searched paths:

- `~/config/non-packaged/add-ons/kernel/drivers/bin/intel_extreme` and any
  corresponding driver symlink override.
- `libGL`, `libEGL`, `libGLdispatch`, `libOpenGL`, and GLES libraries/symlinks
  in the system or user non-packaged `lib` directories.
- The prototype `add-ons/opengl/egl_vendor.d/50_mesa.json` and
  `libEGL_mesa.so*` files in the system or user non-packaged directories.

Do not move the I2C, touchpad, webcam, or Bluetooth overrides as part of this
graphics change. Preserve the system's packaged `intel_extreme` driver.

After the native build, from HaikuPorter's `packages` directory:

```sh
pkgman install -H ./intel_extreme_gen9-2026.10.16-2-x86_64.hpkg
pkgman install ./libglvnd-1.7.0-6-x86_64.hpkg ./mesa_iris-25.3.6-3-x86_64.hpkg
```

Install `llvm21_libs` from the configured package repository or the matching
locally built package if the resolver cannot find it. If `mesa_devel` is
installed, include the newly built `libglvnd_devel` in the same user-space
transaction. The recipes declare conflicts with the old Mesa stack: do not
co-install two providers of the same dispatch paths. Inspect all removals;
stop if the solver requires removal of unrelated applications.

Power off completely and power on to load the new kernel driver. The running
driver is not changed merely by installing an hpkg. These are local builds;
RenkuOS's published repository and default images are not changed by this PR.
Repository publication must include the complete tested stack and resolve the
stock Mesa conflict before an image or `pkgman full-sync` can retain it.

## Verify

Run in a graphical session, after removing prototype overrides:

```sh
bash renkuos/graphics/intel-gen9/verify.sh
bash renkuos/graphics/intel-gen9/verify.sh --software
/boot/system/demos/GLTeapot
```

The hardware check requires the Intel HD 515 renderer, 4096 successful
submissions, correct FBO pixels, 32 BGRA uploads with two live contexts, and
300 presented frames with zero mismatches. The software check must identify
llvmpipe. Resize, repeated context creation, longer runs and other applications
are additional validation, not implied by a basic pass.

Use `listimage GLTeapot` to confirm the packaged `libGL`, `libEGL`,
`libGLdispatch`, Mesa vendor and LLVM are loaded. Check `listimage` for the
kernel driver path too. A run still using old non-packaged files does not
validate the new packages. Confirm the teapot is visibly rendering and moving.

## Evidence from the Mi Air on 2026-11-06

RenkuOS build00074, `hrev60072+580`, x86_64:

- The existing render-node driver loaded and published
  `/dev/graphics/intel_render_9x_000200`.
- After the system update, stock Mesa 22 dispatch was installed and glvnd
  was absent. GLTeapot reported no renderer; `eglInitialize` failed with
  `EGL_NOT_INITIALIZED`.
- The revision-5 glvnd binaries plus the existing corrected Mesa vendor
  restored hardware rendering, first with a process-scoped library path,
  then with non-packaged dispatch overrides and the default search path.
- Renderer: `Mesa Intel(R) HD Graphics 515 (SKL GT2)`; OpenGL 4.6,
  Mesa 25.3.6. Clear pixel: `26,51,76,255`. FBO complete (`0x8cd5`),
  no GL error, correct red center and blue corner. Presentation passed
  300 frames with zero mismatches. The owner confirmed the scoped teapot
  rendered and moved normally; the default launch loaded the restored stack.

Binary identities:

| Component | Identity |
|---|---|
| Running kernel prototype | MD5 `0796534154eb79c888c36f0accca4624` |
| Corrected Mesa EGL vendor | MD5 `e59e0d2d4d6096213da8b897d5a17190` |
| Original glvnd hpkg | SHA256 `47f93aab91801fca43c9a29a9883b9c5af5bb90e44ccc3e63ebaa7289d282e13` |

The new package revisions, their installation transaction, a cold boot with
their newly compiled kernel, and default-image integration are not yet tested.
This distinction is why the submission is a draft.
The standalone driver has now compiled and linked cleanly against the current
RenkuOS SDK. Its newly compiled stress client passed 4096 submissions against
the existing loaded driver. The strengthened graphics clients also passed on
iris and llvmpipe, including resize. See [the validation record](VALIDATION.md)
for the exact scope and output identities.

## Rollback

Remove the HOME driver package with `pkgman uninstall -H intel_extreme_gen9`.
Restore the saved graphics package set through a reviewed package transaction,
replacing `mesa_iris` and glvnd with the previous Mesa runtime/renderer and any
matching development packages. Restore only the prototype files deliberately
kept for that configuration. Cold boot. If the GUI cannot start, use the USB
or boot-loader safe mode to move the HOME driver hpkg out of
`~/config/packages`; the system's original driver remains packaged.

## Review and licensing

The kernel import retains Genode AGPL terms with a linking exception for the
context-layout material; the recipe carries the full license. Source PR #98
records the provenance. This package submission does not approve its inclusion
in the MIT system package or grant a policy exception. License review remains
required. Mesa, libglvnd and the bundled DRM headers retain their notices.

The source recipes and fixes were imported with their original commit history.
AI assistance was used for the original prototype, this integration and its
review. The human contributor remains responsible for the submitted code.
