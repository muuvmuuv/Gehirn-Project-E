// window_darwin.m is the bridge's one piece of Objective-C, which bridge/window.c.v includes on
// macOS the way vlib's gg includes gg_darwin.m. V compiles it with ARC (vlib/sokol, -fobjc-arc).
#include <objc/runtime.h>

static BOOL bridge_yes(id self, SEL cmd) {
	return YES;
}

// bridge_answer_yes makes every instance of cls answer YES to sel, keeping the types of the
// method cls inherits.
static void bridge_answer_yes(Class cls, SEL sel) {
	Method m = class_getInstanceMethod(cls, sel);
	class_replaceMethod(cls, sel, (IMP)bridge_yes, method_getTypeEncoding(m));
}

// bridge_dress_window lets sokol's borderless window become key and main, move when dragged
// anywhere and cast a shadow, none of which AppKit gives a window without a title bar: Esc would
// never reach it, and AppKit moves a window by its background only where the view under the mouse
// allows it, which sokol's view, being opaque, by default does not.
void bridge_dress_window(void* ptr) {
	NSWindow* window = (__bridge NSWindow*)ptr;
	if (window == nil) {
		return;
	}
	bridge_answer_yes([window class], @selector(canBecomeKeyWindow));
	bridge_answer_yes([window class], @selector(canBecomeMainWindow));
	bridge_answer_yes([window.contentView class], @selector(mouseDownCanMoveWindow));
	window.movableByWindowBackground = YES;
	window.hasShadow = YES;
	[window makeKeyAndOrderFront:nil];
}
