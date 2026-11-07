# arm64 bootstrap

These scripts build arm64 packages natively on arm64 Haiku, running in
`qemu-system-aarch64` on an x86_64 Linux host. They follow Haiku's
`docs/develop/packages/Bootstrapping.rst` and add the steps that the current recipes need.
The plan they serve is `Planning/DocsForRelease/arm64-packages-plan.md` in the RenkuOS
planning notes.

## Files

| File | Runs on | What it does |
|---|---|---|
| `phase1b-run.sh` | build host | Boots the work image until the boot script reports `PHASE1 end`. It restarts a guest that crashes or stays silent for 40 minutes, and copies new packages off the image after every boot. |
| `UserBootscript` | guest | Builds the ports. `phase1b-run.sh` substitutes `HOST_EPOCH` and `JOBS` and writes it into the image before each boot. |
| `UserBootscript.nightly` | guest | After Phase 1, builds the ports in `nightly-ports.txt` from the RenkuOSPorts tree, two tries each. See "The nightly run" below. |
| `prepare-nightly.sh` | build host | Readies the work image for `UserBootscript.nightly` and installs it as the boot script. |
| `run-nightly.sh` | build host | Runs the whole nightly: prepares the image and runs `phase1b-run.sh`, in two passes when flex or mkdepend is still missing. |
| `update-packages.sh` | runner | Rebuilds the ports whose recipes changed since the last successful run. See "The package runner" below. |
| `publish-repo.sh` | runner | Builds the package repository and packs it, and the debug info, for the `arm64-packages` release. |
| `bfsq.sh` | build host | Runs `fs_shell` commands against the image's BFS partition while QEMU is off. |
| `fetch-recipe.sh` | build host | Downloads a recipe's sources into `download/` with the `.uri` files HaikuPorter expects. The guest has no curl or wget. |
| `temp-guard.sh` | build host | Logs the CPU temperature every minute to `logs/cputemp.log`. It pauses the guest at 85°C and resumes it below 70°C. |
| `monitor.sh` | your machine | Waits over ssh for the next failure, watchdog kill, reboot, or stage change, then prints it. |
| `run-bench.sh`, `UserBootscript.bench` | build host | Measures serial and parallel build speed at several vCPU counts. |

`phase1b-run.sh` expects a `@bootstrap-raw` arm64 build in
`$BUILD_ROOT/wt-phase1/gen.arm64-bootstrap` (override with `GEN_DIR`), with
`phase1b/pristine.image` and the boot script in `phase1b/UserBootscript`. The image's BFS
partition starts at sector 73728.

The host tools need two paths in place:

- `fs_shell` has its attributes directory compiled in under `/home/kevin/haiku-build`. If
  the build root is somewhere else, make that path a symlink to it.
- The host `package create`, used to rebuild a rigged source package, looks for
  `$GEN_DIR/../data/system`. Link `$GEN_DIR/../data` to the `data` directory of a Haiku
  source tree.

## What the boot script does

1. Sets the clock from the host. The arm64 kernel has no RTC driver and boots at time 0,
   which makes timestamp checks in builds loop forever.
2. **Stage A.** Builds the non-cyclic ports that the cyclic ones need, one at a time with
   `--missing-dependencies`, and installs them as system packages. `--do-bootstrap` only
   schedules cyclic ports, and it only looks for their prerequisites in
   `/boot/system/packages`. No `_bootstrap` package set, on any architecture, provides
   perl, autoconf, diffutils, or libiconv.
3. Builds gettext, xz_utils, and the full python3.10 the same way. This needs the gettext
   cut on the `bootstrap/arm64` branch, which takes groff and makeinfo out of the cycle.
   `--do-bootstrap` is not used: with truncated system packages it obsoleted every package
   and then crashed.
4. Runs HaikuPorter with the full Python, which it needs to unpack `.tar.gz` sources, and
   builds the target ports with `--no-git-repo`.

Before the boot that runs step 4, swap the packages by hand with `bfsq.sh`. Move
`python3.10_bootstrap` and the zlib, libffi, ncurses6, and expat bootstrap packages out of
`/boot/system/packages`, then copy in the full packages and their `_devel` packages. Each
pair provides the same names, so the two never activate together, even with the full ones
in `~/config/packages`.

Each finished port is recorded, so a reboot resumes where the last boot stopped.

## The nightly run

`UserBootscript.nightly` runs in the same image after Phase 1. Start it with
`run-nightly.sh <nightly-ports.txt> <nightly-recipes.txt>`, using the lists from
`phase2/resolve.py`, with QEMU off. Set `PORTS_TREE` to the RenkuOSPorts checkout that
holds the `download/` directories, and `MAKEFILE_ENGINE` to a
`makefile_engine-*-any.hpkg` from any Haiku build. `run-nightly.sh` calls
`prepare-nightly.sh`, which makes these changes to the image:

- **Inputs.** It writes `renkuosports.tar` (the tree at `PORTS_REF`, by default
  `bootstrap/arm64`), the port list, and `nightly-downloads.tar` into `/boot/home`. The
  sources come from `fetch-recipe.sh`. The guest keeps the tree and records its commit
  in `/boot/home/nightly-tree.<commit>`, so later runs send only the files changed since
  then, plus a list of removed files. HaikuPorter parses a recipe again whenever it is
  newer than its dependency info, and parsing the whole tree takes about 4 hours in the
  guest.
- **The real flex and bison.** HaikuPorter takes build tools from
  `/boot/system/packages`, and it picks the bootstrap ones there over newer builds. The
  bootstrap flex 2.5.35 is too old for doxygen, and the bootstrap bison's `--version`
  fails. The script moves both to `/boot/home/removed-bootstrap` and installs the real
  ones. Phase 1 builds bison, but not flex, which needs `autopoint` and `makeinfo`. So
  when flex or mkdepend is missing, `run-nightly.sh` first runs a short pass that builds
  just those two, then prepares the image again for the full list.
- **`makefile_engine` and `mkdepend`** in `/boot/system/packages`. Ports such as vision
  build-prerequire `makefile_engine`, which Haiku's own build makes and the bootstrap
  image leaves out. HaikuPorter only sees it as a system package. The script recompresses
  it with zlib, because the arm64 bootstrap `package` tool has no zstd and HaikuPorter
  skips a package it cannot read without saying why.
- **debug_server kills crashed programs** instead of waiting for a debugger.
- **A regular `haiku`, if `HAIKU_GEN` is set.** The bootstrap `haiku` package leaves out
  libmail, libmedia, libgame, and a few other libraries that ports such as pe and libsdl2
  link. Set `HAIKU_GEN` to the generated directory of a regular arm64 build (configured
  with `--cross-tools-prefix`, not `@bootstrap-raw`) after `jam -q haiku.hpkg
  haiku_devel.hpkg`. The script swaps both packages in and also replaces
  `EFI/BOOT/BOOTAA64.EFI` with that build's loader, because a loader and kernel from
  different commits can disagree on `kernel_args`. A bootstrap loader from before
  `2fe0ded501` crashes a newer kernel right after `ExitBootServices`.
- **The fonts and firmware the regular `haiku` requires.** HaikuPorter will not use a
  `haiku` package whose requirements it cannot resolve. It resolves noto and coreutils
  from the packages it built, but noto_sans_cjk_jp and the four wifi firmware packages
  come from elsewhere. The script installs them as system packages, recompressed with
  zlib. It takes `mediatek_wifi_firmwares` from `HAIKU_GEN` (run `jam -q
  mediatek_wifi_firmwares.hpkg` there first) and the others from `ANY_PACKAGES`, a
  directory of `*-any.hpkg` files such as an x86_64 build's `download/`.
- **Empty locale settings.** The regular `haiku` has FirstBootPrompt. Until
  `~/config/settings/Locale settings` exists, the launch_daemon starts it instead of the
  desktop, which is what runs the boot script. Without the file, the first boot sits at an
  invisible language prompt until `phase1b-run.sh` restarts it 40 minutes later. The
  script writes an empty one, which the Locale Kit reads as en_US.

Run `prepare-nightly.sh` again after changing recipes or the port list. Ports that
already built stay built. Delete a port's marker in `/boot/home/nightly` to build it
again.

The first arm64 nightly ended on 2026-11-02 with 382 packages, counting Phase 1's. At 8
vCPUs, gcc alone took 11.8 hours. Six ports failed:

- **pe and libsdl2** link system libraries the bootstrap image does not have (libmail,
  libmedia, and libgame). **ffmpeg6 and ffmpeg8** need libsdl2.
- **wpa_supplicant and vision** fail when they compile their translation catalogs.
  `linkcatkeys` rejects every `.catkeys` file with "Bad data", because Haiku's
  `CatKey::HashFun` hashes plain `char`, which is unsigned on arm64 and signed on x86.
  The fix belongs in RenkuOS/Source. makefile-engine compiles catalogs for every app
  that has them, so this affects many ports.

All six built on 2026-11-03, on a regular `haiku` from RenkuOS/Source at the commit of
PR #278, which fixes `HashFun`. That brought the total to 400 packages.

## The package runner

`.github/workflows/arm64-packages.yml` runs every night at 03:00 UTC, and by hand from
the Actions tab, on a self-hosted runner labeled `renkuos-arm64`. That runner is
192.168.74.128, a VM next to .122 with 12 vCPUs, 24 GB of memory, and 300 GB of disk. The
workflow has no pull request or push trigger, because the runner runs this repository's
code on our own machine.

`update-packages.sh` follows HaikuPorter's buildmaster `update`:

1. It diffs `bootstrap/arm64` from the commit in `$BUILD_ROOT/processed_rev` to the
   branch's head.
2. It asks HaikuPorter, running on the host, which active arm64 ports the changed files
   belong to (`--ports-for-files --active-versions-only`). A recipe for a version arm64
   does not use, such as gcc 15, does not count.
3. It keeps the ports we already build or that the nightly list names, and builds them in
   the guest with `prepare-nightly.sh` (`REBUILD=1`) and `phase1b-run.sh`. The guest
   cannot download, so the host fetches the sources of every recipe of those ports,
   including a new version's.
4. It moves `processed_rev` to the new head only when every port built, so a failed port
   is tried again the next night.

Bump a recipe's `REVISION` when changing it. The host keeps the first copy of each package
file name, so a rebuild under the same name would not replace it.

When anything was built, a second job runs `publish-repo.sh` and uploads two archives
to the `arm64-packages` release, replacing the previous ones. It is a job of its own
because the job token expires after 24 hours. `$BUILD_ROOT/unpublished` stays until an
upload succeeds, so a failed upload is tried again the next night.

- `renkuosports-arm64-repo.tar` has `repo`, `repo.info`, `repo.sha256`, and `packages/`,
  with the newest version of each package. Unpack it where `repo.info`'s `baseurl`
  points.
- `renkuosports-arm64-debuginfo.tar` has the `_debuginfo` packages, which images do not
  need.

A release file can hold at most 2 GiB, and each archive is about 0.7 GB today.

### Setting up the runner

On the VM, as `kevin`, in `~/haiku-build` (the `BUILD_ROOT` the workflow uses):

- `wt-phase1/gen.arm64-bootstrap`, with the work image, and `phase1-packages/bootstrap`,
  copied from the build that made them. Copy the images with `tar --sparse` over ssh,
  because `rsync -S` sends their empty space over the network.
- `phase2/nightly-ports.txt` and `phase2/nightly-recipes.txt`.
- `RenkuOSPorts`, a clone on `bootstrap/arm64`, with the `download/` directories copied
  in. The workflow checks out the branch's head there on every run.
- `haikuporter` and `haiku-licenses`, clones of github.com/haikuports/haikuporter and
  github.com/waddlesplash/haiku-licenses.
- `inputs/makefile_engine-*-any.hpkg`, and `inputs/tools/package_repo` with
  `libroot_build.so`, `libbe_build.so`, and `libpackage_build.so` in `inputs/tools/lib`,
  all from an x86_64 Haiku build.
- `processed_rev`, holding the commit the packages were built from.
- Packages: `qemu-system-arm qemu-efi-aarch64 qemu-utils mtools fdisk git curl python3 gh`
  and the Haiku build dependencies.

Register the runner in an organization runner group that only RenkuOSPorts can use, with
the label `renkuos-arm64`, and install it as a service running as `kevin`. The
repository requires approval for workflows from every outside contributor.

The VM cannot read CPU temperatures, so `temp-guard.sh` does not run there. The host's
own thermal protection covers it.

## Findings

- **Use 8 vCPUs.** Under TCG (QEMU 8.2), serial work slows with every vCPU added, and
  parallel compiles are fastest at 8. Perl took 6.6 hours at 24 vCPUs and about 3.5 hours
  at 4.
- **tar hangs in configure.** gnulib's `re_compile_pattern` test ran for 5 hours on arm64,
  and hung again on the retry.
  The boot script's watchdog kills any `conftest` after an hour without log output.
- **libtool needed git.** Its recipe ran `./bootstrap`, which clones gnulib. Fixed on `main`.
- **Phase 1 times** at 8 vCPUs on an i9-12900K: gettext 1 h 51 min, python3.10 2 h 54 min
  (with zstd and openssl3), cmake with python3.14 and curl about 3 h 30 min, and libogg,
  libvorbis, and fluidlite under 5 minutes each.
- **`fs_shell` `cp` does not overwrite.** Run `rm` on the file first.
- **HaikuPorter caches parsed recipes** in `repository/recipeCache`. Delete a recipe's entry
  after editing it in the image.
- **No git in the guest.** HaikuPorter applies patches through an implicit git repository
  unless it runs with `--no-git-repo`.
- **launch_daemon stall.** A pipe without `O_CLOEXEC` stalled 6 of 11 boots in one test.
  Fixed in RenkuOS/Source PR #231.
