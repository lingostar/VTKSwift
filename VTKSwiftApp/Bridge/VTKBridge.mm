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

// DICOM support
#include "vtkDICOMImageReader.h"
#include "vtkImageViewer2.h"
#include "vtkImageData.h"
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

    // DICOM-specific
    vtkSmartPointer<vtkImageViewer2>                 imageViewer;
    vtkSmartPointer<vtkDICOMImageReader>             dicomReader;
    bool                                             isDICOMMode = false;
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
        if (_data->interactor) {
            _data->interactor->TerminateApp();
        }
        if (_data->renderWindow) {
            _data->renderWindow->Finalize();
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

    // Create image viewer
    _data->imageViewer = vtkSmartPointer<vtkImageViewer2>::New();
    _data->imageViewer->SetInputConnection(_data->dicomReader->GetOutputPort());
    _data->imageViewer->SetRenderWindow(_data->renderWindow);
    _data->imageViewer->SetRenderer(_data->renderer);
    _data->imageViewer->SetSliceOrientationToXY();

    // Set initial slice to middle
    int sliceMin = _data->imageViewer->GetSliceMin();
    int sliceMax = _data->imageViewer->GetSliceMax();
    _data->imageViewer->SetSlice((sliceMin + sliceMax) / 2);

    // Set default Window/Level for CT (bone window)
    _data->imageViewer->SetColorWindow(400);
    _data->imageViewer->SetColorLevel(40);

    // Switch interactor style to image mode
    vtkSmartPointer<vtkInteractorStyleImage> imageStyle =
        vtkSmartPointer<vtkInteractorStyleImage>::New();
    _data->interactor->SetInteractorStyle(imageStyle);

    // Set DICOM background to black
    _data->renderer->SetBackground(0.0, 0.0, 0.0);
    _data->renderer->SetGradientBackground(false);

    _data->isDICOMMode = true;

    NSLog(@"[VTKBridge] DICOM viewer ready: slices %d-%d, W/L: %.0f/%.0f",
          sliceMin, sliceMax,
          _data->imageViewer->GetColorWindow(),
          _data->imageViewer->GetColorLevel());

    return YES;
}

- (NSInteger)sliceCount {
    if (!_data->imageViewer) return 0;
    return _data->imageViewer->GetSliceMax() - _data->imageViewer->GetSliceMin() + 1;
}

- (NSInteger)currentSlice {
    if (!_data->imageViewer) return 0;
    return _data->imageViewer->GetSlice();
}

- (NSInteger)sliceMin {
    if (!_data->imageViewer) return 0;
    return _data->imageViewer->GetSliceMin();
}

- (NSInteger)sliceMax {
    if (!_data->imageViewer) return 0;
    return _data->imageViewer->GetSliceMax();
}

- (void)setSlice:(NSInteger)sliceIndex {
    if (!_data->imageViewer) return;
    int clamped = (int)sliceIndex;
    if (clamped < _data->imageViewer->GetSliceMin())
        clamped = _data->imageViewer->GetSliceMin();
    if (clamped > _data->imageViewer->GetSliceMax())
        clamped = _data->imageViewer->GetSliceMax();
    _data->imageViewer->SetSlice(clamped);
    [self render];
}

- (void)setWindow:(double)window level:(double)level {
    if (!_data->imageViewer) return;
    _data->imageViewer->SetColorWindow(window);
    _data->imageViewer->SetColorLevel(level);
    [self render];
}

- (double)currentWindow {
    if (!_data->imageViewer) return 0;
    return _data->imageViewer->GetColorWindow();
}

- (double)currentLevel {
    if (!_data->imageViewer) return 0;
    return _data->imageViewer->GetColorLevel();
}

// --------------------------------------------------------------------------
#pragma mark - Rendering
// --------------------------------------------------------------------------
- (void)render {
    if (_data->isDICOMMode && _data->imageViewer) {
        _data->imageViewer->Render();
    } else if (_data->renderWindow) {
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

    if (_data->isDICOMMode && _data->imageViewer) {
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
