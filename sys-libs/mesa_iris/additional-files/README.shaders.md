# Pre-generated Intel CLC shader artifacts (for the iris build on Haiku)

These files replace Mesa's `idep_intel_shaders` custom targets
(`src/intel/shaders/meson.build`), which on Haiku cannot be built because they need
`mesa_clc` + `vtn_bindgen2` + `libclc` (clang/LLVM), and HaikuPorts has no libclc.

They are architecture-independent data (SPIR-V + generated C++), so they are generated
once on a Linux host and shipped into the Haiku build.

Source: Mesa 25.3.6 (`https://archive.mesa3d.org/mesa-25.3.6.tar.xz`,
sha256 59217efeac3b64e7ced958324b9db7494f1e0741aeb22d780276514cc1b8f206).
Generators built with clang/LLVM 23.1.1 (`mesa_clc`, `vtn_bindgen2`).

For each gfx gen in {80,90,110,120,125,200,300}:
  intel_gfx<gen>_shaders.spv                 (mesa_clc output)
  intel_gfx<gen>_shaders_binding.cpp          (vtn_bindgen2 output — compile this)
  intel_gfx<gen>_shaders_binding.h            (vtn_bindgen2 output — header)

The Haiku build only needs the `_binding.cpp` + `_binding.h` files; the `.spv` are kept
for reference/regeneration.

## How they were produced (reproducible)

```sh
# Host: Linux, clang/LLVM 23 + libclc (pkg-config libclc) + spirv-tools + llvm-spirv.
python3 -m venv /tmp/mesa-native-venv
/tmp/mesa-native-venv/bin/pip install meson mako pyyaml packaging setuptools
curl -o mesa-25.3.6.tar.xz https://archive.mesa3d.org/mesa-25.3.6.tar.xz
mkdir mesa-native-src && tar -C mesa-native-src --strip-components=1 -xf mesa-25.3.6.tar.xz
cd mesa-native-src

# LLVM 23 removed the 2-arg TargetRegistry::lookupTarget overload; patch clc_helpers.cpp:
#   #if LLVM_VERSION_MAJOR >= 23
#     llvm::Triple triple_obj(triple);
#     auto target = TargetRegistry::lookupTarget(triple, triple_obj, error_msg);
#   #else
#     auto target = TargetRegistry::lookupTarget(triple, error_msg);
#   #endif

PATH=/tmp/mesa-native-venv/bin:$PATH /tmp/mesa-native-venv/bin/meson setup build-native \
  -Dgallium-drivers=iris -Dvulkan-drivers= -Dplatforms= -Dglx=disabled -Degl=disabled \
  -Dgbm=disabled -Dopengl=false -Dmesa-clc=enabled -Dinstall-mesa-clc=true
PATH=/tmp/mesa-native-venv/bin:$PATH ninja -C build-native \
  src/compiler/clc/mesa_clc src/compiler/spirv/vtn_bindgen2
for g in 80 90 110 120 125 200 300; do
  PATH=/tmp/mesa-native-venv/bin:$PATH ninja -C build-native \
    src/intel/shaders/intel_gfx${g}_shaders_binding.cpp
done
# Outputs are in build-native/src/intel/shaders/.
```

Generator binaries (Linux x86_64) built from the same tree:
- `mesa_clc`      sha256 d2554310d06790cc6e97ab211cd8951f6175e022e8cd9482bf2a94a5b6a45c9b
- `vtn_bindgen2`  sha256 b242898da8cb817e15e6c0e6c4d9bee8f1044ec4c2d3bb40adbec9d435b19720
- patched `src/compiler/clc/clc_helpers.cpp` sha256 56ccd26cd12dc542 (prefix)
