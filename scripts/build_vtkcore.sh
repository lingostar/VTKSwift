#!/bin/bash
set -e

#=============================================================================
# VTKCore XCFramework Build Script
#
# Takes pre-built VTK static libraries (from build_vtk.sh) and the
# Objective-C++ bridge, then packages them into VTKCore.xcframework.
#
# Prerequisites:
#   - VTK already built: vtk-install/{macos-arm64,ios-arm64,ios-sim-arm64}/
#   - Xcode + CLI tools
#
# Usage:
#   ./scripts/build_vtkcore.sh          # Build all platforms
#   ./scripts/build_vtkcore.sh macos    # Build macOS only
#   ./scripts/build_vtkcore.sh ios      # Build iOS only
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FRAMEWORK_DIR="$PROJECT_DIR/framework"
VTK_INSTALL="$PROJECT_DIR/vtk-install"
BRIDGE_DIR="$PROJECT_DIR/VTKSwiftApp/Bridge"
BUILD_DIR="$FRAMEWORK_DIR/build"
OUTPUT_DIR="$FRAMEWORK_DIR"
BUILD_TARGET="${1:-all}"

# VTK version (matches header directory name)
VTK_INC="vtk-9.4"

# Deployment targets (must match project.yml)
MACOS_DEPLOYMENT_TARGET="14.0"
IOS_DEPLOYMENT_TARGET="16.0"

echo "============================================"
echo "VTKCore XCFramework Build"
echo "============================================"
echo "Project Dir:  $PROJECT_DIR"
echo "VTK Install:  $VTK_INSTALL"
echo "Output:       $OUTPUT_DIR/VTKCore.xcframework"
echo "Build Target: $BUILD_TARGET"
echo "============================================"

# Source files to compile
BRIDGE_SOURCES=(
    "$BRIDGE_DIR/VTKBridge.mm"
    "$FRAMEWORK_DIR/VTKModuleInit.mm"
)

#-----------------------------------------------------------------------------
# Compile bridge sources for a given platform
# Args: $1=platform_name $2=vtk_install_subdir $3=clang_target $4=sdk $5=extra_flags
#-----------------------------------------------------------------------------
compile_bridge() {
    local PLATFORM_NAME="$1"
    local VTK_SUBDIR="$2"
    local CLANG_TARGET="$3"
    local SDK_NAME="$4"
    local EXTRA_FLAGS="$5"

    local PLATFORM_BUILD="$BUILD_DIR/$PLATFORM_NAME"
    local VTK_HEADERS="$VTK_INSTALL/$VTK_SUBDIR/include/$VTK_INC"
    local VTK_LIB="$VTK_INSTALL/$VTK_SUBDIR/lib/libVTK.a"
    local SDK_PATH
    SDK_PATH="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"

    echo ""
    echo ">>> Compiling bridge for $PLATFORM_NAME ..."

    # Verify prerequisites
    if [ ! -d "$VTK_HEADERS" ]; then
        echo "ERROR: VTK headers not found at $VTK_HEADERS"
        echo "       Run ./scripts/build_vtk.sh first."
        exit 1
    fi
    if [ ! -f "$VTK_LIB" ]; then
        echo "ERROR: libVTK.a not found at $VTK_LIB"
        exit 1
    fi

    mkdir -p "$PLATFORM_BUILD"

    # Compile each source file
    local OBJ_FILES=()
    for src in "${BRIDGE_SOURCES[@]}"; do
        local basename
        basename="$(basename "$src" .mm)"
        local obj="$PLATFORM_BUILD/${basename}.o"

        echo "    Compiling $(basename "$src") ..."
        xcrun clang++ -c "$src" -o "$obj" \
            -std=c++17 \
            -fPIC \
            -target "$CLANG_TARGET" \
            -isysroot "$SDK_PATH" \
            -I "$VTK_HEADERS" \
            -I "$BRIDGE_DIR" \
            -fobjc-arc \
            -DNDEBUG \
            -O2 \
            $EXTRA_FLAGS

        OBJ_FILES+=("$obj")
    done

    # Merge bridge objects + VTK static lib into single libVTKCore.a
    echo "    Merging into libVTKCore.a ..."
    xcrun libtool -static -o "$PLATFORM_BUILD/libVTKCore.a" \
        "${OBJ_FILES[@]}" "$VTK_LIB"

    local LIB_SIZE
    LIB_SIZE=$(du -sh "$PLATFORM_BUILD/libVTKCore.a" | cut -f1)
    echo "    Created: $PLATFORM_BUILD/libVTKCore.a ($LIB_SIZE)"

    # Build .framework directory structure
    local FW_DIR="$PLATFORM_BUILD/VTKCore.framework"
    rm -rf "$FW_DIR"
    mkdir -p "$FW_DIR/Headers"
    mkdir -p "$FW_DIR/Modules"

    cp "$PLATFORM_BUILD/libVTKCore.a" "$FW_DIR/VTKCore"
    cp "$BRIDGE_DIR/VTKBridge.h" "$FW_DIR/Headers/"
    cp "$FRAMEWORK_DIR/module.modulemap" "$FW_DIR/Modules/"

    # Generate Info.plist
    cat > "$FW_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>VTKCore</string>
    <key>CFBundleIdentifier</key>
    <string>com.developeracademy.VTKCore</string>
    <key>CFBundleName</key>
    <string>VTKCore</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
</dict>
</plist>
PLIST

    echo "    Framework built: $FW_DIR"
}

#-----------------------------------------------------------------------------
# Build all platforms and create XCFramework
#-----------------------------------------------------------------------------

# Determine which platforms to build
PLATFORMS=()

case "$BUILD_TARGET" in
    macos)
        PLATFORMS=("macos")
        ;;
    ios)
        PLATFORMS=("ios-device" "ios-simulator")
        ;;
    all)
        PLATFORMS=("macos" "ios-device" "ios-simulator")
        ;;
    *)
        echo "Unknown target: $BUILD_TARGET"
        echo "Usage: $0 [all|macos|ios]"
        exit 1
        ;;
esac

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Compile each platform
for platform in "${PLATFORMS[@]}"; do
    case "$platform" in
        macos)
            compile_bridge "macos-arm64" "macos-arm64" \
                "arm64-apple-macos${MACOS_DEPLOYMENT_TARGET}" \
                "macosx" ""
            ;;
        ios-device)
            compile_bridge "ios-arm64" "ios-arm64" \
                "arm64-apple-ios${IOS_DEPLOYMENT_TARGET}" \
                "iphoneos" ""
            ;;
        ios-simulator)
            compile_bridge "ios-sim-arm64" "ios-sim-arm64" \
                "arm64-apple-ios${IOS_DEPLOYMENT_TARGET}-simulator" \
                "iphonesimulator" ""
            ;;
    esac
done

# Create XCFramework
echo ""
echo ">>> Creating VTKCore.xcframework ..."

XCFW_ARGS=()
for platform in "${PLATFORMS[@]}"; do
    case "$platform" in
        macos)
            XCFW_ARGS+=(-framework "$BUILD_DIR/macos-arm64/VTKCore.framework")
            ;;
        ios-device)
            XCFW_ARGS+=(-framework "$BUILD_DIR/ios-arm64/VTKCore.framework")
            ;;
        ios-simulator)
            XCFW_ARGS+=(-framework "$BUILD_DIR/ios-sim-arm64/VTKCore.framework")
            ;;
    esac
done

rm -rf "$OUTPUT_DIR/VTKCore.xcframework"
xcodebuild -create-xcframework \
    "${XCFW_ARGS[@]}" \
    -output "$OUTPUT_DIR/VTKCore.xcframework"

echo ""
echo "============================================"
echo "VTKCore.xcframework created successfully!"
echo "============================================"
echo ""
echo "Output: $OUTPUT_DIR/VTKCore.xcframework"
echo ""
ls -la "$OUTPUT_DIR/VTKCore.xcframework/"
echo ""

# Show total size
TOTAL_SIZE=$(du -sh "$OUTPUT_DIR/VTKCore.xcframework" | cut -f1)
echo "Total size: $TOTAL_SIZE"
echo ""
echo "Next steps:"
echo "  1. Reference from Package.swift (binaryTarget path)"
echo "  2. Or zip for distribution:"
echo "     cd $OUTPUT_DIR && zip -r VTKCore.xcframework.zip VTKCore.xcframework/"
echo "     swift package compute-checksum VTKCore.xcframework.zip"
echo "============================================"
