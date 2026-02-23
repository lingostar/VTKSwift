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

/// Manages a VTK rendering pipeline that displays a 3D sphere.
/// Wraps VTK C++ objects behind an Objective-C interface for Swift interop.
@interface VTKBridge : NSObject

/// Initialize the VTK bridge with a target frame size.
/// @param frame The initial frame rectangle for the render view.
- (instancetype)initWithFrame:(CGRect)frame;

/// Set up the VTK rendering pipeline and add a sphere actor.
- (void)setupSphere;

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
