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
VTK_MODULE_INIT(vtkRenderingVolumeOpenGL2);
VTK_MODULE_INIT(vtkInteractionStyle);

#include "vtkSmartPointer.h"
#include "vtkCommand.h"
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
#include "vtkImageCast.h"

// Molecular visualization (macOS only — chemistry libs not built for iOS)
#if !TARGET_OS_IPHONE
#include "vtkPDBReader.h"
#include "vtkMoleculeMapper.h"
#include "vtkMolecule.h"
#endif

// Isosurface extraction (for USDZ export)
#include "vtkMarchingCubes.h"
#include "vtkSmoothPolyDataFilter.h"
#include "vtkDecimatePro.h"
#include "vtkPolyData.h"
#include "vtkPointData.h"
#include "vtkCellArray.h"
#include "vtkPoints.h"
#include "vtkCell.h"
#include "vtkTriangleFilter.h"

// Terrain rendering
#include "vtkImageDataGeometryFilter.h"
#include "vtkWarpScalar.h"
#include "vtkPolyDataNormals.h"
#include "vtkLookupTable.h"
#include "vtkLight.h"
#include "vtkPlaneSource.h"
// Shadow rendering
#include "vtkShadowMapPass.h"
#include "vtkShadowMapBakerPass.h"
#include "vtkSequencePass.h"
#include "vtkRenderPassCollection.h"
#include "vtkCameraPass.h"
#include "vtkOpaquePass.h"
#include "vtkLightsPass.h"
#include <cmath>

#if TARGET_OS_IPHONE
#include "vtkIOSRenderWindow.h"
#include "vtkIOSRenderWindowInteractor.h"
#include "vtkOpenGLRenderWindow.h"
#include "vtkOpenGLState.h"
#include "vtkOpenGLFramebufferObject.h"
#include "vtkOutputWindow.h"
#include <OpenGLES/ES3/gl.h>
#import <GLKit/GLKit.h>
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

    // Slice plane indicator (sync with DICOM viewer)
    // Wireframe outline (thin yellow border) + corner brackets (thick yellow L-shapes)
    vtkSmartPointer<vtkPlaneSource>                  slicePlaneSource;
    vtkSmartPointer<vtkPolyDataMapper>               slicePlaneMapper;
    vtkSmartPointer<vtkActor>                        slicePlaneActor;
    vtkSmartPointer<vtkPolyData>                     slicePlaneCornerData;
    vtkSmartPointer<vtkPolyDataMapper>               slicePlaneCornerMapper;
    vtkSmartPointer<vtkActor>                        slicePlaneCornerActor;
    bool                                             slicePlaneVisible = false;
    double                                           slicePlaneFraction = 0.5;

    // Terrain rendering pipeline
    vtkSmartPointer<vtkImageData>                terrainImageData;
    vtkSmartPointer<vtkImageDataGeometryFilter>  terrainGeomFilter;
    vtkSmartPointer<vtkWarpScalar>               terrainWarp;
    vtkSmartPointer<vtkPolyDataNormals>          terrainNormals;
    vtkSmartPointer<vtkLookupTable>              terrainLUT;
    vtkSmartPointer<vtkPolyDataMapper>           terrainMapper;
    vtkSmartPointer<vtkActor>                    terrainActor;
    vtkSmartPointer<vtkLight>                    sunLight;
    vtkSmartPointer<vtkActor>                    seaPlaneActor;
    vtkSmartPointer<vtkShadowMapPass>            shadowPass;
    vtkSmartPointer<vtkShadowMapBakerPass>       shadowBaker;
    bool    isTerrainMode = false;
    bool    shadowsEnabled = true;
    double  terrainExaggeration = 2.0;
    double  terrainSunElevation = 45.0;
    double  terrainSunAzimuth = 180.0;
    double  terrainMinElev = 0, terrainMaxElev = 1000;
    VTKTerrainColorScheme terrainColorScheme = VTKTerrainColorSchemeElevation;

    // (Custom blit removed — VTK's BlitToCurrent handles the blit natively.)
};

// --------------------------------------------------------------------------
// Container view that auto-resizes VTK's internal GL view on layout changes.
// SwiftUI's NSViewRepresentable/UIViewRepresentable doesn't reliably call
// updateNSView on frame changes alone; this ensures VTK stays in sync.
// --------------------------------------------------------------------------
@class VTKBridge;

// Forward-declare internal method used by VTKContainerView's touch handling
@interface VTKBridge ()
- (vtkRenderWindowInteractor *)vtkInteractor;
@end

#if TARGET_OS_IPHONE
@interface VTKContainerView : UIView <GLKViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, weak) VTKBridge *bridge;
@property (nonatomic) BOOL didInitialRender;
@property (nonatomic, strong) EAGLContext *eaglContext;
@property (nonatomic, strong) GLKView *glkView;
/// Tracks whether a rotate (left-button) interaction is in progress.
@property (nonatomic) BOOL isRotating;
/// Tracks whether a pan (middle-button) interaction is in progress.
@property (nonatomic) BOOL isPanning;
@end

@implementation VTKContainerView

- (void)setupGLContext {
    if (self.eaglContext) return; // already set up

    // Create OpenGL ES 3.0 context
    self.eaglContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!self.eaglContext) {
        NSLog(@"[VTKBridge] Failed to create EAGLContext with ES3, trying ES2...");
        self.eaglContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    }
    if (!self.eaglContext) {
        NSLog(@"[VTKBridge] ERROR: Could not create any EAGLContext!");
        return;
    }

    // Make context current so VTK can use it
    [EAGLContext setCurrentContext:self.eaglContext];

    // Create GLKView as rendering surface with this view as delegate.
    // When [glkView display] is called, GLKView:
    //   1) binds its own FBO (renderbuffer backed by CAEAGLLayer)
    //   2) calls delegate's glkView:drawInRect:
    //   3) presents the renderbuffer to screen
    self.glkView = [[GLKView alloc] initWithFrame:self.bounds context:self.eaglContext];
    self.glkView.delegate = self;
    self.glkView.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    self.glkView.drawableColorFormat = GLKViewDrawableColorFormatRGBA8888;
    self.glkView.drawableStencilFormat = GLKViewDrawableStencilFormatNone;
    self.glkView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.glkView.enableSetNeedsDisplay = NO; // We drive rendering manually via display
    self.glkView.userInteractionEnabled = NO;  // Let touches pass through to VTKContainerView
    self.multipleTouchEnabled = YES;            // Enable multi-touch for pinch/pan
    [self addSubview:self.glkView];

    // Wire up gesture recognizers for 3D interaction (rotate/pan/zoom)
    [self setupGestureRecognizers];

    NSLog(@"[VTKBridge] EAGLContext created (ES%d), GLKView configured",
          (int)self.eaglContext.API);
}

/// GLKViewDelegate — called by [glkView display].
/// At this point, GLKView has already bound its internal FBO.
/// VTK's BlitToCurrent mode will blit into this FBO.
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    if (self.bridge) {
        [self.bridge performVTKRender];
    }
}

- (void)makeGLContextCurrent {
    if (self.eaglContext && [EAGLContext currentContext] != self.eaglContext) {
        [EAGLContext setCurrentContext:self.eaglContext];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && self.bridge && !self.didInitialRender) {
        self.didInitialRender = YES;
        __weak VTKContainerView *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            VTKContainerView *strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.bridge) return;
            [strongSelf makeGLContextCurrent];
            CGSize sz = strongSelf.bounds.size;
            if (sz.width > 0 && sz.height > 0) {
                [strongSelf.bridge resizeTo:sz];
            }
        });
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.glkView) {
        self.glkView.frame = self.bounds;
    }
    if (self.window && self.bridge && self.bounds.size.width > 0 && self.bounds.size.height > 0) {
        [self makeGLContextCurrent];
        [self.bridge resizeTo:self.bounds.size];
    }
}

// --------------------------------------------------------------------------
#pragma mark - Gesture Recognizers → VTK Interactor
// --------------------------------------------------------------------------
// UIGestureRecognizers are used instead of raw touchesBegan/Moved/Ended so
// that UIKit's gesture-conflict resolution keeps navigation back-swipe,
// parent ScrollViews, and other system gestures from stealing touches that
// belong to the volume interaction.
//
// Mapping:
//   1-finger pan  → rotate  (VTK LeftButton drag = trackball rotate)
//   2-finger pan  → pan     (VTK MiddleButton drag = camera translate)
//   pinch         → zoom    (VTK MouseWheel events)

- (void)setupGestureRecognizers {
    // --- 1-finger rotate ---
    UIPanGestureRecognizer *rotatePan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleRotate:)];
    rotatePan.minimumNumberOfTouches = 1;
    rotatePan.maximumNumberOfTouches = 1;
    rotatePan.delegate = self;
    [self addGestureRecognizer:rotatePan];

    // --- 2-finger pan ---
    UIPanGestureRecognizer *twoPan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    twoPan.minimumNumberOfTouches = 2;
    twoPan.maximumNumberOfTouches = 2;
    twoPan.delegate = self;
    [self addGestureRecognizer:twoPan];

    // --- Pinch zoom ---
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePinch:)];
    pinch.delegate = self;
    [self addGestureRecognizer:pinch];
}

/// Convert a UIKit point (origin top-left, points) to VTK coords (origin bottom-left, pixels).
- (CGPoint)vtkPointFromUIPoint:(CGPoint)pt {
    CGFloat scale = self.glkView.contentScaleFactor;
    CGFloat viewH = self.glkView.bounds.size.height;
    return CGPointMake(pt.x * scale, (viewH - pt.y) * scale);
}

- (vtkRenderWindowInteractor *)vtkInteractor {
    if (!self.bridge) return nullptr;
    return [self.bridge vtkInteractor];
}

// --- Rotate (1-finger drag → VTK left-button trackball) ---
- (void)handleRotate:(UIPanGestureRecognizer *)gr {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;

    CGPoint uiPt = [gr locationInView:self.glkView];
    CGPoint pt = [self vtkPointFromUIPoint:uiPt];

    switch (gr.state) {
        case UIGestureRecognizerStateBegan:
            iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
            iren->InvokeEvent(vtkCommand::LeftButtonPressEvent, nullptr);
            self.isRotating = YES;
            break;
        case UIGestureRecognizerStateChanged:
            iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
            iren->InvokeEvent(vtkCommand::MouseMoveEvent, nullptr);
            [self.bridge render];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
            iren->InvokeEvent(vtkCommand::LeftButtonReleaseEvent, nullptr);
            self.isRotating = NO;
            [self.bridge render];
            break;
        default:
            break;
    }
}

// --- Pan (2-finger drag → VTK middle-button translate) ---
- (void)handlePan:(UIPanGestureRecognizer *)gr {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;

    CGPoint uiPt = [gr locationInView:self.glkView];
    CGPoint pt = [self vtkPointFromUIPoint:uiPt];

    switch (gr.state) {
        case UIGestureRecognizerStateBegan:
            // End any in-progress rotate so they don't overlap
            if (self.isRotating) {
                iren->InvokeEvent(vtkCommand::LeftButtonReleaseEvent, nullptr);
                self.isRotating = NO;
            }
            iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
            iren->InvokeEvent(vtkCommand::MiddleButtonPressEvent, nullptr);
            self.isPanning = YES;
            break;
        case UIGestureRecognizerStateChanged:
            iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
            iren->InvokeEvent(vtkCommand::MouseMoveEvent, nullptr);
            [self.bridge render];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
            iren->InvokeEvent(vtkCommand::MiddleButtonReleaseEvent, nullptr);
            self.isPanning = NO;
            [self.bridge render];
            break;
        default:
            break;
    }
}

// --- Pinch (zoom → VTK mouse-wheel) ---
- (void)handlePinch:(UIPinchGestureRecognizer *)gr {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;

    if (gr.state == UIGestureRecognizerStateChanged) {
        CGPoint uiPt = [gr locationInView:self.glkView];
        CGPoint pt = [self vtkPointFromUIPoint:uiPt];
        iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);

        if (gr.scale > 1.02) {
            iren->InvokeEvent(vtkCommand::MouseWheelForwardEvent, nullptr);
            gr.scale = 1.0;   // reset so next callback is relative
        } else if (gr.scale < 0.98) {
            iren->InvokeEvent(vtkCommand::MouseWheelBackwardEvent, nullptr);
            gr.scale = 1.0;
        }
        [self.bridge render];
    }
}

// --------------------------------------------------------------------------
#pragma mark - UIGestureRecognizerDelegate
// --------------------------------------------------------------------------
// Allow pinch + pan to fire simultaneously (zoom while panning).
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    // Allow our own recognizers to work together
    if ([a.view isEqual:self] && [b.view isEqual:self]) {
        return YES;
    }
    return NO;
}

// Prevent the navigation back-swipe and parent scroll views from
// claiming touches that start inside this view.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    // Our recognizers take priority over anything from parent views
    if ([gestureRecognizer.view isEqual:self] && ![other.view isEqual:self]) {
        return YES;
    }
    return NO;
}

@end

#else
@interface VTKContainerView : NSView <NSGestureRecognizerDelegate>
@property (nonatomic, weak) VTKBridge *bridge;
@property (nonatomic) BOOL didInitialRender;
/// Tracks whether a rotate (left-button) interaction is in progress.
@property (nonatomic) BOOL isRotating;
/// Tracks whether a pan (middle-button) interaction is in progress.
@property (nonatomic) BOOL isPanning;
@end

@implementation VTKContainerView

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    // Trigger initial render once view is in a window (GL context available).
    // Dispatch to next run-loop tick so AppKit/Metal backing is fully configured;
    // rendering synchronously here can create the CAMetalLayer with 0×0 drawable.
    if (self.window && self.bridge && !self.didInitialRender) {
        self.didInitialRender = YES;
        __weak VTKContainerView *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            VTKContainerView *strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.bridge) return;
            CGSize sz = strongSelf.bounds.size;
            if (sz.width > 0 && sz.height > 0) {
                [strongSelf.bridge resizeTo:sz];
            }
        });
    }
}

- (void)layout {
    [super layout];
    // Only resize once the view is in a window (Metal context valid)
    if (self.window && self.bridge && self.bounds.size.width > 0 && self.bounds.size.height > 0) {
        [self.bridge resizeTo:self.bounds.size];
    }
}

- (BOOL)isFlipped {
    return YES;  // Match SwiftUI's coordinate system
}

// Accept first responder so we receive key/mouse events directly.
- (BOOL)acceptsFirstResponder {
    return YES;
}

// --------------------------------------------------------------------------
#pragma mark - Mouse / Trackpad → VTK Interactor (macOS)
// --------------------------------------------------------------------------
// Mapping (mirrors iOS gesture recognizer approach):
//   Left-button drag          → rotate  (VTK LeftButton = trackball rotate)
//   Right-button drag / ⌥+drag → zoom   (VTK RightButton = dolly)
//   Middle-button drag / ⌘+drag → pan    (VTK MiddleButton = camera translate)
//   Scroll wheel              → zoom    (VTK MouseWheel events)
//   Trackpad pinch            → zoom    (VTK MouseWheel events)

- (vtkRenderWindowInteractor *)vtkInteractor {
    if (!self.bridge) return nullptr;
    return [self.bridge vtkInteractor];
}

/// Convert an NSEvent location to VTK coordinates (origin bottom-left, pixels).
/// VTK expects pixel coordinates with (0,0) at the bottom-left.
- (CGPoint)vtkPointFromEvent:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    // NSView with isFlipped=YES has origin at top-left → flip Y for VTK
    CGFloat viewH = self.bounds.size.height;
    return CGPointMake(loc.x, viewH - loc.y);
}

// --- Left mouse button → Rotate ---
- (void)mouseDown:(NSEvent *)event {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;
    CGPoint pt = [self vtkPointFromEvent:event];

    // ⌘+click → pan (middle button)
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
        iren->InvokeEvent(vtkCommand::MiddleButtonPressEvent, nullptr);
        self.isPanning = YES;
        return;
    }
    // ⌥+click → zoom (right button)
    if (event.modifierFlags & NSEventModifierFlagOption) {
        iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
        iren->InvokeEvent(vtkCommand::RightButtonPressEvent, nullptr);
        return;
    }

    iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
    iren->InvokeEvent(vtkCommand::LeftButtonPressEvent, nullptr);
    self.isRotating = YES;
}

- (void)mouseDragged:(NSEvent *)event {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;
    CGPoint pt = [self vtkPointFromEvent:event];
    iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
    iren->InvokeEvent(vtkCommand::MouseMoveEvent, nullptr);
    [self.bridge render];
}

- (void)mouseUp:(NSEvent *)event {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;
    CGPoint pt = [self vtkPointFromEvent:event];
    iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);

    if (self.isPanning) {
        iren->InvokeEvent(vtkCommand::MiddleButtonReleaseEvent, nullptr);
        self.isPanning = NO;
    } else if (event.modifierFlags & NSEventModifierFlagOption) {
        iren->InvokeEvent(vtkCommand::RightButtonReleaseEvent, nullptr);
    } else {
        iren->InvokeEvent(vtkCommand::LeftButtonReleaseEvent, nullptr);
        self.isRotating = NO;
    }
    [self.bridge render];
}

// --- Right mouse button → Zoom ---
- (void)rightMouseDown:(NSEvent *)event {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;
    CGPoint pt = [self vtkPointFromEvent:event];
    iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
    iren->InvokeEvent(vtkCommand::RightButtonPressEvent, nullptr);
}

- (void)rightMouseDragged:(NSEvent *)event {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;
    CGPoint pt = [self vtkPointFromEvent:event];
    iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
    iren->InvokeEvent(vtkCommand::MouseMoveEvent, nullptr);
    [self.bridge render];
}

- (void)rightMouseUp:(NSEvent *)event {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;
    CGPoint pt = [self vtkPointFromEvent:event];
    iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
    iren->InvokeEvent(vtkCommand::RightButtonReleaseEvent, nullptr);
    [self.bridge render];
}

// --- Middle mouse button → Pan ---
- (void)otherMouseDown:(NSEvent *)event {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;
    CGPoint pt = [self vtkPointFromEvent:event];
    iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
    iren->InvokeEvent(vtkCommand::MiddleButtonPressEvent, nullptr);
    self.isPanning = YES;
}

- (void)otherMouseDragged:(NSEvent *)event {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;
    CGPoint pt = [self vtkPointFromEvent:event];
    iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
    iren->InvokeEvent(vtkCommand::MouseMoveEvent, nullptr);
    [self.bridge render];
}

- (void)otherMouseUp:(NSEvent *)event {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;
    CGPoint pt = [self vtkPointFromEvent:event];
    iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);
    iren->InvokeEvent(vtkCommand::MiddleButtonReleaseEvent, nullptr);
    self.isPanning = NO;
    [self.bridge render];
}

// --- Scroll wheel → Zoom ---
- (void)scrollWheel:(NSEvent *)event {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;
    CGPoint pt = [self vtkPointFromEvent:event];
    iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);

    CGFloat dy = event.scrollingDeltaY;
    if (event.hasPreciseScrollingDeltas) {
        // Trackpad: accumulate small deltas → discrete wheel events
        dy *= 0.1;  // Scale down trackpad sensitivity
    }
    if (dy > 0.5) {
        iren->InvokeEvent(vtkCommand::MouseWheelForwardEvent, nullptr);
        [self.bridge render];
    } else if (dy < -0.5) {
        iren->InvokeEvent(vtkCommand::MouseWheelBackwardEvent, nullptr);
        [self.bridge render];
    }
}

// --- Trackpad pinch → Zoom ---
- (void)magnifyWithEvent:(NSEvent *)event {
    vtkRenderWindowInteractor *iren = [self vtkInteractor];
    if (!iren) return;
    CGPoint pt = [self vtkPointFromEvent:event];
    iren->SetEventInformation((int)pt.x, (int)pt.y, 0, 0);

    if (event.magnification > 0.01) {
        iren->InvokeEvent(vtkCommand::MouseWheelForwardEvent, nullptr);
        [self.bridge render];
    } else if (event.magnification < -0.01) {
        iren->InvokeEvent(vtkCommand::MouseWheelBackwardEvent, nullptr);
        [self.bridge render];
    }
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

#if TARGET_OS_IPHONE
        // Route all VTK error/warning messages to stderr (visible in Xcode console).
        // Critical for diagnosing shader compilation failures on ES 3.0.
        vtkOutputWindow::GetInstance()->SetDisplayModeToAlwaysStdErr();
#endif

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
        _data->slicePlaneActor = nullptr;
        _data->slicePlaneMapper = nullptr;
        _data->slicePlaneSource = nullptr;
        _data->slicePlaneCornerActor = nullptr;
        _data->slicePlaneCornerMapper = nullptr;
        _data->slicePlaneCornerData = nullptr;

        // Release terrain resources
        _data->terrainActor = nullptr;
        _data->seaPlaneActor = nullptr;
        _data->terrainMapper = nullptr;
        _data->terrainNormals = nullptr;
        _data->terrainWarp = nullptr;
        _data->terrainGeomFilter = nullptr;
        _data->terrainLUT = nullptr;
        _data->terrainImageData = nullptr;
        _data->sunLight = nullptr;
        _data->shadowPass = nullptr;
        _data->shadowBaker = nullptr;

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
#if TARGET_OS_IPHONE
    // Clean up GL context
    if (_renderView.eaglContext && [EAGLContext currentContext] == _renderView.eaglContext) {
        [EAGLContext setCurrentContext:nil];
    }
#endif
}

// --------------------------------------------------------------------------
#pragma mark - Render Window Setup
// --------------------------------------------------------------------------
- (void)setupRenderWindow {
    // ---- Renderer ----
    _data->renderer = vtkSmartPointer<vtkRenderer>::New();
    _data->renderer->SetBackground(0.2, 0.3, 0.5);   // Medium blue bottom
    _data->renderer->SetBackground2(0.5, 0.7, 0.9);   // Lighter blue top
#if TARGET_OS_IPHONE
    // VTK default BackgroundAlpha=0.0 → Transparent()=true → skips color clear.
    // On macOS the gradient shader fills color regardless, but on iOS ES 3.0
    // the gradient shader may fail, leaving the FBO at (0,0,0,0).
    // Setting alpha to 1.0 ensures glClear writes the background color.
    _data->renderer->SetBackgroundAlpha(1.0);
    // Gradient background uses a shader quad that may fail on ES 3.0.
    // Use solid color clear instead — glClear always works.
    _data->renderer->SetGradientBackground(false);
#else
    _data->renderer->SetGradientBackground(true);
#endif

    int w = (int)_frame.size.width;
    int h = (int)_frame.size.height;
    if (w <= 0) w = 800;
    if (h <= 0) h = 600;

#if TARGET_OS_IPHONE
    // ---- iOS / iPadOS ----
    _renderView = [[VTKContainerView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    _renderView.bridge = self;

    // Set up EAGLContext + GLKView BEFORE creating VTK render window
    [_renderView setupGLContext];

    vtkSmartPointer<vtkIOSRenderWindow> renWin =
        vtkSmartPointer<vtkIOSRenderWindow>::New();

    // Use retina-aware pixel dimensions
    double scale = _renderView.glkView ? _renderView.glkView.contentScaleFactor : 1.0;
    int pw = (int)(w * scale);
    int ph = (int)(h * scale);
    renWin->SetSize(pw, ph);
    renWin->SetMultiSamples(0);   // ES 3.0: avoid multisampled FBO complications

    // Don't initialize GL here — the view is not yet in a window, so GLKView's
    // drawable/FBO isn't ready. VTK will auto-initialize on the first Render()
    // call, which goes through [glkView display] → delegate → performVTKRender.
    // At that point GLKView has already bound its FBO.
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

    // Initialize the interactor — connects it to the render window so that
    // mouse/touch events are dispatched correctly.
    // On macOS, this calls vtkCocoaGLView's SetInteractor() enabling mouse handling.
    // On iOS, we forward touch events manually but Initialize() is still needed
    // to set up internal state (Enabled flag, Size, etc.).
    _data->interactor->Initialize();
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
#pragma mark - Molecular Visualization
// --------------------------------------------------------------------------

- (BOOL)loadPDBFile:(NSString *)filePath {
#if !TARGET_OS_IPHONE
    if (!_data->renderer) {
        NSLog(@"[VTKBridge] Renderer not initialized");
        return NO;
    }

    // Clear any existing actors
    _data->renderer->RemoveAllViewProps();

    // Read PDB file
    vtkSmartPointer<vtkPDBReader> reader = vtkSmartPointer<vtkPDBReader>::New();
    reader->SetFileName([filePath UTF8String]);
    reader->Update();

    // vtkMoleculeReaderBase outputs: port 0 = vtkPolyData, port 1 = vtkMolecule
    vtkMolecule *molecule = vtkMolecule::SafeDownCast(reader->GetOutputDataObject(1));
    if (!molecule || molecule->GetNumberOfAtoms() == 0) {
        NSLog(@"[VTKBridge] PDB file contains no atoms: %@", filePath);
        return NO;
    }

    NSLog(@"[VTKBridge] PDB loaded: %lld atoms, %lld bonds from %@",
          molecule->GetNumberOfAtoms(),
          molecule->GetNumberOfBonds(),
          [filePath lastPathComponent]);

    // Create molecule mapper with Ball-and-Stick style
    vtkSmartPointer<vtkMoleculeMapper> mapper = vtkSmartPointer<vtkMoleculeMapper>::New();
    mapper->SetInputData(molecule);
    mapper->UseBallAndStickSettings();

    // Create actor
    vtkSmartPointer<vtkActor> actor = vtkSmartPointer<vtkActor>::New();
    actor->SetMapper(mapper);

    // Add to renderer
    _data->renderer->AddActor(actor);

    // Set up camera
    _data->renderer->ResetCamera();
    vtkCamera *cam = _data->renderer->GetActiveCamera();
    cam->Azimuth(30);
    cam->Elevation(20);
    _data->renderer->ResetCameraClippingRange();

    NSLog(@"[VTKBridge] Molecule rendering ready (Ball-and-Stick)");
    return YES;
#else
    NSLog(@"[VTKBridge] Molecular visualization not available on iOS");
    return NO;
#endif
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
#pragma mark - Measurement Support
// --------------------------------------------------------------------------

- (double)pixelSpacingX {
    if (!_data->dicomReader) return 0.0;
    vtkImageData *imageData = _data->dicomReader->GetOutput();
    if (!imageData) return 0.0;
    double spacing[3];
    imageData->GetSpacing(spacing);
    return spacing[0];
}

- (double)pixelSpacingY {
    if (!_data->dicomReader) return 0.0;
    vtkImageData *imageData = _data->dicomReader->GetOutput();
    if (!imageData) return 0.0;
    double spacing[3];
    imageData->GetSpacing(spacing);
    return spacing[1];
}

- (NSInteger)imageWidth {
    if (!_data->dicomReader) return 0;
    vtkImageData *imageData = _data->dicomReader->GetOutput();
    if (!imageData) return 0;
    int *dims = imageData->GetDimensions();
    return (NSInteger)dims[0];
}

- (NSInteger)imageHeight {
    if (!_data->dicomReader) return 0;
    vtkImageData *imageData = _data->dicomReader->GetOutput();
    if (!imageData) return 0;
    int *dims = imageData->GetDimensions();
    return (NSInteger)dims[1];
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

#if TARGET_OS_IPHONE
    // 3. Cast to float for ES 3.0 compatibility.
    // OpenGL ES 3.0 has NO GL_R16 (normalized 16-bit) format. VTK falls back
    // to GL_R32F as internal format but still passes GL_SHORT data type to
    // glTexImage3D — this combination is invalid on ES 3.0 (GL_INVALID_OPERATION).
    // Converting to float ensures glTexImage3D gets GL_R32F + GL_FLOAT which works.
    vtkSmartPointer<vtkImageCast> castToFloat = vtkSmartPointer<vtkImageCast>::New();
    castToFloat->SetInputConnection(pipelineOutput);
    castToFloat->SetOutputScalarTypeToFloat();
    castToFloat->Update();
    pipelineOutput = castToFloat->GetOutputPort();
    NSLog(@"[VTKBridge] Cast volume data to float for ES 3.0 texture compatibility");
#endif

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
#if TARGET_OS_IPHONE
    // Use a visible non-black background so we can distinguish
    // "volume invisible" from "nothing renders at all".
    _data->renderer->SetBackground(0.1, 0.1, 0.3);
    _data->renderer->SetGradientBackground(false);
    _data->renderer->SetBackgroundAlpha(1.0);
#else
    _data->renderer->SetBackground(0.0, 0.0, 0.0);
    _data->renderer->SetGradientBackground(false);
#endif

    // --- Slice Plane Indicator (synced with DICOM viewer) ---
    // Option C: thin yellow wireframe outline + thick yellow corner brackets.
    // No fill — keeps the volume fully visible while clearly marking the slice plane.
    {
        double bounds[6];
        _data->volume->GetBounds(bounds);
        double xMin = bounds[0], xMax = bounds[1];
        double yMin = bounds[2], yMax = bounds[3];
        double zMid = (bounds[4] + bounds[5]) * 0.5;

        // 1) Thin wireframe rectangle (perimeter only, no fill)
        _data->slicePlaneSource = vtkSmartPointer<vtkPlaneSource>::New();
        _data->slicePlaneSource->SetXResolution(1);
        _data->slicePlaneSource->SetYResolution(1);
        _data->slicePlaneSource->SetOrigin(xMin, yMin, zMid);
        _data->slicePlaneSource->SetPoint1(xMax, yMin, zMid);
        _data->slicePlaneSource->SetPoint2(xMin, yMax, zMid);

        _data->slicePlaneMapper = vtkSmartPointer<vtkPolyDataMapper>::New();
        _data->slicePlaneMapper->SetInputConnection(_data->slicePlaneSource->GetOutputPort());

        _data->slicePlaneActor = vtkSmartPointer<vtkActor>::New();
        _data->slicePlaneActor->SetMapper(_data->slicePlaneMapper);
        _data->slicePlaneActor->GetProperty()->SetRepresentationToWireframe();
        _data->slicePlaneActor->GetProperty()->SetColor(0.95, 0.82, 0.10);   // bright yellow outline
        _data->slicePlaneActor->GetProperty()->SetLineWidth(1.5);
        _data->slicePlaneActor->GetProperty()->LightingOff();
        _data->slicePlaneActor->SetVisibility(0);
        _data->renderer->AddActor(_data->slicePlaneActor);

        // 2) Corner brackets — 4 L-shapes, one per corner
        // Each L = 2 line segments (horizontal arm + vertical arm) sharing a corner point.
        // 16 total points (4 corners × 4 unique endpoints, with duplicates allowed).
        const double width = xMax - xMin;
        const double height = yMax - yMin;
        const double bracketLen = std::min(width, height) * 0.12;

        vtkSmartPointer<vtkPoints> bracketPoints = vtkSmartPointer<vtkPoints>::New();
        bracketPoints->SetNumberOfPoints(16);
        vtkSmartPointer<vtkCellArray> bracketLines = vtkSmartPointer<vtkCellArray>::New();

        // Index layout per corner (4 indices each):
        //   [0] = corner, [1] = horizontal arm tip
        //   [2] = corner (duplicate), [3] = vertical arm tip
        auto setCorner = [&](int base, double cx, double cy, double dx, double dy, double z) {
            bracketPoints->SetPoint(base + 0, cx, cy, z);
            bracketPoints->SetPoint(base + 1, cx + dx * bracketLen, cy, z);
            bracketPoints->SetPoint(base + 2, cx, cy, z);
            bracketPoints->SetPoint(base + 3, cx, cy + dy * bracketLen, z);
        };
        setCorner(0,  xMin, yMin, +1, +1, zMid);  // bottom-left
        setCorner(4,  xMax, yMin, -1, +1, zMid);  // bottom-right
        setCorner(8,  xMin, yMax, +1, -1, zMid);  // top-left
        setCorner(12, xMax, yMax, -1, -1, zMid);  // top-right

        // Add 8 line cells (2 per corner × 4 corners)
        for (int corner = 0; corner < 4; ++corner) {
            int base = corner * 4;
            // Horizontal arm
            bracketLines->InsertNextCell(2);
            bracketLines->InsertCellPoint(base + 0);
            bracketLines->InsertCellPoint(base + 1);
            // Vertical arm
            bracketLines->InsertNextCell(2);
            bracketLines->InsertCellPoint(base + 2);
            bracketLines->InsertCellPoint(base + 3);
        }

        _data->slicePlaneCornerData = vtkSmartPointer<vtkPolyData>::New();
        _data->slicePlaneCornerData->SetPoints(bracketPoints);
        _data->slicePlaneCornerData->SetLines(bracketLines);

        _data->slicePlaneCornerMapper = vtkSmartPointer<vtkPolyDataMapper>::New();
        _data->slicePlaneCornerMapper->SetInputData(_data->slicePlaneCornerData);

        _data->slicePlaneCornerActor = vtkSmartPointer<vtkActor>::New();
        _data->slicePlaneCornerActor->SetMapper(_data->slicePlaneCornerMapper);
        _data->slicePlaneCornerActor->GetProperty()->SetColor(1.0, 0.92, 0.2);  // bright yellow
        _data->slicePlaneCornerActor->GetProperty()->SetLineWidth(4.0);
        _data->slicePlaneCornerActor->GetProperty()->LightingOff();
        _data->slicePlaneCornerActor->SetVisibility(0);
        _data->renderer->AddActor(_data->slicePlaneCornerActor);

        _data->slicePlaneVisible = false;
        _data->slicePlaneFraction = 0.5;
    }

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
#pragma mark - Slice Plane (DICOM-Volume sync)
// --------------------------------------------------------------------------

- (void)setSlicePlaneVisible:(BOOL)visible {
    if (_data->slicePlaneActor) {
        _data->slicePlaneActor->SetVisibility(visible ? 1 : 0);
    }
    if (_data->slicePlaneCornerActor) {
        _data->slicePlaneCornerActor->SetVisibility(visible ? 1 : 0);
    }
    _data->slicePlaneVisible = visible;
    [self render];
}

- (void)setSlicePlaneZFraction:(double)fraction {
    if (!_data->slicePlaneSource || !_data->volume) return;

    double clamped = fraction;
    if (clamped < 0.0) clamped = 0.0;
    if (clamped > 1.0) clamped = 1.0;

    double bounds[6];
    _data->volume->GetBounds(bounds);
    double xMin = bounds[0], xMax = bounds[1];
    double yMin = bounds[2], yMax = bounds[3];
    double z = bounds[4] + (bounds[5] - bounds[4]) * clamped;

    // Update wireframe outline
    _data->slicePlaneSource->SetOrigin(xMin, yMin, z);
    _data->slicePlaneSource->SetPoint1(xMax, yMin, z);
    _data->slicePlaneSource->SetPoint2(xMin, yMax, z);
    _data->slicePlaneSource->Modified();

    // Update corner brackets — re-position all 16 points at new Z
    if (_data->slicePlaneCornerData) {
        vtkPoints *pts = _data->slicePlaneCornerData->GetPoints();
        if (pts) {
            const double width = xMax - xMin;
            const double height = yMax - yMin;
            const double bracketLen = std::min(width, height) * 0.12;

            auto setCorner = [&](int base, double cx, double cy, double dx, double dy) {
                pts->SetPoint(base + 0, cx, cy, z);
                pts->SetPoint(base + 1, cx + dx * bracketLen, cy, z);
                pts->SetPoint(base + 2, cx, cy, z);
                pts->SetPoint(base + 3, cx, cy + dy * bracketLen, z);
            };
            setCorner(0,  xMin, yMin, +1, +1);
            setCorner(4,  xMax, yMin, -1, +1);
            setCorner(8,  xMin, yMax, +1, -1);
            setCorner(12, xMax, yMax, -1, -1);
            pts->Modified();
            _data->slicePlaneCornerData->Modified();
        }
    }

    _data->slicePlaneFraction = clamped;
    [self render];
}

- (BOOL)slicePlaneVisible {
    return _data->slicePlaneVisible;
}

// --------------------------------------------------------------------------
#pragma mark - Isosurface Export
// --------------------------------------------------------------------------

/// Private helper: extract isosurface from loaded DICOM data and return processed polydata.
- (vtkSmartPointer<vtkPolyData>)_extractIsosurfaceWithIsoValue:(double)isoValue
                                                decimationRate:(double)decimationRate
                                                     smoothing:(BOOL)smooth {
    if (!_data->dicomReader) {
        NSLog(@"[VTKBridge] extractIsosurface: No DICOM data loaded.");
        return nullptr;
    }

    vtkImageData *imageData = _data->dicomReader->GetOutput();
    if (!imageData || imageData->GetNumberOfPoints() == 0) {
        NSLog(@"[VTKBridge] extractIsosurface: Empty image data.");
        return nullptr;
    }

    int *dims = imageData->GetDimensions();
    NSLog(@"[VTKBridge] Extracting isosurface: isoValue=%.1f, dims=%dx%dx%d",
          isoValue, dims[0], dims[1], dims[2]);

    // 1. Marching Cubes — isosurface extraction
    auto mc = vtkSmartPointer<vtkMarchingCubes>::New();
    mc->SetInputData(imageData);
    mc->SetValue(0, isoValue);
    mc->ComputeNormalsOn();
    mc->Update();

    vtkSmartPointer<vtkPolyData> mesh = mc->GetOutput();
    if (!mesh || mesh->GetNumberOfPoints() == 0) {
        NSLog(@"[VTKBridge] MarchingCubes produced no geometry for isoValue=%.1f", isoValue);
        return nullptr;
    }
    NSLog(@"[VTKBridge] MarchingCubes: %lld points, %lld cells",
          (long long)mesh->GetNumberOfPoints(), (long long)mesh->GetNumberOfCells());

    // 2. Smoothing (optional)
    if (smooth && mesh->GetNumberOfPoints() > 0) {
        auto smoother = vtkSmartPointer<vtkSmoothPolyDataFilter>::New();
        smoother->SetInputData(mesh);
        smoother->SetNumberOfIterations(20);
        smoother->SetRelaxationFactor(0.1);
        smoother->FeatureEdgeSmoothingOff();
        smoother->BoundarySmoothingOn();
        smoother->Update();
        mesh = smoother->GetOutput();
        NSLog(@"[VTKBridge] After smoothing: %lld points", (long long)mesh->GetNumberOfPoints());
    }

    // 3. Decimation (optional)
    if (decimationRate > 0.01 && mesh->GetNumberOfPoints() > 0) {
        auto decimator = vtkSmartPointer<vtkDecimatePro>::New();
        decimator->SetInputData(mesh);
        decimator->SetTargetReduction(decimationRate);
        decimator->PreserveTopologyOn();
        decimator->Update();
        mesh = decimator->GetOutput();
        NSLog(@"[VTKBridge] After decimation (%.0f%%): %lld points, %lld cells",
              decimationRate * 100, (long long)mesh->GetNumberOfPoints(), (long long)mesh->GetNumberOfCells());
    }

    // 4. Ensure all cells are triangles
    auto triFilter = vtkSmartPointer<vtkTriangleFilter>::New();
    triFilter->SetInputData(mesh);
    triFilter->Update();
    mesh = triFilter->GetOutput();

    if (mesh->GetNumberOfCells() == 0) {
        NSLog(@"[VTKBridge] No triangles after processing.");
        return nullptr;
    }

    return mesh;
}

- (BOOL)exportIsosurfaceAsSTL:(NSString *)outputPath
                     isoValue:(double)isoValue
               decimationRate:(double)decimationRate
                    smoothing:(BOOL)smooth {
    vtkSmartPointer<vtkPolyData> mesh = [self _extractIsosurfaceWithIsoValue:isoValue
                                                             decimationRate:decimationRate
                                                                  smoothing:smooth];
    if (!mesh) return NO;

    // 5. Write binary STL manually
    //    Format: 80-byte header | uint32 numTriangles |
    //    per triangle: float[3] normal, float[3] v0, float[3] v1, float[3] v2, uint16 attr
    FILE *fp = fopen([outputPath UTF8String], "wb");
    if (!fp) {
        NSLog(@"[VTKBridge] Cannot open file for writing: %@", outputPath);
        return NO;
    }

    // Header (80 bytes)
    char header[80] = {0};
    snprintf(header, 80, "VTKSwift DICOM isosurface isoValue=%.1f", isoValue);
    fwrite(header, 1, 80, fp);

    // Count triangles
    vtkIdType numCells = mesh->GetNumberOfCells();
    uint32_t numTriangles = (uint32_t)numCells;
    fwrite(&numTriangles, sizeof(uint32_t), 1, fp);

    // Get normals if available
    vtkDataArray *normals = mesh->GetPointData()->GetNormals();

    // Write each triangle
    for (vtkIdType i = 0; i < numCells; i++) {
        vtkCell *cell = mesh->GetCell(i);
        if (cell->GetNumberOfPoints() != 3) continue;

        vtkIdType id0 = cell->GetPointId(0);
        vtkIdType id1 = cell->GetPointId(1);
        vtkIdType id2 = cell->GetPointId(2);

        double p0[3], p1[3], p2[3];
        mesh->GetPoint(id0, p0);
        mesh->GetPoint(id1, p1);
        mesh->GetPoint(id2, p2);

        // Face normal (average of vertex normals or zero)
        float normal[3] = {0, 0, 0};
        if (normals) {
            double n0[3], n1[3], n2[3];
            normals->GetTuple(id0, n0);
            normals->GetTuple(id1, n1);
            normals->GetTuple(id2, n2);
            normal[0] = (float)((n0[0] + n1[0] + n2[0]) / 3.0);
            normal[1] = (float)((n0[1] + n1[1] + n2[1]) / 3.0);
            normal[2] = (float)((n0[2] + n1[2] + n2[2]) / 3.0);
        }

        fwrite(normal, sizeof(float), 3, fp);

        float v0[3] = {(float)p0[0], (float)p0[1], (float)p0[2]};
        float v1[3] = {(float)p1[0], (float)p1[1], (float)p1[2]};
        float v2[3] = {(float)p2[0], (float)p2[1], (float)p2[2]};
        fwrite(v0, sizeof(float), 3, fp);
        fwrite(v1, sizeof(float), 3, fp);
        fwrite(v2, sizeof(float), 3, fp);

        uint16_t attrByteCount = 0;
        fwrite(&attrByteCount, sizeof(uint16_t), 1, fp);
    }

    fclose(fp);

    NSLog(@"[VTKBridge] STL exported: %u triangles to %@", numTriangles, outputPath);
    return YES;
}

- (BOOL)exportIsosurfaceAsOBJ:(NSString *)outputPath
                     isoValue:(double)isoValue
               decimationRate:(double)decimationRate
                    smoothing:(BOOL)smooth {
    vtkSmartPointer<vtkPolyData> mesh = [self _extractIsosurfaceWithIsoValue:isoValue
                                                             decimationRate:decimationRate
                                                                  smoothing:smooth];
    if (!mesh) return NO;

    // Derive .mtl path from .obj path
    NSString *basePath = [outputPath stringByDeletingPathExtension];
    NSString *mtlPath = [basePath stringByAppendingPathExtension:@"mtl"];
    NSString *mtlFilename = [mtlPath lastPathComponent];
    NSString *objName = [[outputPath lastPathComponent] stringByDeletingPathExtension];

    // --- Write MTL file ---
    FILE *mtlFp = fopen([mtlPath UTF8String], "w");
    if (!mtlFp) {
        NSLog(@"[VTKBridge] Cannot open MTL file for writing: %@", mtlPath);
        return NO;
    }
    fprintf(mtlFp, "# VTKSwift Material\n");
    fprintf(mtlFp, "# Generated from DICOM isosurface (isoValue=%.1f)\n\n", isoValue);
    fprintf(mtlFp, "newmtl isosurface\n");
    fprintf(mtlFp, "Ka 0.2 0.2 0.2\n");      // ambient
    fprintf(mtlFp, "Kd 0.878 0.839 0.784\n"); // diffuse (bone-like ivory)
    fprintf(mtlFp, "Ks 0.3 0.3 0.3\n");       // specular
    fprintf(mtlFp, "Ns 80.0\n");              // shininess
    fprintf(mtlFp, "d 1.0\n");                // opacity
    fprintf(mtlFp, "illum 2\n");              // diffuse + specular
    fclose(mtlFp);

    // --- Write OBJ file ---
    FILE *fp = fopen([outputPath UTF8String], "w");
    if (!fp) {
        NSLog(@"[VTKBridge] Cannot open OBJ file for writing: %@", outputPath);
        return NO;
    }

    fprintf(fp, "# VTKSwift OBJ Export\n");
    fprintf(fp, "# DICOM isosurface isoValue=%.1f\n", isoValue);
    fprintf(fp, "# Reference only — not for clinical diagnosis\n\n");
    fprintf(fp, "mtllib %s\n", [mtlFilename UTF8String]);
    fprintf(fp, "o %s\n\n", [objName UTF8String]);

    vtkIdType numPoints = mesh->GetNumberOfPoints();
    vtkIdType numCells = mesh->GetNumberOfCells();

    // Vertices
    for (vtkIdType i = 0; i < numPoints; i++) {
        double p[3];
        mesh->GetPoint(i, p);
        fprintf(fp, "v %.6f %.6f %.6f\n", p[0], p[1], p[2]);
    }
    fprintf(fp, "\n");

    // Normals
    vtkDataArray *normals = mesh->GetPointData()->GetNormals();
    if (normals) {
        for (vtkIdType i = 0; i < numPoints; i++) {
            double n[3];
            normals->GetTuple(i, n);
            fprintf(fp, "vn %.6f %.6f %.6f\n", n[0], n[1], n[2]);
        }
        fprintf(fp, "\n");
    }

    // Faces (1-indexed)
    fprintf(fp, "usemtl isosurface\n");
    for (vtkIdType i = 0; i < numCells; i++) {
        vtkCell *cell = mesh->GetCell(i);
        if (cell->GetNumberOfPoints() != 3) continue;

        vtkIdType i0 = cell->GetPointId(0) + 1;  // OBJ is 1-indexed
        vtkIdType i1 = cell->GetPointId(1) + 1;
        vtkIdType i2 = cell->GetPointId(2) + 1;

        if (normals) {
            fprintf(fp, "f %lld//%lld %lld//%lld %lld//%lld\n",
                    (long long)i0, (long long)i0,
                    (long long)i1, (long long)i1,
                    (long long)i2, (long long)i2);
        } else {
            fprintf(fp, "f %lld %lld %lld\n",
                    (long long)i0, (long long)i1, (long long)i2);
        }
    }

    fclose(fp);

    NSLog(@"[VTKBridge] OBJ exported: %lld vertices, %lld faces to %@",
          (long long)numPoints, (long long)numCells, outputPath);
    return YES;
}

- (BOOL)extractIsosurfaceMeshWithIsoValue:(double)isoValue
                           decimationRate:(double)decimationRate
                                smoothing:(BOOL)smooth
                                 vertices:(NSData * _Nullable * _Nonnull)verticesOut
                                  normals:(NSData * _Nullable * _Nonnull)normalsOut
                                    faces:(NSData * _Nullable * _Nonnull)facesOut {
    vtkSmartPointer<vtkPolyData> mesh = [self _extractIsosurfaceWithIsoValue:isoValue
                                                             decimationRate:decimationRate
                                                                  smoothing:smooth];
    if (!mesh) return NO;

    vtkIdType numPoints = mesh->GetNumberOfPoints();
    vtkIdType numCells = mesh->GetNumberOfCells();

    // Pack vertices as float32 [x,y,z, x,y,z, ...]
    NSMutableData *vData = [NSMutableData dataWithLength:numPoints * 3 * sizeof(float)];
    float *vPtr = (float *)[vData mutableBytes];
    for (vtkIdType i = 0; i < numPoints; i++) {
        double p[3];
        mesh->GetPoint(i, p);
        vPtr[i * 3 + 0] = (float)p[0];
        vPtr[i * 3 + 1] = (float)p[1];
        vPtr[i * 3 + 2] = (float)p[2];
    }

    // Pack normals as float32 [nx,ny,nz, ...]
    NSMutableData *nData = [NSMutableData dataWithLength:numPoints * 3 * sizeof(float)];
    float *nPtr = (float *)[nData mutableBytes];
    vtkDataArray *meshNormals = mesh->GetPointData()->GetNormals();
    if (meshNormals) {
        for (vtkIdType i = 0; i < numPoints; i++) {
            double n[3];
            meshNormals->GetTuple(i, n);
            nPtr[i * 3 + 0] = (float)n[0];
            nPtr[i * 3 + 1] = (float)n[1];
            nPtr[i * 3 + 2] = (float)n[2];
        }
    }

    // Pack face indices as uint32 [i0,i1,i2, ...]
    NSMutableData *fData = [NSMutableData dataWithLength:numCells * 3 * sizeof(uint32_t)];
    uint32_t *fPtr = (uint32_t *)[fData mutableBytes];
    vtkIdType fIdx = 0;
    for (vtkIdType i = 0; i < numCells; i++) {
        vtkCell *cell = mesh->GetCell(i);
        if (cell->GetNumberOfPoints() != 3) continue;
        fPtr[fIdx * 3 + 0] = (uint32_t)cell->GetPointId(0);
        fPtr[fIdx * 3 + 1] = (uint32_t)cell->GetPointId(1);
        fPtr[fIdx * 3 + 2] = (uint32_t)cell->GetPointId(2);
        fIdx++;
    }
    // Trim if some cells were skipped
    if (fIdx < numCells) {
        [fData setLength:fIdx * 3 * sizeof(uint32_t)];
    }

    *verticesOut = [vData copy];
    *normalsOut = [nData copy];
    *facesOut = [fData copy];

    NSLog(@"[VTKBridge] Mesh extracted: %lld vertices, %lld faces",
          (long long)numPoints, (long long)fIdx);
    return YES;
}

- (BOOL)exportMultiIsosurfaceAsOBJ:(NSString *)outputPath
                         isoValues:(NSArray<NSNumber *> *)isoValues
                             names:(NSArray<NSString *> *)names
                    decimationRate:(double)decimationRate
                         smoothing:(BOOL)smooth {
    if (!isoValues || isoValues.count == 0) return NO;
    if (names.count != isoValues.count) return NO;

    // Predefined colors for each tissue layer (up to 5)
    static const double colors[][3] = {
        {0.878, 0.839, 0.784},  // Bone — ivory
        {0.827, 0.522, 0.475},  // Soft Tissue — pink
        {0.925, 0.839, 0.745},  // Skin — peach
        {0.600, 0.200, 0.200},  // Muscle — dark red
        {0.700, 0.700, 0.700},  // Other — gray
    };
    static const int numColors = 5;

    NSString *basePath = [outputPath stringByDeletingPathExtension];
    NSString *mtlPath = [basePath stringByAppendingPathExtension:@"mtl"];
    NSString *mtlFilename = [mtlPath lastPathComponent];

    // --- Write MTL ---
    FILE *mtlFp = fopen([mtlPath UTF8String], "w");
    if (!mtlFp) return NO;
    fprintf(mtlFp, "# VTKSwift Multi-Isosurface Material\n\n");
    for (NSUInteger i = 0; i < names.count; i++) {
        int ci = (int)(i % numColors);
        fprintf(mtlFp, "newmtl %s\n", [names[i] UTF8String]);
        fprintf(mtlFp, "Ka 0.2 0.2 0.2\n");
        fprintf(mtlFp, "Kd %.3f %.3f %.3f\n", colors[ci][0], colors[ci][1], colors[ci][2]);
        fprintf(mtlFp, "Ks 0.3 0.3 0.3\n");
        fprintf(mtlFp, "Ns 80.0\n");
        fprintf(mtlFp, "d %.1f\n", (i == 0) ? 1.0 : 0.6);  // lower layers semi-transparent
        fprintf(mtlFp, "illum 2\n\n");
    }
    fclose(mtlFp);

    // --- Write OBJ ---
    FILE *fp = fopen([outputPath UTF8String], "w");
    if (!fp) return NO;

    fprintf(fp, "# VTKSwift Multi-Isosurface OBJ Export\n");
    fprintf(fp, "# Reference only — not for clinical diagnosis\n\n");
    fprintf(fp, "mtllib %s\n\n", [mtlFilename UTF8String]);

    vtkIdType vertexOffset = 0;  // OBJ vertex indices are global, 1-based

    for (NSUInteger layer = 0; layer < isoValues.count; layer++) {
        double isoValue = [isoValues[layer] doubleValue];
        NSString *name = names[layer];

        vtkSmartPointer<vtkPolyData> mesh = [self _extractIsosurfaceWithIsoValue:isoValue
                                                                 decimationRate:decimationRate
                                                                      smoothing:smooth];
        if (!mesh) {
            NSLog(@"[VTKBridge] Multi-ISO: skipping layer %@ (isoValue=%.1f) — no geometry", name, isoValue);
            continue;
        }

        vtkIdType numPoints = mesh->GetNumberOfPoints();
        vtkIdType numCells = mesh->GetNumberOfCells();

        fprintf(fp, "g %s\n", [name UTF8String]);
        fprintf(fp, "usemtl %s\n", [name UTF8String]);

        // Vertices
        for (vtkIdType i = 0; i < numPoints; i++) {
            double p[3];
            mesh->GetPoint(i, p);
            fprintf(fp, "v %.6f %.6f %.6f\n", p[0], p[1], p[2]);
        }

        // Normals
        vtkDataArray *normals = mesh->GetPointData()->GetNormals();
        if (normals) {
            for (vtkIdType i = 0; i < numPoints; i++) {
                double n[3];
                normals->GetTuple(i, n);
                fprintf(fp, "vn %.6f %.6f %.6f\n", n[0], n[1], n[2]);
            }
        }

        // Faces (offset by total vertices from previous layers)
        for (vtkIdType i = 0; i < numCells; i++) {
            vtkCell *cell = mesh->GetCell(i);
            if (cell->GetNumberOfPoints() != 3) continue;

            long long i0 = cell->GetPointId(0) + vertexOffset + 1;
            long long i1 = cell->GetPointId(1) + vertexOffset + 1;
            long long i2 = cell->GetPointId(2) + vertexOffset + 1;

            if (normals) {
                fprintf(fp, "f %lld//%lld %lld//%lld %lld//%lld\n", i0, i0, i1, i1, i2, i2);
            } else {
                fprintf(fp, "f %lld %lld %lld\n", i0, i1, i2);
            }
        }

        vertexOffset += numPoints;
        fprintf(fp, "\n");
        NSLog(@"[VTKBridge] Multi-ISO layer '%@' (%.0f HU): %lld verts, %lld faces",
              name, isoValue, (long long)numPoints, (long long)numCells);
    }

    fclose(fp);
    NSLog(@"[VTKBridge] Multi-isosurface OBJ exported to %@", outputPath);
    return YES;
}

// --------------------------------------------------------------------------
#pragma mark - Terrain Viewer (Urban Sunlight Simulator)
// --------------------------------------------------------------------------

- (BOOL)loadTerrainFromRawDEM:(NSString *)path
                        width:(NSInteger)width
                       height:(NSInteger)height
                     spacingX:(double)spacingX
                     spacingY:(double)spacingY {
    if (!path || path.length == 0) return NO;

    // Read raw 16-bit signed LE heightfield
    FILE *fp = fopen([path UTF8String], "rb");
    if (!fp) {
        NSLog(@"[VTKBridge] Cannot open DEM file: %@", path);
        return NO;
    }

    NSInteger totalPixels = width * height;
    int16_t *rawData = new int16_t[totalPixels];
    size_t bytesRead = fread(rawData, sizeof(int16_t), totalPixels, fp);
    fclose(fp);

    if ((NSInteger)bytesRead != totalPixels) {
        NSLog(@"[VTKBridge] DEM read error: expected %ld pixels, got %zu",
              (long)totalPixels, bytesRead);
        delete[] rawData;
        return NO;
    }

    // Find elevation range
    double minElev = 1e9, maxElev = -1e9;
    for (NSInteger i = 0; i < totalPixels; i++) {
        double v = (double)rawData[i];
        if (v < minElev) minElev = v;
        if (v > maxElev) maxElev = v;
    }
    _data->terrainMinElev = minElev;
    _data->terrainMaxElev = maxElev;

    NSLog(@"[VTKBridge] DEM loaded: %ldx%ld, elevation %.0f–%.0fm, spacing %.1fx%.1fm",
          (long)width, (long)height, minElev, maxElev, spacingX, spacingY);

    // Create vtkImageData
    _data->terrainImageData = vtkSmartPointer<vtkImageData>::New();
    _data->terrainImageData->SetDimensions((int)width, (int)height, 1);
    _data->terrainImageData->SetSpacing(spacingX, spacingY, 1.0);
    _data->terrainImageData->SetOrigin(0, 0, 0);
    _data->terrainImageData->AllocateScalars(VTK_FLOAT, 1);

    // Copy data (flip Y so north is up in VTK coordinate system)
    float *scalars = static_cast<float *>(
        _data->terrainImageData->GetScalarPointer());
    for (NSInteger row = 0; row < height; row++) {
        for (NSInteger col = 0; col < width; col++) {
            NSInteger srcIdx = row * width + col;
            NSInteger dstIdx = (height - 1 - row) * width + col;
            scalars[dstIdx] = (float)rawData[srcIdx];
        }
    }

    delete[] rawData;

    [self buildTerrainPipeline];
    return YES;
}

- (BOOL)loadSyntheticTerrain:(NSInteger)gridSize {
    if (gridSize < 32) gridSize = 32;
    if (gridSize > 1024) gridSize = 1024;

    double spacing = 30.0;  // ~30m like SRTM

    _data->terrainImageData = vtkSmartPointer<vtkImageData>::New();
    _data->terrainImageData->SetDimensions((int)gridSize, (int)gridSize, 1);
    _data->terrainImageData->SetSpacing(spacing, spacing, 1.0);
    _data->terrainImageData->SetOrigin(0, 0, 0);
    _data->terrainImageData->AllocateScalars(VTK_FLOAT, 1);

    float *scalars = static_cast<float *>(
        _data->terrainImageData->GetScalarPointer());
    double center = gridSize * spacing * 0.5;
    _data->terrainMinElev = 1e9;
    _data->terrainMaxElev = -1e9;

    for (NSInteger j = 0; j < gridSize; j++) {
        for (NSInteger i = 0; i < gridSize; i++) {
            double x = i * spacing;
            double y = j * spacing;
            double dx = (x - center) / (center * 0.6);
            double dy = (y - center) / (center * 0.6);
            // Mountain + ridge + noise
            double elev = 300.0 * exp(-(dx * dx + dy * dy)) +
                          100.0 * sin(dx * 3.0) * cos(dy * 2.5) +
                          50.0 * sin(dx * 7.0 + dy * 5.0) * 0.5 -
                          20.0;
            if (elev < -20) elev = -20;
            scalars[j * gridSize + i] = (float)elev;
            if (elev < _data->terrainMinElev) _data->terrainMinElev = elev;
            if (elev > _data->terrainMaxElev) _data->terrainMaxElev = elev;
        }
    }

    NSLog(@"[VTKBridge] Synthetic terrain: %ldx%ld, elevation %.0f–%.0fm",
          (long)gridSize, (long)gridSize,
          _data->terrainMinElev, _data->terrainMaxElev);

    [self buildTerrainPipeline];
    return YES;
}

- (void)buildTerrainPipeline {
    // Clear previous scene
    _data->renderer->RemoveAllViewProps();
    if (_data->sunLight) {
        _data->renderer->RemoveLight(_data->sunLight);
        _data->sunLight = nullptr;
    }
    _data->renderer->RemoveAllLights();

    // 1. ImageData → PolyData (flat 2D grid)
    _data->terrainGeomFilter =
        vtkSmartPointer<vtkImageDataGeometryFilter>::New();
    _data->terrainGeomFilter->SetInputData(_data->terrainImageData);

    // 2. Warp Z by elevation
    _data->terrainWarp = vtkSmartPointer<vtkWarpScalar>::New();
    _data->terrainWarp->SetInputConnection(
        _data->terrainGeomFilter->GetOutputPort());
    _data->terrainWarp->SetScaleFactor(_data->terrainExaggeration);
    _data->terrainWarp->UseNormalOn();
    _data->terrainWarp->SetNormal(0, 0, 1);

    // 3. Compute smooth normals
    _data->terrainNormals = vtkSmartPointer<vtkPolyDataNormals>::New();
    _data->terrainNormals->SetInputConnection(
        _data->terrainWarp->GetOutputPort());
    _data->terrainNormals->SetFeatureAngle(60.0);
    _data->terrainNormals->ComputePointNormalsOn();
    _data->terrainNormals->SplittingOff();
    _data->terrainNormals->Update();

    // 4. Color by elevation
    [self buildTerrainLUT];

    // 5. Mapper
    _data->terrainMapper = vtkSmartPointer<vtkPolyDataMapper>::New();
    _data->terrainMapper->SetInputConnection(
        _data->terrainNormals->GetOutputPort());
    _data->terrainMapper->SetLookupTable(_data->terrainLUT);
    _data->terrainMapper->SetScalarRange(
        _data->terrainMinElev, _data->terrainMaxElev);
    _data->terrainMapper->ScalarVisibilityOn();

    // 6. Actor
    _data->terrainActor = vtkSmartPointer<vtkActor>::New();
    _data->terrainActor->SetMapper(_data->terrainMapper);
    _data->terrainActor->GetProperty()->SetAmbient(0.15);
    _data->terrainActor->GetProperty()->SetDiffuse(0.85);
    _data->terrainActor->GetProperty()->SetSpecular(0.05);
    _data->terrainActor->GetProperty()->SetSpecularPower(5.0);
    _data->renderer->AddActor(_data->terrainActor);

    // 7. Sea plane at z=0
    [self addSeaPlane];

    // 8. Lighting — sun (positional for shadow map compatibility)
    _data->sunLight = vtkSmartPointer<vtkLight>::New();
    _data->sunLight->SetLightTypeToSceneLight();
    _data->sunLight->SetPositional(true);
    _data->sunLight->SetConeAngle(120.0);
    _data->sunLight->SetColor(1.0, 0.95, 0.85);
    _data->sunLight->SetIntensity(1.0);
    [self updateSunDirection];
    _data->renderer->AddLight(_data->sunLight);

    // Ambient fill light (sky)
    vtkSmartPointer<vtkLight> ambientLight =
        vtkSmartPointer<vtkLight>::New();
    ambientLight->SetLightTypeToSceneLight();
    ambientLight->SetPositional(false);
    ambientLight->SetColor(0.6, 0.7, 0.9);
    ambientLight->SetIntensity(0.3);
    ambientLight->SetPosition(0, 0, 1);
    ambientLight->SetFocalPoint(0, 0, 0);
    _data->renderer->AddLight(ambientLight);

    // 9. Shadow map passes
    if (_data->shadowsEnabled) {
        [self setupShadowPasses];
    }

    // 10. Sky background
    _data->renderer->SetBackground(0.45, 0.55, 0.70);
    _data->renderer->SetBackground2(0.15, 0.25, 0.50);
    _data->renderer->SetGradientBackground(true);

    // 11. Camera setup
    _data->renderer->ResetCamera();
    vtkCamera *cam = _data->renderer->GetActiveCamera();
    cam->Elevation(-30);
    cam->Azimuth(20);
    _data->renderer->ResetCameraClippingRange();

    // Trackball interaction
    vtkSmartPointer<vtkInteractorStyleTrackballCamera> style =
        vtkSmartPointer<vtkInteractorStyleTrackballCamera>::New();
    _data->interactor->SetInteractorStyle(style);

    _data->isTerrainMode = true;
    NSLog(@"[VTKBridge] Terrain pipeline ready");
}

- (void)buildTerrainLUT {
    _data->terrainLUT = vtkSmartPointer<vtkLookupTable>::New();
    _data->terrainLUT->SetNumberOfTableValues(256);

    double minE = _data->terrainMinElev;
    double maxE = _data->terrainMaxElev;
    double range = maxE - minE;
    if (range < 1.0) range = 1.0;

    _data->terrainLUT->SetTableRange(minE, maxE);

    switch (_data->terrainColorScheme) {
        case VTKTerrainColorSchemeElevation: {
            _data->terrainLUT->Build();
            for (int i = 0; i < 256; i++) {
                double t = (double)i / 255.0;
                double r, g, b;
                if (t < 0.05) {
                    // Below sea level: deep blue
                    r = 0.1; g = 0.2; b = 0.6;
                } else if (t < 0.15) {
                    // Coast: sandy
                    double s = (t - 0.05) / 0.10;
                    r = 0.1 + s * 0.6;
                    g = 0.2 + s * 0.5;
                    b = 0.6 - s * 0.4;
                } else if (t < 0.35) {
                    // Lowland: green
                    double s = (t - 0.15) / 0.20;
                    r = 0.25 + s * 0.15;
                    g = 0.55 + s * 0.05;
                    b = 0.15 + s * 0.05;
                } else if (t < 0.60) {
                    // Mid-elevation: green to brown
                    double s = (t - 0.35) / 0.25;
                    r = 0.40 + s * 0.25;
                    g = 0.60 - s * 0.20;
                    b = 0.20 - s * 0.05;
                } else if (t < 0.85) {
                    // Highland: brown to gray
                    double s = (t - 0.60) / 0.25;
                    r = 0.65 + s * 0.10;
                    g = 0.40 + s * 0.15;
                    b = 0.15 + s * 0.20;
                } else {
                    // Peak: gray to white
                    double s = (t - 0.85) / 0.15;
                    r = 0.75 + s * 0.25;
                    g = 0.55 + s * 0.45;
                    b = 0.35 + s * 0.65;
                }
                _data->terrainLUT->SetTableValue(i, r, g, b, 1.0);
            }
            break;
        }
        case VTKTerrainColorSchemeSatellite: {
            _data->terrainLUT->Build();
            for (int i = 0; i < 256; i++) {
                double t = (double)i / 255.0;
                double r, g, b;
                if (t < 0.05) {
                    r = 0.15; g = 0.25; b = 0.45;
                } else if (t < 0.20) {
                    double s = (t - 0.05) / 0.15;
                    r = 0.35 + s * 0.15;
                    g = 0.40 + s * 0.15;
                    b = 0.25 - s * 0.05;
                } else if (t < 0.50) {
                    double s = (t - 0.20) / 0.30;
                    r = 0.50 + s * 0.10;
                    g = 0.55 - s * 0.10;
                    b = 0.20 + s * 0.05;
                } else {
                    double s = (t - 0.50) / 0.50;
                    r = 0.60 + s * 0.15;
                    g = 0.45 + s * 0.10;
                    b = 0.25 + s * 0.15;
                }
                _data->terrainLUT->SetTableValue(i, r, g, b, 1.0);
            }
            break;
        }
        case VTKTerrainColorSchemeGrayscale: {
            _data->terrainLUT->Build();
            for (int i = 0; i < 256; i++) {
                double t = (double)i / 255.0;
                double v;
                if (t < 0.05) {
                    v = 0.3;
                } else {
                    v = 0.5 + (t - 0.05) * 0.45;
                }
                _data->terrainLUT->SetTableValue(i, v, v, v, 1.0);
            }
            break;
        }
    }
}

- (void)addSeaPlane {
    // Get terrain bounds for plane sizing
    _data->terrainGeomFilter->Update();
    _data->terrainWarp->Update();
    double bounds[6];
    _data->terrainWarp->GetOutput()->GetBounds(bounds);
    double margin = 500.0;

    vtkSmartPointer<vtkPlaneSource> plane =
        vtkSmartPointer<vtkPlaneSource>::New();
    plane->SetOrigin(bounds[0] - margin, bounds[2] - margin, 0);
    plane->SetPoint1(bounds[1] + margin, bounds[2] - margin, 0);
    plane->SetPoint2(bounds[0] - margin, bounds[3] + margin, 0);
    plane->SetResolution(1, 1);
    plane->Update();

    vtkSmartPointer<vtkPolyDataMapper> planeMapper =
        vtkSmartPointer<vtkPolyDataMapper>::New();
    planeMapper->SetInputConnection(plane->GetOutputPort());

    _data->seaPlaneActor = vtkSmartPointer<vtkActor>::New();
    _data->seaPlaneActor->SetMapper(planeMapper);
    _data->seaPlaneActor->GetProperty()->SetColor(0.2, 0.4, 0.7);
    _data->seaPlaneActor->GetProperty()->SetOpacity(0.6);
    _data->seaPlaneActor->GetProperty()->SetAmbient(0.4);
    _data->seaPlaneActor->GetProperty()->SetDiffuse(0.6);
    _data->renderer->AddActor(_data->seaPlaneActor);
}

- (void)setupShadowPasses {
    // Create render passes for shadow mapping
    vtkSmartPointer<vtkOpaquePass> opaquePass =
        vtkSmartPointer<vtkOpaquePass>::New();
    vtkSmartPointer<vtkLightsPass> lightsPass =
        vtkSmartPointer<vtkLightsPass>::New();

    // Sequence: lights → opaque geometry
    vtkSmartPointer<vtkRenderPassCollection> passes =
        vtkSmartPointer<vtkRenderPassCollection>::New();
    passes->AddItem(lightsPass);
    passes->AddItem(opaquePass);

    vtkSmartPointer<vtkSequencePass> seqPass =
        vtkSmartPointer<vtkSequencePass>::New();
    seqPass->SetPasses(passes);

    // Shadow map baker (renders depth from light's POV)
    _data->shadowBaker = vtkSmartPointer<vtkShadowMapBakerPass>::New();
    _data->shadowBaker->SetResolution(2048);
    _data->shadowBaker->SetOpaqueSequence(seqPass);

    // Shadow map pass (uses baked depth to compute shadows)
    _data->shadowPass = vtkSmartPointer<vtkShadowMapPass>::New();
    _data->shadowPass->SetShadowMapBakerPass(_data->shadowBaker);
    _data->shadowPass->SetOpaqueSequence(seqPass);

    // Top-level camera pass
    vtkSmartPointer<vtkRenderPassCollection> topPasses =
        vtkSmartPointer<vtkRenderPassCollection>::New();
    topPasses->AddItem(_data->shadowBaker);
    topPasses->AddItem(_data->shadowPass);

    vtkSmartPointer<vtkSequencePass> topSeq =
        vtkSmartPointer<vtkSequencePass>::New();
    topSeq->SetPasses(topPasses);

    vtkSmartPointer<vtkCameraPass> cameraPass =
        vtkSmartPointer<vtkCameraPass>::New();
    cameraPass->SetDelegatePass(topSeq);

    _data->renderer->SetPass(cameraPass);

    NSLog(@"[VTKBridge] Shadow map passes configured (2048x2048)");
}

- (void)updateSunDirection {
    if (!_data->sunLight) return;

    // Convert elevation/azimuth to direction vector
    double elevRad = _data->terrainSunElevation * M_PI / 180.0;
    double azRad = _data->terrainSunAzimuth * M_PI / 180.0;

    // Azimuth: 0=North(+Y), 90=East(+X), 180=South(-Y), 270=West(-X)
    double dx = cos(elevRad) * sin(azRad);
    double dy = cos(elevRad) * cos(azRad);
    double dz = sin(elevRad);

    // VTK light: SetPosition sets where light comes from
    double dist = 50000.0;
    _data->sunLight->SetPosition(dx * dist, dy * dist, dz * dist);
    _data->sunLight->SetFocalPoint(0, 0, 0);

    // Warm light at low sun angles (golden hour effect)
    double warmth = 1.0;
    if (_data->terrainSunElevation < 15.0) {
        warmth = _data->terrainSunElevation / 15.0;
        if (warmth < 0.0) warmth = 0.0;
    }
    double r = 1.0;
    double g = 0.80 + warmth * 0.15;
    double b = 0.60 + warmth * 0.25;
    _data->sunLight->SetColor(r, g, b);

    // Dim light at low sun angles
    double intensity = 0.3 + 0.7 * sin(elevRad);
    if (intensity < 0.3) intensity = 0.3;
    _data->sunLight->SetIntensity(intensity);
}

- (void)setSunElevation:(double)elevation azimuth:(double)azimuth {
    if (!_data->isTerrainMode) return;

    if (elevation < 0) elevation = 0;
    if (elevation > 90) elevation = 90;
    while (azimuth < 0) azimuth += 360;
    while (azimuth >= 360) azimuth -= 360;

    _data->terrainSunElevation = elevation;
    _data->terrainSunAzimuth = azimuth;

    [self updateSunDirection];
    [self render];
}

- (void)setElevationExaggeration:(double)factor {
    if (!_data->isTerrainMode || !_data->terrainWarp) return;

    if (factor < 0.5) factor = 0.5;
    if (factor > 10.0) factor = 10.0;

    _data->terrainExaggeration = factor;
    _data->terrainWarp->SetScaleFactor(factor);
    _data->terrainWarp->Update();
    _data->terrainNormals->Update();

    _data->renderer->ResetCameraClippingRange();
    [self render];
}

- (void)setShadowsEnabled:(BOOL)enabled {
    if (!_data->isTerrainMode) return;

    _data->shadowsEnabled = (bool)enabled;

    if (enabled) {
        [self setupShadowPasses];
    } else {
        // Remove render passes (revert to default rendering)
        _data->renderer->SetPass(nullptr);
        _data->shadowPass = nullptr;
        _data->shadowBaker = nullptr;
    }

    [self render];
}

- (void)applyTerrainColorScheme:(VTKTerrainColorScheme)scheme {
    if (!_data->isTerrainMode) return;

    _data->terrainColorScheme = scheme;
    [self buildTerrainLUT];

    if (_data->terrainMapper) {
        _data->terrainMapper->SetLookupTable(_data->terrainLUT);
        _data->terrainMapper->SetScalarRange(
            _data->terrainMinElev, _data->terrainMaxElev);
    }

    [self render];
}

// Terrain property getters
- (BOOL)isTerrainLoaded {
    return _data->isTerrainMode;
}

- (double)terrainElevationExaggeration {
    return _data->terrainExaggeration;
}

- (double)terrainSunElevation {
    return _data->terrainSunElevation;
}

- (double)terrainSunAzimuth {
    return _data->terrainSunAzimuth;
}

// --------------------------------------------------------------------------
#pragma mark - Rendering
// --------------------------------------------------------------------------
- (void)render {
    if (!_data->renderWindow) return;

#if TARGET_OS_IPHONE
    // Guard: only render when the container view is in a window.
    if (!_renderView.window) return;
    [_renderView makeGLContextCurrent];

    // Drive rendering through GLKView's display loop.
    // [glkView display] will:
    //   1) make EAGLContext current
    //   2) bind GLKView's internal FBO (renderbuffer backed by CAEAGLLayer)
    //   3) call our delegate method glkView:drawInRect: → performVTKRender
    //   4) present the renderbuffer to screen
    if (_renderView.glkView) {
        [_renderView.glkView display];
    }
#else
    if (!_renderView.window) return;
    _data->renderWindow->Render();
#endif
}

/// Returns VTK's interactor (used by VTKContainerView for touch events).
- (vtkRenderWindowInteractor *)vtkInteractor {
    return _data ? _data->interactor.Get() : nullptr;
}

/// Called from GLKView delegate (iOS) or directly.
/// On iOS, GLKView has already bound its FBO before this is called.
/// This follows VTK's official iOS example pattern: just call Render().
/// VTK's BlitToCurrent mode handles the blit from display FBO → GLKView FBO.
- (void)performVTKRender {
    if (!_data->renderWindow) return;

#if TARGET_OS_IPHONE
    // Sync VTK's state tracker with GLKView's FBO so VTK's push/pop works correctly.
    vtkOpenGLRenderWindow *glRenWin =
        vtkOpenGLRenderWindow::SafeDownCast(_data->renderWindow);
    if (glRenWin && glRenWin->GetState()) {
        GLint glkFBO = 0;
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &glkFBO);
        glRenWin->GetState()->vtkglBindFramebuffer(GL_FRAMEBUFFER, (unsigned int)glkFBO);
    }

    // VTK's Render() does: Start (bind internal FBOs) → render scene →
    // End → Frame (resolve render→display, blit display→current).
    // BlitToCurrent mode blits to GLKView's FBO. GLKView then presents it.
    _data->renderWindow->Render();

    static int renderCount = 0;
    renderCount++;
    if (renderCount <= 2) {
        GLenum glErr = glGetError();
        NSLog(@"[VTKBridge] GL_VERSION: %s  GLSL: %s  Renderer: %s  glErr=%d",
              (const char *)glGetString(GL_VERSION) ?: "(null)",
              (const char *)glGetString(GL_SHADING_LANGUAGE_VERSION) ?: "(null)",
              (const char *)glGetString(GL_RENDERER) ?: "(null)",
              (int)glErr);

        // Read center pixel from currently-bound FBO (GLKView's FBO after blit)
        GLint viewport[4];
        glGetIntegerv(GL_VIEWPORT, viewport);
        int cx = viewport[2] / 2, cy = viewport[3] / 2;
        unsigned char pixel[4] = {0};
        glReadPixels(cx, cy, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
        NSLog(@"[VTKBridge] PostRender center pixel: R=%d G=%d B=%d A=%d  (viewport: %d x %d)",
              pixel[0], pixel[1], pixel[2], pixel[3], viewport[2], viewport[3]);

        // Check if volume mode — log volume-specific info
        if (_data->isVolumeMode && _data->volumeMapper) {
            NSLog(@"[VTKBridge] Volume mode active. SmartMapper: %s, LastUsedRenderMode: %d",
                  _data->volumeMapper->GetClassName(),
                  _data->volumeMapper->GetLastUsedRenderMode());
        }

        // Read a corner pixel too (should be background color)
        unsigned char cornerPixel[4] = {0};
        glReadPixels(5, 5, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, cornerPixel);
        NSLog(@"[VTKBridge] PostRender corner pixel: R=%d G=%d B=%d A=%d",
              cornerPixel[0], cornerPixel[1], cornerPixel[2], cornerPixel[3]);
    }
#else
    _data->renderWindow->Render();
#endif
}

// Custom blit removed — VTK's BlitToCurrent handles display→GLKView blit natively.

- (void)resizeTo:(CGSize)size {
    if (!_data->renderWindow || size.width <= 0 || size.height <= 0) return;

#if TARGET_OS_IPHONE
    // Ensure GL context is current
    [_renderView makeGLContextCurrent];

    // Use retina-aware pixel dimensions for VTK
    double scale = _renderView.glkView ? _renderView.glkView.contentScaleFactor : 1.0;
    int w = (int)(size.width * scale);
    int h = (int)(size.height * scale);
#else
    int w = (int)size.width;
    int h = (int)size.height;
#endif

    _data->renderWindow->SetSize(w, h);

    // Render via GLKView on iOS, directly on macOS
    [self render];

#if TARGET_OS_IPHONE
    // Resize GLKView's drawable if needed
    if (_renderView.glkView) {
        _renderView.glkView.frame = _renderView.bounds;
    }
#else
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
        // Terrain & other modes: keep user's camera angle, just fix clipping
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
