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
| `UserBootscript.nightly` | guest | After Phase 1, builds the ports in `nightly-ports.txt` from the RenkuOSPorts tree, two tries each. Copy it to `phase1b/UserBootscript` to use it. See "The nightly run" below. |
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

`UserBootscript.nightly` runs in the same image after Phase 1. It needs three files in
`/boot/home`, copied in with `bfsq.sh`: `renkuosports.tar` (the recipe tree),
`nightly-ports.txt` (from `phase2/resolve.py`), and `nightly-downloads.tar` (every
source, fetched on the host with `fetch-recipe.sh`). Before the first boot, make these
changes to the image by hand:

- **Swap in the real flex and bison.** HaikuPorter takes build tools from
  `/boot/system/packages` and prefers them to newer builds of the same version. The
  bootstrap flex 2.5.35 is too old for doxygen, and the bootstrap bison's `--version`
  fails. Replace both with the packages Phase 1 built.
- **Add `makefile_engine` and `mkdepend`** to `/boot/system/packages`. Ports such as
  vision build-prerequire `makefile_engine`, which Haiku's own build makes and the
  bootstrap image leaves out. HaikuPorter only sees it as a system package.
  `makefile_engine` is an `any` package, so take it from an x86_64 build, but recompress
  it first with `package recompress -z zlib`. The arm64 bootstrap `package` tool has no
  zstd, and HaikuPorter skips a package it cannot read without saying why.
- **Make debug_server kill crashed programs** instead of waiting for a debugger:
  `default_action kill` in `~/config/settings/system/debug_server/settings`.

The first arm64 nightly ended on 2026-11-02 with 382 packages, counting Phase 1's. At 8
vCPUs, gcc alone took 11.8 hours. Six ports failed:

- **pe and libsdl2** link system libraries the bootstrap image does not have (libmail,
  libmedia, and libgame). **ffmpeg6 and ffmpeg8** need libsdl2.
- **wpa_supplicant and vision** fail when they compile their translation catalogs.
  `linkcatkeys` rejects every `.catkeys` file with "Bad data", because Haiku's
  `CatKey::HashFun` hashes plain `char`, which is unsigned on arm64 and signed on x86.
  The fix belongs in RenkuOS/Source. makefile-engine compiles catalogs for every app
  that has them, so this affects many ports.

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
