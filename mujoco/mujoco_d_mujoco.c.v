// MuJoCo: the one door to the physics engine of ADR-0008, a thin binding of MuJoCo's C API that
// compiles a model from MJCF text, steps it, and reads and writes the state a body needs, and
// knows nothing of LCL. It builds only with -d mujoco, and `just mujoco` builds the pinned static
// library into thirdparty/mujoco.
module mujoco

#flag -I @VMODROOT/thirdparty/mujoco/include

// V puts each @START_LIBS flag before the ones already there, so the archives land in the reverse
// of this order, libmujoco.a first and each dependency after what needs it, ahead of vlib's -lm
// and -lpthread, as in zenoh/zenoh.c.v.
#flag @VMODROOT/thirdparty/mujoco/lib/libminiz.a@START_LIBS
#flag @VMODROOT/thirdparty/mujoco/lib/libtinyxml2.a@START_LIBS
#flag @VMODROOT/thirdparty/mujoco/lib/libtinyobjloader.a@START_LIBS
#flag @VMODROOT/thirdparty/mujoco/lib/libqhullstatic_r.a@START_LIBS
#flag @VMODROOT/thirdparty/mujoco/lib/libccd.a@START_LIBS
#flag @VMODROOT/thirdparty/mujoco/lib/libmujoco.a@START_LIBS
#flag darwin -lc++
#flag linux -lstdc++
#flag linux -lm
#flag linux -lpthread
#include <mujoco/mujoco.h>

@[typedef]
struct C.mjsCompiler {
mut:
	usethread u8
}

@[typedef]
struct C.mjSpec {
mut:
	compiler C.mjsCompiler
}

@[typedef]
struct C.mjOption {
mut:
	timestep     f64
	disableflags int
}

@[typedef]
struct C.mjModel {
	nq     i64
	nv     i64
	nu     i64
	nmocap i64
mut:
	opt C.mjOption
}

@[typedef]
struct C.mjWarningStat {
	lastinfo int
	number   int
}

@[typedef]
struct C.mjContact {
	geom [2]int
}

@[typedef]
struct C.mjData {
	time      f64
	ncon      int
	qpos      &f64
	qvel      &f64
	ctrl      &f64
	mocap_pos &f64
	contact   &C.mjContact
	warning   [7]C.mjWarningStat
}

@[typedef]
struct C.mjLogMessage {
	level   int
	subject [1024]u8
}

fn C.mj_parseXMLString(xml &char, vfs voidptr, error &char, error_sz int) &C.mjSpec
fn C.mj_compile(s &C.mjSpec, vfs voidptr) &C.mjModel
fn C.mjs_getError(s &C.mjSpec) &char
fn C.mj_deleteSpec(s &C.mjSpec)
fn C.mj_makeData(m &C.mjModel) &C.mjData
fn C.mj_step(m &C.mjModel, d &C.mjData)
fn C.mj_forward(m &C.mjModel, d &C.mjData)
fn C.mj_name2id(m &C.mjModel, typ int, name &char) int
fn C.mju_error(format &char, msg &char)
fn C.mju_setLogHandler(handler fn (&C.mjLogMessage)) voidptr
fn C.mju_warningText(warning int, info usize) &char

// warnings is mjNWARNING, the number of warning counters in mjData.
const warnings = 7

fn init() {
	C.mju_setLogHandler(log)
}

// log is MuJoCo's log handler, on the thread that called MuJoCo, the field loop's. It replaces
// the default one, which appends every warning and error to MUJOCO_LOG.TXT in the working
// directory. It ignores info and debug messages, which reach a handler unfiltered, and warnings,
// which step reads from the counters. MuJoCo's error path must not return, so on an error it
// prints MuJoCo's message as one line and ends the process.
fn log(msg &C.mjLogMessage) {
	if msg.level != C.mjLOG_ERROR {
		return
	}
	eprintln('field: mujoco: ${line(&char(&msg.subject[0]))}')
	exit(1)
}

// line is MuJoCo's message s as one line.
fn line(s &char) string {
	return unsafe { cstring_to_vstring(s) }.trim_space().replace('\n', ' ')
}

// Model is a compiled MuJoCo model with its state, which body.Mujoco steps on the field loop's
// thread alone. Its compiler started no thread, and MuJoCo never resets it on its own.
// ponytail: never freed, since a field unit loads one for its life and a test a few; add a free
// with mj_deleteData and mj_deleteModel once something loads models over and over.
@[heap]
pub struct Model {
	m &C.mjModel
mut:
	d &C.mjData
}

// load parses and compiles the MJCF text xml, with the compiler's threads and autoreset switched
// off whatever xml says, for body.Mujoco. A model that fails to parse or compile returns MuJoCo's
// message as one line.
pub fn load(xml string) !&Model {
	mut why := [1000]u8{}
	mut spec := C.mj_parseXMLString(&char(xml.clone().str), unsafe { nil }, &char(&why[0]), why.len)
	if spec == unsafe { nil } {
		return error('mujoco: cannot parse the model: ${line(&char(&why[0]))}')
	}
	spec.compiler.usethread = 0
	mut m := C.mj_compile(spec, unsafe { nil })
	if m == unsafe { nil } {
		why_not := line(C.mjs_getError(spec))
		C.mj_deleteSpec(spec)
		return error('mujoco: cannot compile the model: ${why_not}')
	}
	C.mj_deleteSpec(spec)
	m.opt.disableflags |= C.mjDSBL_AUTORESET
	d := C.mj_makeData(m)
	C.mj_forward(m, d)
	return &Model{
		m: m
		d: d
	}
}

// step advances the model by one timestep. Once a warning counter has risen, an unstable state,
// a bad control or a full contact or constraint buffer among them, it raises it as MuJoCo's error,
// which ends the process through log, so no bad number reaches the caller.
pub fn (mut m Model) step() {
	C.mj_step(m.m, m.d)
	for i in 0 .. warnings {
		w := m.d.warning[i]
		if w.number > 0 {
			msg := '${line(C.mju_warningText(i, usize(w.lastinfo)))} Time = ${m.d.time:.4f} s.'
			C.mju_error(c'%s', &char(msg.str))
		}
	}
}

// time is the model's clock in seconds, timestep per step since load.
pub fn (m &Model) time() f64 {
	return m.d.time
}

// timestep is how far one step advances the model's clock, in seconds.
pub fn (m &Model) timestep() f64 {
	return m.m.opt.timestep
}

// qpos is a copy of the joint positions, one per coordinate in the model's joint order.
pub fn (m &Model) qpos() []f64 {
	return copied(m.d.qpos, m.m.nq)
}

// qvel is a copy of the joint velocities, one per degree of freedom in the model's joint order.
pub fn (m &Model) qvel() []f64 {
	return copied(m.d.qvel, m.m.nv)
}

// set_ctrl sets the control of actuator i, which holds until set again, and ignores an i the
// model has no actuator for.
pub fn (mut m Model) set_ctrl(i int, v f64) {
	if i >= 0 && i < m.m.nu {
		unsafe {
			m.d.ctrl[i] = v
		}
	}
}

// set_mocap moves mocap body i, in the model's body order, to x and y in meters and keeps its
// height, and ignores an i the model has no mocap body for.
pub fn (mut m Model) set_mocap(i int, x f64, y f64) {
	if i >= 0 && i < m.m.nmocap {
		unsafe {
			m.d.mocap_pos[3 * i] = x
			m.d.mocap_pos[3 * i + 1] = y
		}
	}
}

// geom is the id of the geom named name, or -1 when the model has none.
pub fn (m &Model) geom(name string) int {
	return C.mj_name2id(m.m, C.mjOBJ_GEOM, &char(name.clone().str))
}

// touching reports whether geom touches anything after the last step.
pub fn (m &Model) touching(geom int) bool {
	for i in 0 .. m.d.ncon {
		c := unsafe { m.d.contact[i] }
		if c.geom[0] == geom || c.geom[1] == geom {
			return true
		}
	}
	return false
}

fn copied(p &f64, n i64) []f64 {
	mut out := []f64{len: int(n)}
	for i in 0 .. out.len {
		out[i] = unsafe { p[i] }
	}
	return out
}
