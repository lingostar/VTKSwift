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
};

// --------------------------------------------------------------------------
#pragma mark - VTKBridge
// --------------------------------------------------------------------------
@implementation VTKBridge {
    VTKBridgeData *_data;
    CGRect _frame;

#if TARGET_OS_IPHONE
    UIView *_renderView;
#else
    NSView *_renderView;
#endif
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
    _renderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];

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
    _renderView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    _renderView.wantsLayer = YES;

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

    _data->renderWindow->SetSize((int)size.width, (int)size.height);

#if !TARGET_OS_IPHONE
    // VTK's internal vtkCocoaView does not auto-resize with our container.
    vtkCocoaRenderWindow *cocoaWin =
        vtkCocoaRenderWindow::SafeDownCast(_data->renderWindow);
    if (cocoaWin) {
        void *winId = cocoaWin->GetWindowId();
        if (winId) {
            NSView *glView = (__bridge NSView *)winId;
            [glView setFrame:NSMakeRect(0, 0, size.width, size.height)];
        }
    }
#endif

    if (_data->isDICOMMode) {
        _data->renderer->ResetCamera();
    } else {
        _data->renderer->ResetCameraClippingRange();
    }
    [self render];
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
