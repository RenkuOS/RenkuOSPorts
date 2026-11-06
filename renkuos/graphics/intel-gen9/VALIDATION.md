# Mi Air validation — 2026-11-06

Hardware: Xiaomi Mi Air 12.5, Intel HD Graphics 515, PCI `8086:191e`.
OS: RenkuOS build00074, `hrev60072+580`, x86_64.
Installed SDK: `haiku_devel-r1~beta6_hrev60072_580-1-x86_64.hpkg`.
Compiler: GCC 13.3.0 (`2023_08_10`).

## Standalone source build

Exported the driver, common graphics sources, `kernel_cpp.cpp` and private
graphics headers from Source commit
`544c5b738194a5b228e8a7951fcdba8af50f87d6`. Added the port's standalone Makefile
and configuration headers. Built in a fresh directory with `make -j2`
against `/boot/system/develop/headers/private` and
`/boot/system/develop/lib/_KERNEL_`.

Both the driver and client compiled and linked without compiler warnings or
unresolved symbols. The driver link uses `--no-undefined`.

| Output | SHA256 |
|---|---|
| Candidate `intel_extreme` | `9265774ca8fd11268f4e2713957f2a62bfc2ebe52d1f4af287203ac6e56314a9` |
| New `intel-gen9-stress` | `d574807fd902b0d85f9f34d99b63b18b8ad91a0820c9cd473725be5b75241d49` |

The candidate was **not installed or booted**. Its debug/tracing configuration
headers are byte-identical to the default templates in inspected RenkuOS
Source main `e8d122409d`; this does not cover custom kernel configuration
overrides. Their Git blob identities are respectively
`404cb94e487e3e61ea6e660ea8f941282dc1a59b` and
`2cbab809a57c11d16a551d6d5d647037937762c2`.

The newly compiled client ran against the existing loaded driver:

```text
context 3
syncobj 66
Requested 4096 submissions, elapsed 0.144 s
PASS
```

This is source-build compatibility evidence and a client test against the
existing prototype. It is not execution validation of the newly linked kernel.

## Strengthened graphics clients

Built the FBO/window, BGRA upload and presentation clients natively. Used the
available OpenGL headers and explicitly linked the restored dispatch SONAMEs
with `-lbe`. Final compilation had no warnings. No graphics library or kernel
was rebuilt or installed for these client tests.

Both hardware iris and forced llvmpipe passed:

```text
renderer=Mesa Intel(R) HD Graphics 515 (SKL GT2)
PASS failures=0
PASS: 32 texture uploads with two live contexts
PASS: 300 frame present, 0 mismatches; swaps=300 bitmaps=300

renderer=llvmpipe (LLVM 21.1.8, 256 bits)
PASS failures=0
PASS: 32 texture uploads with two live contexts
PASS: 300 frame present, 0 mismatches; swaps=300 bitmaps=300
```

The presentation client now varies the background each frame, checks all
interior/background pixels outside the rasterization-edge bands, and requires
one non-null bitmap for each successful swap. Thus a missing callback or a
repeated stale image cannot silently pass. The FBO client requires a presented
window bitmap as well.

The resize variant (`EGL_HAIKU_TEST_RESIZE=1`) passed on both renderers:

```text
PASS: 300 frame present, 0 mismatches; swaps=300 bitmaps=300
```

The hardware and software baseline tests ran with the coverage-reducing
environment controls unset. The software variant set only
`LIBGL_ALWAYS_SOFTWARE=1` for renderer selection.

GLTeapot rendered and animated normally according to the owner's scoped test.
After the reviewed dispatch repair, a fresh default-environment launch loaded
the restored glvnd libraries, the corrected Mesa vendor and LLVM 21.

## Host checks

- HaikuPorter recipe lint passed for each of the three ports, individually.
- Bash syntax checks cover all recipes and the verification script.
- Source archive checksums and the ordered Mesa patch sequence were checked.
- The committed shader files match the checksummed artifact set.
- The added CI workflow targets `main` and checks these ports directly; it does
  not compare the whole RenkuOS fork against HaikuPorts upstream.

## Remaining acceptance work

- Build and inspect the three revised binary/source packages natively on
  RenkuOS, including their generated SDK requirements and payload providers.
- Run a package-manager replacement transaction with no manual overrides.
- Cold-boot the new driver package and repeat the hardware/software clients.
- Compile and exercise the additional Mesa lifetime fixes; these were not in
  the installed vendor used for today's hardware tests.
- Check future system updates retain the intended stack after repository
  publication. This PR does not publish packages or change the default image.
- Complete the kernel source license/packaging review recorded in Source #98.
