//
//  VTKBridge.h
//  VTKSwiftApp
//
//  Objective-C bridge to VTK C++ library.
//  This header exposes only Objective-C types (no C++) so it can be imported by Swift.
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// Manages a VTK rendering pipeline.
/// Wraps VTK C++ objects behind an Objective-C interface for Swift interop.
@interface VTKBridge : NSObject

/// Initialize the VTK bridge with a target frame size.
/// @param frame The initial frame rectangle for the render view.
- (instancetype)initWithFrame:(CGRect)frame;

// --------------------------------------------------------------------------
#pragma mark - Primitives
// --------------------------------------------------------------------------

/// Set up the VTK rendering pipeline and add a sphere actor.
- (void)setupSphere;

// --------------------------------------------------------------------------
#pragma mark - DICOM
// --------------------------------------------------------------------------

/// Load a DICOM directory and set up image viewer pipeline.
/// @param path Absolute path to a directory containing DICOM files.
/// @return YES if loading succeeded, NO otherwise.
- (BOOL)loadDICOMDirectory:(NSString *)path;

/// Total number of slices in the loaded DICOM volume.
@property (nonatomic, readonly) NSInteger sliceCount;

/// Current slice index.
@property (nonatomic, readonly) NSInteger currentSlice;

/// Minimum slice index.
@property (nonatomic, readonly) NSInteger sliceMin;

/// Maximum slice index.
@property (nonatomic, readonly) NSInteger sliceMax;

/// Set the displayed slice index.
- (void)setSlice:(NSInteger)sliceIndex;

/// Set the Window/Level for DICOM display.
- (void)setWindow:(double)window level:(double)level;

/// Current window value.
@property (nonatomic, readonly) double currentWindow;

/// Current level value.
@property (nonatomic, readonly) double currentLevel;

// --------------------------------------------------------------------------
#pragma mark - Volume Rendering
// --------------------------------------------------------------------------

/// CT preset identifiers for volume rendering.
typedef NS_ENUM(NSInteger, VTKVolumePreset) {
    VTKVolumePresetSoftTissue = 0,
    VTKVolumePresetBone,
    VTKVolumePresetLung,
    VTKVolumePresetBrain,
    VTKVolumePresetAbdomen,
};

/// Load a DICOM directory and set up 3D volume rendering pipeline.
/// @param path Absolute path to a directory containing DICOM files.
/// @return YES if loading succeeded, NO otherwise.
- (BOOL)loadVolumeFromDICOMDirectory:(NSString *)path;

/// Apply a predefined CT volume preset (changes transfer functions).
- (void)applyVolumePreset:(VTKVolumePreset)preset;

/// Set volume opacity scale (0.0 ~ 2.0, default 1.0).
- (void)setVolumeOpacityScale:(double)scale;

/// Current volume preset.
@property (nonatomic, readonly) VTKVolumePreset currentVolumePreset;

/// Whether volume data is loaded.
@property (nonatomic, readonly) BOOL isVolumeLoaded;

// --------------------------------------------------------------------------
#pragma mark - Rendering
// --------------------------------------------------------------------------

/// Trigger a render pass.
- (void)render;

/// Resize the render window to match a new frame.
/// @param size The new size for the render window.
- (void)resizeTo:(CGSize)size;

#if TARGET_OS_IPHONE
/// Returns the UIView used for VTK rendering (iOS/iPadOS).
@property (nonatomic, readonly) UIView *renderView;
#else
/// Returns the NSView used for VTK rendering (macOS).
@property (nonatomic, readonly) NSView *renderView;
#endif

@end

NS_ASSUME_NONNULL_END
