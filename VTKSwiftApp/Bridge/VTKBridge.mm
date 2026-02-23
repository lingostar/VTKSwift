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
// Without these, vtkPolyDataMapper::New() creates a base class that cannot render.
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

#if TARGET_OS_IPHONE
#include "vtkIOSRenderWindow.h"
#include "vtkIOSRenderWindowInteractor.h"
#else
#include "vtkCocoaRenderWindow.h"
#include "vtkCocoaRenderWindowInteractor.h"
#endif

// --------------------------------------------------------------------------
// Private C++ data held by the bridge
// --------------------------------------------------------------------------
struct VTKBridgeData {
    vtkSmartPointer<vtkRenderer>                     renderer;
    vtkSmartPointer<vtkRenderWindow>                 renderWindow;
    vtkSmartPointer<vtkRenderWindowInteractor>       interactor;
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
    // Use SetParentId — VTK creates its own GL view as a subview of _renderView
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
    // Use SetParentId — VTK creates its vtkCocoaView (OpenGL) as a subview
    // of _renderView.  Do NOT use SetWindowId (expects vtkCocoaView, not NSView)
    // or SetRootWindow (window is nil at this point).
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
#pragma mark - Sphere Setup
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
#pragma mark - Rendering
// --------------------------------------------------------------------------
- (void)render {
    if (_data->renderWindow) {
        _data->renderWindow->Render();
    }
}

- (void)resizeTo:(CGSize)size {
    if (!_data->renderWindow || size.width <= 0 || size.height <= 0) return;

    _data->renderWindow->SetSize((int)size.width, (int)size.height);

#if !TARGET_OS_IPHONE
    // VTK's internal vtkCocoaView does not auto-resize with our container.
    // Manually resize it to match.
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

    _data->renderer->ResetCameraClippingRange();
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
