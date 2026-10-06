#!/usr/bin/env bash
# Builds the pinned MuJoCo from its source tarball, checked against its sha256, as one static
# library for this host, and installs its headers into thirdparty/mujoco/include/mujoco, its
# archives into thirdparty/mujoco/lib, which a build with -d mujoco links, and the licenses of
# MuJoCo and its dependencies, unless they are there already. ADR-0008, Distribution, decides the patch and the configure line. The justfile's mujoco
# recipe runs it. The first build needs cmake, Ninja, a C++ compiler, git and the network, since
# CMake fetches seven dependencies at the commits the tag names.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
version=3.14.0
sum=4e1ebd14406967f4554a9c6ed613fe7f88a8ea8a9c272ede80d083a25f9e31a9

# Asks getconf for glibc, as scripts/zenoh.sh does, since archives built against one libc do not
# link against the other.
target="$(uname -s)-$(uname -m)"
if [ "$(uname -s)" = Linux ]; then
    if getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
        target="$target-gnu"
    else
        target="$target-musl"
    fi
fi
dir=thirdparty/mujoco
if [ "$(cat "$dir/VERSION" 2>/dev/null)" = "$version static $target" ] && [ -d "$dir/licenses" ]; then
    exit 0
fi
for tool in cmake ninja git c++; do
    if ! command -v "$tool" >/dev/null; then
        echo "mujoco: building MuJoCo $version needs $tool, which is not on PATH" >&2
        exit 1
    fi
done
echo "mujoco: building MuJoCo $version for $target into $dir, about a minute"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/mujoco.tar.gz" "https://github.com/google-deepmind/mujoco/archive/refs/tags/$version.tar.gz"
got=$( (sha256sum 2>/dev/null || shasum -a 256) <"$tmp/mujoco.tar.gz" | cut -d' ' -f1)
if [ "$got" != "$sum" ]; then
    echo "mujoco: checksum mismatch for MuJoCo $version" >&2
    exit 1
fi
tar -xzf "$tmp/mujoco.tar.gz" -C "$tmp"
src="$tmp/mujoco-$version"

# Upstream builds a shared library only, and CMake refuses to install a static one whose fetched
# dependencies sit in no export set, so the patch makes it static and drops its install rules.
patch -s -p1 -d "$src" <<'EOF'
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -140,7 +140,7 @@
 # Emscripten does not support SHARED libs
 if(NOT EMSCRIPTEN)
   find_package(Threads REQUIRED)
-  add_library(mujoco SHARED ${MUJOCO_RESOURCE_FILES})
+  add_library(mujoco STATIC ${MUJOCO_RESOURCE_FILES})
 else()
   add_library(mujoco STATIC ${MUJOCO_RESOURCE_FILES})
 endif()
@@ -310,7 +310,7 @@
   endif()
 endif()
 
-if(NOT EMSCRIPTEN AND NOT (APPLE AND MUJOCO_BUILD_MACOS_FRAMEWORKS))
+if(FALSE)
   set(MUJOCO_TARGETS mujoco)
 
   # Install the libraries.
EOF

# musl declares localtime_r but, unlike glibc under _GNU_SOURCE, defines no _POSIX_C_SOURCE, which
# engine_util_errmem.c checks for. Link time optimization stays off so the archives hold objects.
cmake -S "$src" -B "$tmp/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS=-D_POSIX_C_SOURCE=200809L -DBUILD_SHARED_LIBS=OFF -DMUJOCO_ENABLE_LTO=OFF \
    -DMUJOCO_BUILD_EXAMPLES=OFF -DMUJOCO_BUILD_SIMULATE=OFF -DMUJOCO_BUILD_TESTS=OFF \
    -DMUJOCO_TEST_PYTHON_UTIL=OFF >"$tmp/configure.log" 2>&1 || {
    tail -n 20 "$tmp/configure.log" >&2
    echo "mujoco: configuring MuJoCo $version failed" >&2
    exit 1
}
cmake --build "$tmp/build" -j4 --target mujoco >"$tmp/build.log" 2>&1 || {
    tail -n 20 "$tmp/build.log" >&2
    echo "mujoco: building MuJoCo $version failed" >&2
    exit 1
}
rm -rf "$dir"
mkdir -p "$dir/include" "$dir/lib"
cp -R "$src/include/mujoco" "$dir/include/"
for a in mujoco ccd qhullstatic_r tinyobjloader tinyxml2 miniz; do
    cp "$tmp/build/lib/lib$a.a" "$dir/lib/"
done
cp "$src/LICENSE" "$dir/"

# The archives carry the dependencies CMake fetched, and a binary built from them carries their
# notices (ADR-0008, Licensing). MarchingCubeCpp states its license in its README only.
for dep in "$tmp"/build/_deps/*-src; do
    name=$(basename "$dep" -src)
    mkdir -p "$dir/licenses/$name"
    for f in "$dep"/LICENSE* "$dep"/COPYING* "$dep"/BSD-LICENSE*; do
        if [ -f "$f" ]; then
            cp "$f" "$dir/licenses/$name/"
        fi
    done
    if [ -z "$(ls "$dir/licenses/$name")" ]; then
        cp "$dep"/README* "$dir/licenses/$name/"
    fi
done
echo "$version static $target" >"$dir/VERSION"
echo "mujoco: installed MuJoCo $version for $target into $dir"
