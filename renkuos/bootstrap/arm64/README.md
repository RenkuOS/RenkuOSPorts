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
| `bfsq.sh` | build host | Runs `fs_shell` commands against the image's BFS partition while QEMU is off. |
| `fetch-recipe.sh` | build host | Downloads a recipe's sources into `download/` with the `.uri` files HaikuPorter expects. The guest has no curl or wget. |
| `monitor.sh` | your machine | Waits over ssh for the next failure, watchdog kill, reboot, or stage change, then prints it. |
| `run-bench.sh`, `UserBootscript.bench` | build host | Measures serial and parallel build speed at several vCPU counts. |

`phase1b-run.sh` expects a `@bootstrap-raw` arm64 build in
`$BUILD_ROOT/wt-phase1/gen.arm64-bootstrap` (override with `GEN_DIR`), with
`phase1b/pristine.image` and the boot script in `phase1b/UserBootscript`. The image's BFS
partition starts at sector 73728.

## What the boot script does

1. Sets the clock from the host. The arm64 kernel has no RTC driver and boots at time 0,
   which makes timestamp checks in builds loop forever.
2. **Stage A.** Builds the non-cyclic ports that the cyclic ones need, one at a time with
   `--missing-dependencies`, and installs them as system packages. `--do-bootstrap` only
   schedules cyclic ports, and it only looks for their prerequisites in
   `/boot/system/packages`. No `_bootstrap` package set, on any architecture, provides
   perl, autoconf, diffutils, or libiconv.
3. Runs `haikuporter --do-bootstrap`. If the cycle still cannot start, it builds a heavy set
   (binutils, gcc, ICU, and LLVM) and tries once more.
4. Installs the resulting full Python, which HaikuPorter needs to unpack `.tar.gz` sources,
   and builds the target ports with it.

Each finished port is recorded, so a reboot resumes where the last boot stopped.

## Findings

- **Use 8 vCPUs.** Under TCG (QEMU 8.2), serial work slows with every vCPU added, and
  parallel compiles are fastest at 8. Perl took 6.6 hours at 24 vCPUs and about 3.5 hours
  at 4.
- **tar hangs in configure.** gnulib's `re_compile_pattern` test ran for 5 hours on arm64,
  and hung again on the retry.
  The boot script's watchdog kills any `conftest` after an hour without log output.
- **libtool needed git.** Its recipe ran `./bootstrap`, which clones gnulib. Fixed on `main`.
- **launch_daemon stall.** A pipe without `O_CLOEXEC` stalled 6 of 11 boots in one test.
  Fixed in RenkuOS/Source PR #231.
