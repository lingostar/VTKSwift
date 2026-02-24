//
//  VTKBridge.mm
//  VTKSwiftApp
//
//  Objective-C++ implementation that wraps VTK C++ rendering pipeline.
//

#import "VTKBridge.h"

// VTK headers
#include "vtkAutoInit.h"

// Initialize VTK rendering module factories — CRITICAL for OpenGL2 rendering.
VTK_MODULE_INIT(vtkRenderingOpenGL2);
VTK_MODULE_INIT(vtkInteractionStyle);

#include "vtkSmartPointer.h"
#include "vtkSphereSource.h"
#include "vtkPolyDataMapper.h"
#include "vtkActor.h"
#include "vtkProperty.h"
#include "vtkRenderer.h"
#include "vtkRenderWindow.h"
#include "vtkRenderWindowInteractor.h"
#include "vtkInteractorStyleTrackballCamera.h"
#include "vtkCamera.h"

// DICOM support (using primitives available on all platforms)
#include "vtkDICOMImageReader.h"
#include "vtkImageData.h"
#include "vtkImageActor.h"
#include "vtkImageMapper3D.h"
#include "vtkImageMapToColors.h"
#include "vtkWindowLevelLookupTable.h"
#include "vtkInteractorStyleImage.h"

// Volume rendering
#include "vtkSmartVolumeMapper.h"
#include "vtkVolumeProperty.h"
#include "vtkColorTransferFunction.h"
#include "vtkPiecewiseFunction.h"
#include "vtkVolume.h"

// Data preprocessing
#include "vtkImageThreshold.h"
#include "vtkImageResample.h"

#if TARGET_OS_IPHONE
#include "vtkIOSRenderWindow.h"
#include "vtkIOSRenderWindowInteractor.h"
#include <OpenGLES/ES3/gl.h>
#else
#include "vtkCocoaRenderWindow.h"
#include "vtkCocoaRenderWindowInteractor.h"
#include <OpenGL/gl3.h>
#endif

// --------------------------------------------------------------------------
// Private C++ data held by the bridge
// --------------------------------------------------------------------------
struct VTKBridgeData {
    vtkSmartPointer<vtkRenderer>                     renderer;
    vtkSmartPointer<vtkRenderWindow>                 renderWindow;
    vtkSmartPointer<vtkRenderWindowInteractor>       interactor;

    // DICOM-specific (manual pipeline replacing vtkImageViewer2)
    vtkSmartPointer<vtkDICOMImageReader>             dicomReader;
    vtkSmartPointer<vtkWindowLevelLookupTable>       dicomLUT;
    vtkSmartPointer<vtkImageMapToColors>             dicomColors;
    vtkSmartPointer<vtkImageActor>                   dicomActor;
    bool                                             isDICOMMode = false;
    int                                              dicomSliceMin = 0;
    int                                              dicomSliceMax = 0;
    int                                              dicomCurrentSlice = 0;
    double                                           dicomWindow = 400.0;
    double                                           dicomLevel = 40.0;

    // Volume rendering pipeline
    vtkSmartPointer<vtkDICOMImageReader>             volumeReader;
    vtkSmartPointer<vtkSmartVolumeMapper>            volumeMapper;
    vtkSmartPointer<vtkVolumeProperty>               volumeProperty;
    vtkSmartPointer<vtkColorTransferFunction>        volumeColorTF;
    vtkSmartPointer<vtkPiecewiseFunction>            volumeOpacityTF;
    vtkSmartPointer<vtkPiecewiseFunction>            volumeGradientTF;
    vtkSmartPointer<vtkVolume>                       volume;
    bool                                             isVolumeMode = false;
    VTKVolumePreset                                  volumePreset = VTKVolumePresetSoftTissue;
    double                                           volumeOpacityScale = 1.0;
};

// --------------------------------------------------------------------------
// Container view that auto-resizes VTK's internal GL view on layout changes.
// SwiftUI's NSViewRepresentable/UIViewRepresentable doesn't reliably call
// updateNSView on frame changes alone; this ensures VTK stays in sync.
// --------------------------------------------------------------------------
@class VTKBridge;

#if TARGET_OS_IPHONE
@interface VTKContainerView : UIView
@property (nonatomic, weak) VTKBridge *bridge;
@end

@implementation VTKContainerView
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.bridge && self.bounds.size.width > 0 && self.bounds.size.height > 0) {
        [self.bridge resizeTo:self.bounds.size];
    }
}
@end

#else
@interface VTKContainerView : NSView
@property (nonatomic, weak) VTKBridge *bridge;
@property (nonatomic) BOOL didInitialRender;
@end

@implementation VTKContainerView

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    // Trigger initial render once view is in a window (GL context available)
    if (self.window && self.bridge && !self.didInitialRender) {
        self.didInitialRender = YES;
        CGSize sz = self.bounds.size;
        if (sz.width > 0 && sz.height > 0) {
            [self.bridge resizeTo:sz];
        }
    }
}

- (void)layout {
    [super layout];
    if (self.bridge && self.bounds.size.width > 0 && self.bounds.size.height > 0) {
        [self.bridge resizeTo:self.bounds.size];
    }
}

- (BOOL)isFlipped {
    return YES;  // Match SwiftUI's coordinate system
}

@end
#endif

// --------------------------------------------------------------------------
#pragma mark - VTKBridge
// --------------------------------------------------------------------------
@implementation VTKBridge {
    VTKBridgeData *_data;
    CGRect _frame;
    VTKContainerView *_renderView;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    if (self) {
        _frame = frame;
        _data = new VTKBridgeData();
        [self setupRenderWindow];
    }
    return self;
}

- (void)dealloc {
    if (_data) {
        // Release volume rendering resources
        _data->volume = nullptr;
        _data->volumeMapper = nullptr;
        _data->volumeProperty = nullptr;
        _data->volumeColorTF = nullptr;
        _data->volumeOpacityTF = nullptr;
        _data->volumeGradientTF = nullptr;
        _data->volumeReader = nullptr;

        // Release DICOM resources first
        _data->dicomActor = nullptr;
        _data->dicomColors = nullptr;
        _data->dicomLUT = nullptr;
        _data->dicomReader = nullptr;

        // Detach renderer before finalize to avoid GL teardown crashes
        if (_data->renderWindow && _data->renderer) {
            _data->renderWindow->RemoveRenderer(_data->renderer);
        }
        if (_data->interactor) {
            _data->interactor->SetRenderWindow(nullptr);
            _data->interactor = nullptr;
        }
        _data->renderer = nullptr;
        if (_data->renderWindow) {
            _data->renderWindow->Finalize();
            _data->renderWindow = nullptr;
        }
        delete _data;
        _data = nullptr;
    }
}

// --------------------------------------------------------------------------
#pragma mark - Render Window Setup
// --------------------------------------------------------------------------
- (void)setupRenderWindow {
    // ---- Renderer ----
    _data->renderer = vtkSmartPointer<vtkRenderer>::New();
    _data->renderer->SetBackground(0.1, 0.1, 0.2);   // Dark blue bottom
    _data->renderer->SetBackground2(0.4, 0.5, 0.7);   // Lighter blue top
    _data->renderer->SetGradientBackground(true);

    int w = (int)_frame.size.width;
    int h = (int)_frame.size.height;
    if (w <= 0) w = 800;
    if (h <= 0) h = 600;

#if TARGET_OS_IPHONE
    // ---- iOS / iPadOS ----
    _renderView = [[VTKContainerView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    _renderView.bridge = self;

    vtkSmartPointer<vtkIOSRenderWindow> renWin =
        vtkSmartPointer<vtkIOSRenderWindow>::New();
    renWin->SetSize(w, h);
    renWin->SetParentId((__bridge void *)_renderView);
    _data->renderWindow = renWin;

    vtkSmartPointer<vtkIOSRenderWindowInteractor> iren =
        vtkSmartPointer<vtkIOSRenderWindowInteractor>::New();
    _data->interactor = iren;

#else
    // ---- macOS ----
    _renderView = [[VTKContainerView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    _renderView.bridge = self;
    _renderView.wantsLayer = YES;
    _renderView.autoresizesSubviews = YES;

    vtkSmartPointer<vtkCocoaRenderWindow> renWin =
        vtkSmartPointer<vtkCocoaRenderWindow>::New();
    renWin->SetSize(w, h);
    renWin->SetMultiSamples(0);
    renWin->SetParentId((__bridge void *)_renderView);
    _data->renderWindow = renWin;

    vtkSmartPointer<vtkCocoaRenderWindowInteractor> iren =
        vtkSmartPointer<vtkCocoaRenderWindowInteractor>::New();
    _data->interactor = iren;
#endif

    // Add renderer to render window
    _data->renderWindow->AddRenderer(_data->renderer);

    // Setup interactor style
    vtkSmartPointer<vtkInteractorStyleTrackballCamera> style =
        vtkSmartPointer<vtkInteractorStyleTrackballCamera>::New();
    _data->interactor->SetRenderWindow(_data->renderWindow);
    _data->interactor->SetInteractorStyle(style);
}

// --------------------------------------------------------------------------
#pragma mark - Sphere Setup (Primitives)
// --------------------------------------------------------------------------
- (void)setupSphere {
    // Create sphere geometry
    vtkSmartPointer<vtkSphereSource> sphere =
        vtkSmartPointer<vtkSphereSource>::New();
    sphere->SetCenter(0.0, 0.0, 0.0);
    sphere->SetRadius(1.0);
    sphere->SetThetaResolution(64);
    sphere->SetPhiResolution(64);
    sphere->Update();

    // Create mapper
    vtkSmartPointer<vtkPolyDataMapper> mapper =
        vtkSmartPointer<vtkPolyDataMapper>::New();
    mapper->SetInputConnection(sphere->GetOutputPort());

    // Create actor with red color and slight specularity
    vtkSmartPointer<vtkActor> actor =
        vtkSmartPointer<vtkActor>::New();
    actor->SetMapper(mapper);
    actor->GetProperty()->SetColor(0.9, 0.2, 0.2);       // Red
    actor->GetProperty()->SetSpecular(0.4);
    actor->GetProperty()->SetSpecularPower(30.0);
    actor->GetProperty()->SetDiffuse(0.8);
    actor->GetProperty()->SetAmbient(0.2);

    // Add actor to renderer
    _data->renderer->AddActor(actor);

    // Reset camera to show the sphere
    _data->renderer->ResetCamera();
    vtkCamera *cam = _data->renderer->GetActiveCamera();
    cam->Azimuth(30);
    cam->Elevation(20);
    _data->renderer->ResetCameraClippingRange();
}

// --------------------------------------------------------------------------
#pragma mark - DICOM Loading
// --------------------------------------------------------------------------
- (BOOL)loadDICOMDirectory:(NSString *)path {
    if (!path || path.length == 0) return NO;

    const char *dirPath = [path UTF8String];

    // Create DICOM reader
    _data->dicomReader = vtkSmartPointer<vtkDICOMImageReader>::New();
    _data->dicomReader->SetDirectoryName(dirPath);
    _data->dicomReader->Update();

    // Check if data was loaded
    vtkImageData *imageData = _data->dicomReader->GetOutput();
    if (!imageData || imageData->GetNumberOfPoints() == 0) {
        NSLog(@"[VTKBridge] Failed to load DICOM from: %@", path);
        _data->dicomReader = nullptr;
        return NO;
    }

    int *dims = imageData->GetDimensions();
    NSLog(@"[VTKBridge] DICOM loaded: %d x %d x %d slices", dims[0], dims[1], dims[2]);

    // Compute slice range from Z dimension
    _data->dicomSliceMin = 0;
    _data->dicomSliceMax = dims[2] - 1;
    _data->dicomCurrentSlice = (_data->dicomSliceMin + _data->dicomSliceMax) / 2;

    // Default Window/Level for CT
    _data->dicomWindow = 400.0;
    _data->dicomLevel = 40.0;

    // Build lookup table for window/level mapping
    _data->dicomLUT = vtkSmartPointer<vtkWindowLevelLookupTable>::New();
    [self updateLUT];

    // Map scalars through the lookup table
    _data->dicomColors = vtkSmartPointer<vtkImageMapToColors>::New();
    _data->dicomColors->SetLookupTable(_data->dicomLUT);
    _data->dicomColors->SetInputConnection(_data->dicomReader->GetOutputPort());
    _data->dicomColors->Update();

    // Create image actor
    _data->dicomActor = vtkSmartPointer<vtkImageActor>::New();
    _data->dicomActor->GetMapper()->SetInputConnection(_data->dicomColors->GetOutputPort());

    // Set display extent to show the initial slice (XY orientation)
    _data->dicomActor->SetDisplayExtent(
        imageData->GetExtent()[0], imageData->GetExtent()[1],  // X range
        imageData->GetExtent()[2], imageData->GetExtent()[3],  // Y range
        _data->dicomCurrentSlice, _data->dicomCurrentSlice     // Z = single slice
    );

    _data->renderer->AddActor(_data->dicomActor);

    // Switch interactor style to image mode
    vtkSmartPointer<vtkInteractorStyleImage> imageStyle =
        vtkSmartPointer<vtkInteractorStyleImage>::New();
    _data->interactor->SetInteractorStyle(imageStyle);

    // Set DICOM background to black
    _data->renderer->SetBackground(0.0, 0.0, 0.0);
    _data->renderer->SetGradientBackground(false);
    _data->renderer->ResetCamera();

    _data->isDICOMMode = true;

    NSLog(@"[VTKBridge] DICOM viewer ready: slices %d-%d, W/L: %.0f/%.0f",
          _data->dicomSliceMin, _data->dicomSliceMax,
          _data->dicomWindow, _data->dicomLevel);

    return YES;
}

- (void)updateLUT {
    if (!_data->dicomLUT) return;
    _data->dicomLUT->SetWindow(_data->dicomWindow);
    _data->dicomLUT->SetLevel(_data->dicomLevel);
    _data->dicomLUT->Build();
}

- (NSInteger)sliceCount {
    if (!_data->isDICOMMode) return 0;
    return _data->dicomSliceMax - _data->dicomSliceMin + 1;
}

- (NSInteger)currentSlice {
    if (!_data->isDICOMMode) return 0;
    return _data->dicomCurrentSlice;
}

- (NSInteger)sliceMin {
    return _data->dicomSliceMin;
}

- (NSInteger)sliceMax {
    return _data->dicomSliceMax;
}

- (void)setSlice:(NSInteger)sliceIndex {
    if (!_data->isDICOMMode || !_data->dicomActor) return;
    int clamped = (int)sliceIndex;
    if (clamped < _data->dicomSliceMin) clamped = _data->dicomSliceMin;
    if (clamped > _data->dicomSliceMax) clamped = _data->dicomSliceMax;
    _data->dicomCurrentSlice = clamped;

    // Update display extent to show the new slice
    vtkImageData *imageData = _data->dicomReader->GetOutput();
    if (imageData) {
        _data->dicomActor->SetDisplayExtent(
            imageData->GetExtent()[0], imageData->GetExtent()[1],
            imageData->GetExtent()[2], imageData->GetExtent()[3],
            clamped, clamped
        );
    }
    [self render];
}

- (void)setWindow:(double)window level:(double)level {
    if (!_data->isDICOMMode) return;
    _data->dicomWindow = window;
    _data->dicomLevel = level;
    [self updateLUT];
    if (_data->dicomColors) {
        _data->dicomColors->Update();
    }
    [self render];
}

- (double)currentWindow {
    return _data->dicomWindow;
}

- (double)currentLevel {
    return _data->dicomLevel;
}

// --------------------------------------------------------------------------
#pragma mark - Volume Rendering
// --------------------------------------------------------------------------
- (BOOL)loadVolumeFromDICOMDirectory:(NSString *)path {
    if (!path || path.length == 0) return NO;

    const char *dirPath = [path UTF8String];

    // Create DICOM reader
    _data->volumeReader = vtkSmartPointer<vtkDICOMImageReader>::New();
    _data->volumeReader->SetDirectoryName(dirPath);
    _data->volumeReader->Update();

    vtkImageData *imageData = _data->volumeReader->GetOutput();
    if (!imageData || imageData->GetNumberOfPoints() == 0) {
        NSLog(@"[VTKBridge] Failed to load volume DICOM from: %@", path);
        _data->volumeReader = nullptr;
        return NO;
    }

    int *dims = imageData->GetDimensions();
    double *spacing = imageData->GetSpacing();
    NSLog(@"[VTKBridge] Volume loaded: %d x %d x %d, spacing: %.2f x %.2f x %.2f",
          dims[0], dims[1], dims[2], spacing[0], spacing[1], spacing[2]);

    // --- Data Preprocessing ---
    // 1. Threshold: clamp air (HU < -1000) to -1000
    vtkSmartPointer<vtkImageThreshold> threshold =
        vtkSmartPointer<vtkImageThreshold>::New();
    threshold->SetInputConnection(_data->volumeReader->GetOutputPort());
    threshold->ThresholdByLower(-1000.0);
    threshold->SetInValue(-1000.0);
    threshold->ReplaceInOn();
    threshold->ReplaceOutOff();
    threshold->Update();

    // 2. Resample for iPad memory constraints (if volume > 256^3)
    vtkSmartPointer<vtkImageResample> resample;
    vtkAlgorithmOutput *pipelineOutput = threshold->GetOutputPort();

    long totalVoxels = (long)dims[0] * dims[1] * dims[2];
    const long maxVoxels = 256L * 256 * 256; // ~16M voxels

    if (totalVoxels > maxVoxels) {
        double factor = pow((double)maxVoxels / totalVoxels, 1.0 / 3.0);
        NSLog(@"[VTKBridge] Resampling volume by factor %.2f (voxels: %ld > %ld)",
              factor, totalVoxels, maxVoxels);

        resample = vtkSmartPointer<vtkImageResample>::New();
        resample->SetInputConnection(threshold->GetOutputPort());
        resample->SetAxisMagnificationFactor(0, factor);
        resample->SetAxisMagnificationFactor(1, factor);
        resample->SetAxisMagnificationFactor(2, factor);
        resample->SetInterpolationModeToLinear();
        resample->Update();
        pipelineOutput = resample->GetOutputPort();
    }

    // --- Volume Mapper ---
    _data->volumeMapper = vtkSmartPointer<vtkSmartVolumeMapper>::New();
    _data->volumeMapper->SetInputConnection(pipelineOutput);
    _data->volumeMapper->SetRequestedRenderModeToGPU();

    // --- Transfer Functions ---
    _data->volumeColorTF = vtkSmartPointer<vtkColorTransferFunction>::New();
    _data->volumeOpacityTF = vtkSmartPointer<vtkPiecewiseFunction>::New();
    _data->volumeGradientTF = vtkSmartPointer<vtkPiecewiseFunction>::New();

    // --- Volume Property ---
    _data->volumeProperty = vtkSmartPointer<vtkVolumeProperty>::New();
    _data->volumeProperty->SetColor(_data->volumeColorTF);
    _data->volumeProperty->SetScalarOpacity(_data->volumeOpacityTF);
    _data->volumeProperty->SetGradientOpacity(_data->volumeGradientTF);
    _data->volumeProperty->SetInterpolationTypeToLinear();
    _data->volumeProperty->ShadeOn();
    _data->volumeProperty->SetAmbient(0.2);
    _data->volumeProperty->SetDiffuse(0.7);
    _data->volumeProperty->SetSpecular(0.3);
    _data->volumeProperty->SetSpecularPower(20.0);

    // --- Volume Actor ---
    _data->volume = vtkSmartPointer<vtkVolume>::New();
    _data->volume->SetMapper(_data->volumeMapper);
    _data->volume->SetProperty(_data->volumeProperty);

    // Apply default preset
    _data->volumePreset = VTKVolumePresetSoftTissue;
    [self applyVolumePreset:_data->volumePreset];

    // Setup scene
    _data->renderer->RemoveAllViewProps();
    _data->renderer->AddVolume(_data->volume);
    _data->renderer->SetBackground(0.0, 0.0, 0.0);
    _data->renderer->SetGradientBackground(false);
    _data->renderer->ResetCamera();

    // Switch to trackball for 3D interaction
    vtkSmartPointer<vtkInteractorStyleTrackballCamera> style =
        vtkSmartPointer<vtkInteractorStyleTrackballCamera>::New();
    _data->interactor->SetInteractorStyle(style);

    _data->isVolumeMode = true;

    NSLog(@"[VTKBridge] Volume rendering ready (preset: SoftTissue)");
    return YES;
}

- (void)applyVolumePreset:(VTKVolumePreset)preset {
    if (!_data->volumeColorTF || !_data->volumeOpacityTF) return;

    _data->volumePreset = preset;
    _data->volumeColorTF->RemoveAllPoints();
    _data->volumeOpacityTF->RemoveAllPoints();
    _data->volumeGradientTF->RemoveAllPoints();

    double s = _data->volumeOpacityScale;

    switch (preset) {
        case VTKVolumePresetSoftTissue: {
            // W:400 L:40  → range -160 ~ 240
            _data->volumeColorTF->AddRGBPoint(-1000, 0.0, 0.0, 0.0);
            _data->volumeColorTF->AddRGBPoint(-160,  0.0, 0.0, 0.0);
            _data->volumeColorTF->AddRGBPoint(-60,   0.55, 0.25, 0.15);
            _data->volumeColorTF->AddRGBPoint(40,    0.88, 0.60, 0.50);
            _data->volumeColorTF->AddRGBPoint(240,   1.0, 0.94, 0.90);
            _data->volumeColorTF->AddRGBPoint(3000,  1.0, 1.0, 1.0);

            _data->volumeOpacityTF->AddPoint(-1000, 0.0);
            _data->volumeOpacityTF->AddPoint(-160,  0.0);
            _data->volumeOpacityTF->AddPoint(-60,   0.0);
            _data->volumeOpacityTF->AddPoint(40,    0.15 * s);
            _data->volumeOpacityTF->AddPoint(240,   0.40 * s);
            _data->volumeOpacityTF->AddPoint(3000,  0.60 * s);
            break;
        }
        case VTKVolumePresetBone: {
            // W:2000 L:300  → range -700 ~ 1300
            _data->volumeColorTF->AddRGBPoint(-1000, 0.0, 0.0, 0.0);
            _data->volumeColorTF->AddRGBPoint(-700,  0.0, 0.0, 0.0);
            _data->volumeColorTF->AddRGBPoint(100,   0.55, 0.25, 0.15);
            _data->volumeColorTF->AddRGBPoint(300,   0.90, 0.75, 0.60);
            _data->volumeColorTF->AddRGBPoint(800,   1.0, 0.95, 0.85);
            _data->volumeColorTF->AddRGBPoint(1300,  1.0, 1.0, 1.0);
            _data->volumeColorTF->AddRGBPoint(3000,  1.0, 1.0, 1.0);

            _data->volumeOpacityTF->AddPoint(-1000, 0.0);
            _data->volumeOpacityTF->AddPoint(100,   0.0);
            _data->volumeOpacityTF->AddPoint(200,   0.02 * s);
            _data->volumeOpacityTF->AddPoint(300,   0.10 * s);
            _data->volumeOpacityTF->AddPoint(800,   0.60 * s);
            _data->volumeOpacityTF->AddPoint(1300,  0.85 * s);
            _data->volumeOpacityTF->AddPoint(3000,  0.90 * s);
            break;
        }
        case VTKVolumePresetLung: {
            // W:1500 L:-600  → range -1350 ~ 150
            _data->volumeColorTF->AddRGBPoint(-1350, 0.0, 0.0, 0.0);
            _data->volumeColorTF->AddRGBPoint(-1000, 0.15, 0.15, 0.25);
            _data->volumeColorTF->AddRGBPoint(-600,  0.40, 0.50, 0.70);
            _data->volumeColorTF->AddRGBPoint(-300,  0.65, 0.70, 0.80);
            _data->volumeColorTF->AddRGBPoint(0,     0.85, 0.55, 0.40);
            _data->volumeColorTF->AddRGBPoint(150,   1.0, 1.0, 1.0);
            _data->volumeColorTF->AddRGBPoint(3000,  1.0, 1.0, 1.0);

            _data->volumeOpacityTF->AddPoint(-1350, 0.0);
            _data->volumeOpacityTF->AddPoint(-1000, 0.0);
            _data->volumeOpacityTF->AddPoint(-900,  0.01 * s);
            _data->volumeOpacityTF->AddPoint(-600,  0.05 * s);
            _data->volumeOpacityTF->AddPoint(-300,  0.15 * s);
            _data->volumeOpacityTF->AddPoint(0,     0.35 * s);
            _data->volumeOpacityTF->AddPoint(150,   0.50 * s);
            _data->volumeOpacityTF->AddPoint(3000,  0.60 * s);
            break;
        }
        case VTKVolumePresetBrain: {
            // W:80 L:40  → range 0 ~ 80
            _data->volumeColorTF->AddRGBPoint(-1000, 0.0, 0.0, 0.0);
            _data->volumeColorTF->AddRGBPoint(0,     0.0, 0.0, 0.0);
            _data->volumeColorTF->AddRGBPoint(20,    0.30, 0.30, 0.35);
            _data->volumeColorTF->AddRGBPoint(40,    0.65, 0.60, 0.62);
            _data->volumeColorTF->AddRGBPoint(60,    0.85, 0.80, 0.78);
            _data->volumeColorTF->AddRGBPoint(80,    1.0, 0.95, 0.90);
            _data->volumeColorTF->AddRGBPoint(3000,  1.0, 1.0, 1.0);

            _data->volumeOpacityTF->AddPoint(-1000, 0.0);
            _data->volumeOpacityTF->AddPoint(0,     0.0);
            _data->volumeOpacityTF->AddPoint(20,    0.05 * s);
            _data->volumeOpacityTF->AddPoint(40,    0.25 * s);
            _data->volumeOpacityTF->AddPoint(60,    0.50 * s);
            _data->volumeOpacityTF->AddPoint(80,    0.70 * s);
            _data->volumeOpacityTF->AddPoint(3000,  0.75 * s);
            break;
        }
        case VTKVolumePresetAbdomen: {
            // W:400 L:50  → range -150 ~ 250
            _data->volumeColorTF->AddRGBPoint(-1000, 0.0, 0.0, 0.0);
            _data->volumeColorTF->AddRGBPoint(-150,  0.0, 0.0, 0.0);
            _data->volumeColorTF->AddRGBPoint(-50,   0.45, 0.25, 0.20);
            _data->volumeColorTF->AddRGBPoint(50,    0.80, 0.55, 0.40);
            _data->volumeColorTF->AddRGBPoint(150,   0.90, 0.75, 0.60);
            _data->volumeColorTF->AddRGBPoint(250,   1.0, 0.90, 0.80);
            _data->volumeColorTF->AddRGBPoint(3000,  1.0, 1.0, 1.0);

            _data->volumeOpacityTF->AddPoint(-1000, 0.0);
            _data->volumeOpacityTF->AddPoint(-150,  0.0);
            _data->volumeOpacityTF->AddPoint(-50,   0.0);
            _data->volumeOpacityTF->AddPoint(50,    0.15 * s);
            _data->volumeOpacityTF->AddPoint(150,   0.35 * s);
            _data->volumeOpacityTF->AddPoint(250,   0.55 * s);
            _data->volumeOpacityTF->AddPoint(3000,  0.65 * s);
            break;
        }
    }

    // Gradient opacity (edge enhancement — shared across presets)
    _data->volumeGradientTF->AddPoint(0,   0.0);
    _data->volumeGradientTF->AddPoint(20,  0.2);
    _data->volumeGradientTF->AddPoint(100, 1.0);

    if (_data->isVolumeMode) {
        [self render];
    }
}

- (void)setVolumeOpacityScale:(double)scale {
    if (scale < 0.0) scale = 0.0;
    if (scale > 2.0) scale = 2.0;
    _data->volumeOpacityScale = scale;
    // Re-apply preset with new scale
    [self applyVolumePreset:_data->volumePreset];
}

- (VTKVolumePreset)currentVolumePreset {
    return _data->volumePreset;
}

- (BOOL)isVolumeLoaded {
    return _data->isVolumeMode;
}

// --------------------------------------------------------------------------
#pragma mark - Rendering
// --------------------------------------------------------------------------
- (void)render {
    if (_data->renderWindow) {
        _data->renderWindow->Render();
    }

    // Debug: Print OpenGL context information after first render
    static BOOL didLogOnce = NO;
    if (!didLogOnce) {
        didLogOnce = YES;
        const char *version = (const char *)glGetString(GL_VERSION);
        const char *renderer = (const char *)glGetString(GL_RENDERER);
        const char *glslVersion = (const char *)glGetString(GL_SHADING_LANGUAGE_VERSION);
        NSLog(@"[VTKBridge] GL_VERSION: %s", version ?: "(null)");
        NSLog(@"[VTKBridge] GL_RENDERER: %s", renderer ?: "(null)");
        NSLog(@"[VTKBridge] GL_SHADING_LANGUAGE_VERSION: %s", glslVersion ?: "(null)");
        NSLog(@"[VTKBridge] RenderWindow class: %s",
              _data->renderWindow->GetClassName());
#if TARGET_OS_IPHONE
        NSLog(@"[VTKBridge] Build target: iOS");
#else
        NSLog(@"[VTKBridge] Build target: macOS");
#endif
    }
}

- (void)resizeTo:(CGSize)size {
    if (!_data->renderWindow || size.width <= 0 || size.height <= 0) return;

    int w = (int)size.width;
    int h = (int)size.height;

    _data->renderWindow->SetSize(w, h);

    // Render first to ensure VTK creates its internal GL view
    _data->renderWindow->Render();

#if !TARGET_OS_IPHONE
    // Now the GL view exists — resize it and set autoresizing so it tracks the parent.
    vtkCocoaRenderWindow *cocoaWin =
        vtkCocoaRenderWindow::SafeDownCast(_data->renderWindow);
    if (cocoaWin) {
        void *winId = cocoaWin->GetWindowId();
        if (winId) {
            NSView *glView = (__bridge NSView *)winId;
            [glView setFrame:NSMakeRect(0, 0, size.width, size.height)];
            glView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        }
    }
#endif

    if (_data->isDICOMMode || _data->isVolumeMode) {
        _data->renderer->ResetCamera();
    } else {
        _data->renderer->ResetCameraClippingRange();
    }

    // Render again at the correct size
    _data->renderWindow->Render();
}

// --------------------------------------------------------------------------
#pragma mark - View Access
// --------------------------------------------------------------------------
#if TARGET_OS_IPHONE
- (UIView *)renderView {
    return _renderView;
}
#else
- (NSView *)renderView {
    return _renderView;
}
#endif

@end
