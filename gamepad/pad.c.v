module main

// The one door to SDL (ADR-0006): the 15 functions of SDL2's game controller API the gamepad
// needs, from SDL 2.0.9 on for rumble. sdl2-compat runs them on SDL3 where a system has only that.
#flag -DSDL_MAIN_HANDLED
#pkgconfig --cflags --libs sdl2
#include <SDL.h>

@[typedef]
struct C.SDL_GameController {}

@[typedef]
struct C.SDL_Event {}

fn C.SDL_SetHint(name &char, value &char) bool
fn C.SDL_Init(flags u32) int
fn C.SDL_Quit()
fn C.SDL_GetError() &char
fn C.SDL_PollEvent(event &C.SDL_Event) int
fn C.SDL_NumJoysticks() int
fn C.SDL_IsGameController(index int) bool
fn C.SDL_GameControllerNameForIndex(index int) &char
fn C.SDL_GameControllerOpen(index int) &C.SDL_GameController
fn C.SDL_GameControllerClose(gc &C.SDL_GameController)
fn C.SDL_GameControllerGetAttached(gc &C.SDL_GameController) bool
fn C.SDL_GameControllerName(gc &C.SDL_GameController) &char
fn C.SDL_GameControllerGetAxis(gc &C.SDL_GameController, axis int) i16
fn C.SDL_GameControllerGetButton(gc &C.SDL_GameController, button int) u8
fn C.SDL_GameControllerRumble(gc &C.SDL_GameController, low u16, high u16, ms u32) int

// Axis is a stick in SDL's controller layout, SDL_GameControllerAxis.
enum Axis {
	leftx = C.SDL_CONTROLLER_AXIS_LEFTX
	lefty = C.SDL_CONTROLLER_AXIS_LEFTY
}

// Button is a button in SDL's controller layout, SDL_GameControllerButton: Back is View on an
// Xbox pad and Share on a PlayStation one, Start is Menu or Options, and leftshoulder is LB or L1.
enum Button {
	back         = C.SDL_CONTROLLER_BUTTON_BACK
	start        = C.SDL_CONTROLLER_BUTTON_START
	leftshoulder = C.SDL_CONTROLLER_BUTTON_LEFTSHOULDER
}

// Pad is one open game controller, or none when gc is nil.
struct Pad {
	gc   &C.SDL_GameController = unsafe { nil }
	name string
}

// sdl_start starts SDL's game controller subsystem. The gamepad has no window, so SDL must pass
// it controller events in the background, and SDL must leave SIGINT alone so Ctrl-C ends it.
fn sdl_start() ! {
	C.SDL_SetHint(c'SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS', c'1')
	C.SDL_SetHint(c'SDL_NO_SIGNAL_HANDLERS', c'1')
	if C.SDL_Init(u32(C.SDL_INIT_GAMECONTROLLER)) != 0 {
		return error('SDL_Init failed: ${c_text(C.SDL_GetError())}')
	}
}

// sdl_quit stops SDL.
fn sdl_quit() {
	C.SDL_Quit()
}

// pump drains SDL's events, which updates every controller's state and notices one plugged in or
// pulled out.
fn pump() {
	mut ev := C.SDL_Event{}
	for C.SDL_PollEvent(&ev) != 0 {}
}

// controllers is the name of every attached joystick SDL knows as a game controller.
fn controllers() []string {
	mut names := []string{}
	for i in 0 .. C.SDL_NumJoysticks() {
		if C.SDL_IsGameController(i) {
			names << c_text(C.SDL_GameControllerNameForIndex(i))
		}
	}
	return names
}

// open_pad opens the first game controller, or returns a Pad that is not open.
fn open_pad() Pad {
	for i in 0 .. C.SDL_NumJoysticks() {
		if !C.SDL_IsGameController(i) {
			continue
		}
		gc := C.SDL_GameControllerOpen(i)
		if gc != unsafe { nil } {
			return Pad{
				gc:   gc
				name: c_text(C.SDL_GameControllerName(gc))
			}
		}
	}
	return Pad{}
}

// is_open reports whether p holds a controller.
fn (p Pad) is_open() bool {
	return p.gc != unsafe { nil }
}

// attached reports whether the controller is still plugged in.
fn (p Pad) attached() bool {
	return C.SDL_GameControllerGetAttached(p.gc)
}

// axis is a stick's position, -1 to 1, with y pointing down as SDL reads it.
fn (p Pad) axis(a Axis) f64 {
	return f64(C.SDL_GameControllerGetAxis(p.gc, int(a))) / 32767.0
}

// pressed reports whether a button is down.
fn (p Pad) pressed(b Button) bool {
	return C.SDL_GameControllerGetButton(p.gc, int(b)) != 0
}

// rumble runs the low and high frequency motors, each 0 to 1, for ms milliseconds, replacing the
// rumble before. A controller without motors ignores it.
fn (p Pad) rumble(low f64, high f64, ms u32) {
	C.SDL_GameControllerRumble(p.gc, u16(low * 65535.0), u16(high * 65535.0), ms)
}

// close closes the controller.
fn (p Pad) close() {
	C.SDL_GameControllerClose(p.gc)
}

// c_text is a C string from SDL as a V string, or unnamed for a null pointer.
fn c_text(s &char) string {
	if s == unsafe { nil } {
		return 'unnamed'
	}
	return unsafe { cstring_to_vstring(s) }
}
