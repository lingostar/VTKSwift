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
#pragma mark - Molecular Visualization (macOS only)
// --------------------------------------------------------------------------

/// Load a PDB file and render the molecule using Ball-and-Stick style.
/// Only available on macOS (VTK chemistry libraries not built for iOS).
/// @param filePath Absolute path to a .pdb file.
/// @return YES if the molecule was loaded and rendered successfully.
- (BOOL)loadPDBFile:(NSString *)filePath;

// --------------------------------------------------------------------------
#pragma mark - Terrain Viewer (Urban Sunlight Simulator)
// --------------------------------------------------------------------------

/// Terrain color scheme identifiers.
typedef NS_ENUM(NSInteger, VTKTerrainColorScheme) {
    VTKTerrainColorSchemeElevation = 0,   // Blue-green-brown-white by height
    VTKTerrainColorSchemeSatellite,       // Earth tones (natural)
    VTKTerrainColorSchemeGrayscale,       // Grayscale for shadow analysis
};

/// Load terrain from a raw DEM file (16-bit signed little-endian heightfield).
/// @param path Absolute path to the .raw file.
/// @param width Number of columns in the heightfield grid.
/// @param height Number of rows in the heightfield grid.
/// @param spacingX Horizontal spacing per pixel in meters.
/// @param spacingY Vertical spacing per pixel in meters.
/// @return YES if the terrain was loaded and rendered.
- (BOOL)loadTerrainFromRawDEM:(NSString *)path
                        width:(NSInteger)width
                       height:(NSInteger)height
                     spacingX:(double)spacingX
                     spacingY:(double)spacingY;

/// Load built-in synthetic terrain as demo/fallback.
/// @param gridSize Grid resolution (e.g. 256 or 512).
/// @return YES on success.
- (BOOL)loadSyntheticTerrain:(NSInteger)gridSize;

/// Set elevation exaggeration factor (1.0 = true scale, 5.0 = 5x vertical).
- (void)setElevationExaggeration:(double)factor;

/// Set sun position from solar angles.
/// @param elevation Sun elevation in degrees (0=horizon, 90=zenith).
/// @param azimuth Sun azimuth in degrees (0=north, 90=east, 180=south, 270=west).
- (void)setSunElevation:(double)elevation azimuth:(double)azimuth;

/// Enable or disable shadow map rendering.
- (void)setShadowsEnabled:(BOOL)enabled;

/// Apply a terrain color scheme.
- (void)applyTerrainColorScheme:(VTKTerrainColorScheme)scheme;

/// Whether terrain data is loaded.
@property (nonatomic, readonly) BOOL isTerrainLoaded;

/// Current elevation exaggeration factor.
@property (nonatomic, readonly) double terrainElevationExaggeration;

/// Current sun elevation angle in degrees.
@property (nonatomic, readonly) double terrainSunElevation;

/// Current sun azimuth angle in degrees.
@property (nonatomic, readonly) double terrainSunAzimuth;

// --------------------------------------------------------------------------
#pragma mark - Measurement Support
// --------------------------------------------------------------------------

/// Pixel spacing in mm (X direction). 0 if not available.
@property (nonatomic, readonly) double pixelSpacingX;

/// Pixel spacing in mm (Y direction). 0 if not available.
@property (nonatomic, readonly) double pixelSpacingY;

/// Image dimensions (columns).
@property (nonatomic, readonly) NSInteger imageWidth;

/// Image dimensions (rows).
@property (nonatomic, readonly) NSInteger imageHeight;

// --------------------------------------------------------------------------
#pragma mark - Isosurface Export
// --------------------------------------------------------------------------

/// Extract an isosurface from loaded DICOM data and write a binary STL file.
/// A DICOM directory must be loaded first via loadDICOMDirectory:.
/// @param outputPath Absolute path where the binary STL will be written.
/// @param isoValue Isosurface threshold in Hounsfield Units (e.g., 300 for bone).
/// @param decimationRate Target triangle reduction ratio (0.0 = none, 0.9 = 90% removed).
/// @param smooth Whether to apply Laplacian smoothing (20 iterations).
/// @return YES if the STL was written successfully.
- (BOOL)exportIsosurfaceAsSTL:(NSString *)outputPath
                     isoValue:(double)isoValue
               decimationRate:(double)decimationRate
                    smoothing:(BOOL)smooth;

/// Extract an isosurface and write an OBJ file (with optional MTL for color).
/// @param outputPath Absolute path where the .obj will be written. A .mtl file is created alongside.
/// @param isoValue Isosurface threshold in Hounsfield Units.
/// @param decimationRate Target triangle reduction ratio (0.0 = none, 0.9 = 90% removed).
/// @param smooth Whether to apply Laplacian smoothing.
/// @return YES if the OBJ was written successfully.
- (BOOL)exportIsosurfaceAsOBJ:(NSString *)outputPath
                     isoValue:(double)isoValue
               decimationRate:(double)decimationRate
                    smoothing:(BOOL)smooth;

/// Extract isosurface mesh data as raw vertex/face arrays for use by Swift (USDZ conversion etc.).
/// @param isoValue Isosurface threshold in Hounsfield Units.
/// @param decimationRate Target triangle reduction ratio.
/// @param smooth Whether to apply Laplacian smoothing.
/// @param verticesOut On success, filled with packed float32 [x,y,z, x,y,z, ...] vertex positions.
/// @param normalsOut On success, filled with packed float32 [nx,ny,nz, ...] per-vertex normals.
/// @param facesOut On success, filled with packed uint32 [i0,i1,i2, i0,i1,i2, ...] triangle indices.
/// @return YES if mesh extraction succeeded.
- (BOOL)extractIsosurfaceMeshWithIsoValue:(double)isoValue
                           decimationRate:(double)decimationRate
                                smoothing:(BOOL)smooth
                                 vertices:(NSData * _Nullable * _Nonnull)verticesOut
                                  normals:(NSData * _Nullable * _Nonnull)normalsOut
                                    faces:(NSData * _Nullable * _Nonnull)facesOut;

/// Export multiple isosurfaces as a single OBJ file with separate groups and materials.
/// Each entry in isoValues gets its own named group and material color.
/// @param outputPath Absolute path where the .obj will be written.
/// @param isoValues NSArray of NSNumber (double) isosurface thresholds.
/// @param names NSArray of NSString group names (e.g. @[@"Bone", @"Skin"]).
/// @param decimationRate Target triangle reduction ratio.
/// @param smooth Whether to apply Laplacian smoothing.
/// @return YES if the multi-layer OBJ was written successfully.
- (BOOL)exportMultiIsosurfaceAsOBJ:(NSString *)outputPath
                         isoValues:(NSArray<NSNumber *> *)isoValues
                             names:(NSArray<NSString *> *)names
                    decimationRate:(double)decimationRate
                         smoothing:(BOOL)smooth;

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
