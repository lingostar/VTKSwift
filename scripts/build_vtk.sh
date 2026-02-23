#!/bin/bash
set -e

#=============================================================================
# VTK Build Script for macOS + iOS (Apple Silicon)
#
# Builds VTK from source:
#   - macOS (arm64): Direct CMake build
#   - iOS (Device + Simulator): VTK's official superbuild (VTK_IOS_BUILD)
#
# Prerequisites:
#   - CMake 3.20+  (brew install cmake)
#   - Ninja        (brew install ninja)
#   - Xcode + CLI tools
#
# Usage:
#   ./scripts/build_vtk.sh          # Build all platforms
#   ./scripts/build_vtk.sh macos    # Build macOS only
#   ./scripts/build_vtk.sh ios      # Build iOS only
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VTK_VERSION="v9.4.2"
VTK_SRC_DIR="$PROJECT_DIR/vtk-src"
BUILD_BASE="$PROJECT_DIR/vtk-build"
INSTALL_BASE="$PROJECT_DIR/vtk-install"
NUM_CORES=$(sysctl -n hw.ncpu)
BUILD_TARGET="${1:-all}"  # all, macos, or ios

echo "============================================"
echo "VTK Build Script for Apple Platforms"
echo "============================================"
echo "VTK Version:  $VTK_VERSION"
echo "Source Dir:    $VTK_SRC_DIR"
echo "Build Dir:     $BUILD_BASE"
echo "Install Dir:   $INSTALL_BASE"
echo "Build Cores:   $NUM_CORES"
echo "Build Target:  $BUILD_TARGET"
echo "============================================"

#-----------------------------------------------------------------------------
# Step 1: Clone VTK source
#-----------------------------------------------------------------------------
if [ ! -d "$VTK_SRC_DIR" ]; then
    echo ""
    echo ">>> Step 1: Cloning VTK $VTK_VERSION ..."
    git clone --depth 1 --branch "$VTK_VERSION" \
        https://gitlab.kitware.com/vtk/vtk.git "$VTK_SRC_DIR"
else
    echo ""
    echo ">>> Step 1: VTK source already exists at $VTK_SRC_DIR (skipping clone)"
fi

#=============================================================================
# MACOS BUILD — Direct CMake build
#=============================================================================
build_macos() {
    echo ""
    echo ">>> Building VTK for macOS (arm64) ..."

    MACOS_BUILD_DIR="$BUILD_BASE/macos-arm64"
    MACOS_INSTALL_DIR="$INSTALL_BASE/macos-arm64"

    mkdir -p "$MACOS_BUILD_DIR"
    cmake -S "$VTK_SRC_DIR" -B "$MACOS_BUILD_DIR" \
        -GNinja \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DVTK_BUILD_TESTING=OFF \
        -DVTK_BUILD_EXAMPLES=OFF \
        -DVTK_WRAP_PYTHON=OFF \
        -DVTK_WRAP_JAVA=OFF \
        -DVTK_ENABLE_WRAPPING=OFF \
        -DVTK_GROUP_ENABLE_Web=NO \
        -DVTK_GROUP_ENABLE_MPI=NO \
        -DVTK_GROUP_ENABLE_Qt=NO \
        -DVTK_GROUP_ENABLE_Views=NO \
        -DVTK_GROUP_ENABLE_Imaging=NO \
        -DVTK_MODULE_ENABLE_VTK_RenderingCore=YES \
        -DVTK_MODULE_ENABLE_VTK_RenderingOpenGL2=YES \
        -DVTK_MODULE_ENABLE_VTK_RenderingUI=YES \
        -DVTK_MODULE_ENABLE_VTK_FiltersSources=YES \
        -DVTK_MODULE_ENABLE_VTK_FiltersCore=YES \
        -DVTK_MODULE_ENABLE_VTK_FiltersGeneral=YES \
        -DVTK_MODULE_ENABLE_VTK_InteractionStyle=YES \
        -DVTK_MODULE_ENABLE_VTK_CommonCore=YES \
        -DVTK_MODULE_ENABLE_VTK_CommonDataModel=YES \
        -DVTK_MODULE_ENABLE_VTK_CommonExecutionModel=YES \
        -DVTK_MODULE_ENABLE_VTK_CommonMath=YES \
        -DVTK_MODULE_ENABLE_VTK_CommonTransforms=YES \
        -DVTK_DEFAULT_RENDER_WINDOW_HEADLESS=OFF \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DCMAKE_INSTALL_PREFIX="$MACOS_INSTALL_DIR"

    cmake --build "$MACOS_BUILD_DIR" -- -j"$NUM_CORES"
    cmake --install "$MACOS_BUILD_DIR"

    # Combine all static libraries into a single libVTK.a
    echo "    Combining macOS static libraries ..."
    local LIB_FILES=()
    while IFS= read -r -d '' file; do
        LIB_FILES+=("$file")
    done < <(find "$MACOS_INSTALL_DIR/lib" -name "libvtk*.a" -print0)

    if [ ${#LIB_FILES[@]} -gt 0 ]; then
        libtool -static -o "$MACOS_INSTALL_DIR/lib/libVTK.a" "${LIB_FILES[@]}"
        echo "    Created: $MACOS_INSTALL_DIR/lib/libVTK.a (${#LIB_FILES[@]} libs combined)"
    fi

    echo "    macOS build complete: $MACOS_INSTALL_DIR"
}

#=============================================================================
# IOS BUILD — VTK's official superbuild (VTK_IOS_BUILD=ON)
#
# This uses VTK's CMake/vtkiOS.cmake which automatically handles:
#   1. Building host compile tools (VTKCompileTools)
#   2. Cross-compiling for device (arm64) via ios.device.toolchain
#   3. Cross-compiling for simulator (arm64) via ios.simulator.toolchain
#   4. Combining into a vtk.framework
#=============================================================================
build_ios() {
    echo ""
    echo ">>> Building VTK for iOS (official superbuild) ..."

    IOS_BUILD_DIR="$BUILD_BASE/ios-superbuild"
    IOS_INSTALL_DIR="$INSTALL_BASE/ios"

    mkdir -p "$IOS_BUILD_DIR"
    mkdir -p "$IOS_INSTALL_DIR"

    # The VTK_IOS_BUILD superbuild uses "Unix Makefiles" or Ninja for
    # the outer build, but ExternalProject_Add subbuilds.
    # Ninja works as the outer generator; subbuilds use CMAKE_MAKE_PROGRAM.
    cmake -S "$VTK_SRC_DIR" -B "$IOS_BUILD_DIR" \
        -GNinja \
        -DVTK_IOS_BUILD=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DIOS_DEVICE_ARCHITECTURES="arm64" \
        -DIOS_SIMULATOR_ARCHITECTURES="arm64" \
        -DIOS_EMBED_BITCODE=OFF \
        -DCMAKE_INSTALL_PREFIX="$IOS_INSTALL_DIR" \
        -DCMAKE_MAKE_PROGRAM="$(which ninja)" \
        -DVTK_MODULE_ENABLE_VTK_InteractionStyle=ON \
        -DVTK_MODULE_ENABLE_VTK_RenderingOpenGL2=ON \
        -DVTK_MODULE_ENABLE_VTK_FiltersSources=ON

    cmake --build "$IOS_BUILD_DIR" -- -j"$NUM_CORES"

    echo "    iOS superbuild complete."

    # The superbuild outputs are in CMakeExternals/Install/
    local IOS_EXTERN="$IOS_BUILD_DIR/CMakeExternals/Install"

    # Copy device libraries and headers to a known location
    local DEVICE_DIR="$IOS_EXTERN/vtk-ios-device-arm64"
    local SIM_DIR="$IOS_EXTERN/vtk-ios-simulator"

    # Detect VTK header version directory name
    local VTK_INC_DIR=""

    if [ -d "$DEVICE_DIR" ]; then
        echo "    Copying iOS device artifacts ..."
        mkdir -p "$INSTALL_BASE/ios-arm64"
        if [ -d "$DEVICE_DIR/include" ]; then
            cp -R "$DEVICE_DIR/include" "$INSTALL_BASE/ios-arm64/"
            # Find the vtk-X.Y directory name
            VTK_INC_DIR=$(find "$DEVICE_DIR/include" -maxdepth 1 -name "vtk-*" -type d | head -1 | xargs basename 2>/dev/null || echo "vtk-9.4")
        fi
        mkdir -p "$INSTALL_BASE/ios-arm64/lib"
        find "$DEVICE_DIR/lib" -name "libvtk*.a" -exec cp {} "$INSTALL_BASE/ios-arm64/lib/" \; 2>/dev/null || true

        # Combine into single library
        local DEVICE_LIBS=()
        while IFS= read -r -d '' file; do
            DEVICE_LIBS+=("$file")
        done < <(find "$INSTALL_BASE/ios-arm64/lib" -name "libvtk*.a" -print0)

        if [ ${#DEVICE_LIBS[@]} -gt 0 ]; then
            libtool -static -o "$INSTALL_BASE/ios-arm64/lib/libVTK.a" "${DEVICE_LIBS[@]}"
            echo "    Created: ios-arm64/lib/libVTK.a (${#DEVICE_LIBS[@]} libs)"
        fi
    fi

    if [ -d "$SIM_DIR" ]; then
        echo "    Copying iOS simulator artifacts ..."
        mkdir -p "$INSTALL_BASE/ios-sim-arm64"
        if [ -d "$SIM_DIR/include" ]; then
            cp -R "$SIM_DIR/include" "$INSTALL_BASE/ios-sim-arm64/"
        fi
        mkdir -p "$INSTALL_BASE/ios-sim-arm64/lib"
        find "$SIM_DIR/lib" -name "libvtk*.a" -exec cp {} "$INSTALL_BASE/ios-sim-arm64/lib/" \; 2>/dev/null || true

        # Combine into single library
        local SIM_LIBS=()
        while IFS= read -r -d '' file; do
            SIM_LIBS+=("$file")
        done < <(find "$INSTALL_BASE/ios-sim-arm64/lib" -name "libvtk*.a" -print0)

        if [ ${#SIM_LIBS[@]} -gt 0 ]; then
            libtool -static -o "$INSTALL_BASE/ios-sim-arm64/lib/libVTK.a" "${SIM_LIBS[@]}"
            echo "    Created: ios-sim-arm64/lib/libVTK.a (${#SIM_LIBS[@]} libs)"
        fi
    fi

    # Check for the framework created by the superbuild
    local FW_DIR="$IOS_INSTALL_DIR/frameworks"
    if [ -d "$FW_DIR/vtk.framework" ]; then
        echo "    vtk.framework found at: $FW_DIR/vtk.framework"
        mkdir -p "$PROJECT_DIR/Frameworks"
        cp -R "$FW_DIR/vtk.framework" "$PROJECT_DIR/Frameworks/"
    fi

    # Print the VTK include directory name for project configuration
    if [ -n "$VTK_INC_DIR" ]; then
        echo ""
        echo "    VTK include directory: $VTK_INC_DIR"
        echo "    (Update project.yml HEADER_SEARCH_PATHS if different from vtk-9.4)"
    fi

    echo "    iOS build complete."
}

#=============================================================================
# Run the requested builds
#=============================================================================
case "$BUILD_TARGET" in
    macos)
        build_macos
        ;;
    ios)
        build_ios
        ;;
    all)
        build_macos
        build_ios
        ;;
    *)
        echo "Unknown target: $BUILD_TARGET"
        echo "Usage: $0 [all|macos|ios]"
        exit 1
        ;;
esac

#=============================================================================
# Summary
#=============================================================================
echo ""
echo "============================================"
echo "VTK build complete!"
echo "============================================"
echo ""
echo "Artifacts:"
[ -d "$INSTALL_BASE/macos-arm64/lib" ] && \
    echo "  macOS:     $INSTALL_BASE/macos-arm64/"
[ -d "$INSTALL_BASE/ios-arm64/lib" ] && \
    echo "  iOS:       $INSTALL_BASE/ios-arm64/"
[ -d "$INSTALL_BASE/ios-sim-arm64/lib" ] && \
    echo "  iOS Sim:   $INSTALL_BASE/ios-sim-arm64/"
echo ""
echo "Next steps:"
echo "  1. xcodegen generate"
echo "  2. Open VTKSwift.xcodeproj in Xcode"
echo "  3. Build and run"
echo "============================================"
