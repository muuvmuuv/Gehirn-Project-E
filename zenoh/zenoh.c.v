// Zenoh: the one door to the network between HQ and the field unit, a thin wrapper of zenoh-c
// that moves bytes under key expressions and knows nothing of LCL. ADR-0003 decides what travels
// and how; `just zenoh` fetches the pinned zenoh-c into thirdparty/zenoh-c.
module zenoh

import x.json2

#flag -I @VMODROOT/thirdparty/zenoh-c/include

// On Linux the archive needs the libraries that zenoh-c's lib/cmake/zenohc/zenohcConfig.cmake
// names, after it. V keeps only the first of two equal flags, and vlib's -ldl, -lpthread and -lm
// come before any module's, so @START_LIBS moves the archive to the front of the libraries.
#flag @VMODROOT/thirdparty/zenoh-c/lib/libzenohc.a@START_LIBS
#flag darwin -framework Foundation -framework Security
#flag linux -lrt
#flag linux -lpthread
#flag linux -lm
#flag linux -ldl
#include "zenoh.h"

@[typedef]
struct C.z_owned_config_t {}

@[typedef]
struct C.z_loaned_config_t {}

@[typedef]
struct C.z_moved_config_t {}

@[typedef]
struct C.z_owned_session_t {}

@[typedef]
struct C.z_loaned_session_t {}

@[typedef]
struct C.z_moved_session_t {}

@[typedef]
struct C.z_view_keyexpr_t {}

@[typedef]
struct C.z_loaned_keyexpr_t {}

@[typedef]
struct C.z_owned_publisher_t {}

@[typedef]
struct C.z_loaned_publisher_t {}

@[typedef]
struct C.z_moved_publisher_t {}

@[typedef]
struct C.z_owned_subscriber_t {}

@[typedef]
struct C.z_moved_subscriber_t {}

@[typedef]
struct C.z_owned_closure_sample_t {}

@[typedef]
struct C.z_moved_closure_sample_t {}

@[typedef]
struct C.z_owned_ring_handler_sample_t {}

@[typedef]
struct C.z_loaned_ring_handler_sample_t {}

@[typedef]
struct C.z_moved_ring_handler_sample_t {}

@[typedef]
struct C.z_owned_fifo_handler_sample_t {}

@[typedef]
struct C.z_loaned_fifo_handler_sample_t {}

@[typedef]
struct C.z_moved_fifo_handler_sample_t {}

@[typedef]
struct C.z_owned_sample_t {}

@[typedef]
struct C.z_loaned_sample_t {}

@[typedef]
struct C.z_moved_sample_t {}

@[typedef]
struct C.z_owned_bytes_t {}

@[typedef]
struct C.z_loaned_bytes_t {}

@[typedef]
struct C.z_moved_bytes_t {}

@[typedef]
struct C.z_owned_slice_t {}

@[typedef]
struct C.z_loaned_slice_t {}

@[typedef]
struct C.z_moved_slice_t {}

@[typedef]
struct C.z_view_string_t {}

@[typedef]
struct C.z_loaned_string_t {}

@[typedef]
struct C.z_owned_encoding_t {}

@[typedef]
struct C.z_loaned_encoding_t {}

@[typedef]
struct C.z_moved_encoding_t {}

// C.z_publisher_options_t names only the fields gehirn sets. The C compiler lays the struct out
// from the header that came with the library, unstable fields included.
@[typedef]
struct C.z_publisher_options_t {
mut:
	encoding           voidptr
	congestion_control int
	priority           int
	is_express         bool
}

@[typedef]
struct C.z_publisher_put_options_t {
mut:
	attachment voidptr
}

fn C.z_config_default(&C.z_owned_config_t) i8
fn C.z_config_loan_mut(&C.z_owned_config_t) &C.z_loaned_config_t
fn C.z_config_move(&C.z_owned_config_t) &C.z_moved_config_t
fn C.zc_config_insert_json5(&C.z_loaned_config_t, &char, &char) i8
fn C.z_config_drop(&C.z_moved_config_t)
fn C.z_open(&C.z_owned_session_t, &C.z_moved_config_t, voidptr) i8
fn C.z_session_loan(&C.z_owned_session_t) &C.z_loaned_session_t
fn C.z_session_move(&C.z_owned_session_t) &C.z_moved_session_t
fn C.z_session_drop(&C.z_moved_session_t)
fn C.z_view_keyexpr_from_str(&C.z_view_keyexpr_t, &char) i8
fn C.z_view_keyexpr_loan(&C.z_view_keyexpr_t) &C.z_loaned_keyexpr_t
fn C.z_keyexpr_as_view_string(&C.z_loaned_keyexpr_t, &C.z_view_string_t)
fn C.z_view_string_loan(&C.z_view_string_t) &C.z_loaned_string_t
fn C.z_string_data(&C.z_loaned_string_t) &u8
fn C.z_string_len(&C.z_loaned_string_t) usize
fn C.z_publisher_options_default(&C.z_publisher_options_t)
fn C.z_declare_publisher(&C.z_loaned_session_t, &C.z_owned_publisher_t, &C.z_loaned_keyexpr_t, &C.z_publisher_options_t) i8
fn C.z_publisher_loan(&C.z_owned_publisher_t) &C.z_loaned_publisher_t
fn C.z_publisher_move(&C.z_owned_publisher_t) &C.z_moved_publisher_t
fn C.z_publisher_drop(&C.z_moved_publisher_t)
fn C.z_publisher_put_options_default(&C.z_publisher_put_options_t)
fn C.z_publisher_put(&C.z_loaned_publisher_t, &C.z_moved_bytes_t, &C.z_publisher_put_options_t) i8
fn C.z_encoding_application_json() &C.z_loaned_encoding_t
fn C.z_encoding_clone(&C.z_owned_encoding_t, &C.z_loaned_encoding_t)
fn C.z_encoding_move(&C.z_owned_encoding_t) &C.z_moved_encoding_t
fn C.z_bytes_copy_from_buf(&C.z_owned_bytes_t, &u8, usize) i8
fn C.z_bytes_move(&C.z_owned_bytes_t) &C.z_moved_bytes_t
fn C.z_bytes_drop(&C.z_moved_bytes_t)
fn C.z_bytes_to_slice(&C.z_loaned_bytes_t, &C.z_owned_slice_t) i8
fn C.z_slice_loan(&C.z_owned_slice_t) &C.z_loaned_slice_t
fn C.z_slice_move(&C.z_owned_slice_t) &C.z_moved_slice_t
fn C.z_slice_drop(&C.z_moved_slice_t)
fn C.z_slice_data(&C.z_loaned_slice_t) &u8
fn C.z_slice_len(&C.z_loaned_slice_t) usize
fn C.z_ring_channel_sample_new(&C.z_owned_closure_sample_t, &C.z_owned_ring_handler_sample_t, usize)
fn C.z_fifo_channel_sample_new(&C.z_owned_closure_sample_t, &C.z_owned_fifo_handler_sample_t, usize)
fn C.z_closure_sample_move(&C.z_owned_closure_sample_t) &C.z_moved_closure_sample_t
fn C.z_declare_subscriber(&C.z_loaned_session_t, &C.z_owned_subscriber_t, &C.z_loaned_keyexpr_t, &C.z_moved_closure_sample_t, voidptr) i8
fn C.z_subscriber_move(&C.z_owned_subscriber_t) &C.z_moved_subscriber_t
fn C.z_subscriber_drop(&C.z_moved_subscriber_t)
fn C.z_ring_handler_sample_loan(&C.z_owned_ring_handler_sample_t) &C.z_loaned_ring_handler_sample_t
fn C.z_ring_handler_sample_move(&C.z_owned_ring_handler_sample_t) &C.z_moved_ring_handler_sample_t
fn C.z_ring_handler_sample_drop(&C.z_moved_ring_handler_sample_t)
fn C.z_ring_handler_sample_recv(&C.z_loaned_ring_handler_sample_t, &C.z_owned_sample_t) i8
fn C.z_ring_handler_sample_try_recv(&C.z_loaned_ring_handler_sample_t, &C.z_owned_sample_t) i8
fn C.z_fifo_handler_sample_loan(&C.z_owned_fifo_handler_sample_t) &C.z_loaned_fifo_handler_sample_t
fn C.z_fifo_handler_sample_move(&C.z_owned_fifo_handler_sample_t) &C.z_moved_fifo_handler_sample_t
fn C.z_fifo_handler_sample_drop(&C.z_moved_fifo_handler_sample_t)
fn C.z_fifo_handler_sample_recv(&C.z_loaned_fifo_handler_sample_t, &C.z_owned_sample_t) i8
fn C.z_fifo_handler_sample_try_recv(&C.z_loaned_fifo_handler_sample_t, &C.z_owned_sample_t) i8
fn C.z_sample_loan(&C.z_owned_sample_t) &C.z_loaned_sample_t
fn C.z_sample_move(&C.z_owned_sample_t) &C.z_moved_sample_t
fn C.z_sample_drop(&C.z_moved_sample_t)
fn C.z_sample_keyexpr(&C.z_loaned_sample_t) &C.z_loaned_keyexpr_t
fn C.z_sample_payload(&C.z_loaned_sample_t) &C.z_loaned_bytes_t
fn C.z_sample_attachment(&C.z_loaned_sample_t) &C.z_loaned_bytes_t

// z_ok is zenoh-c's Z_OK, the z_result_t of success.
const z_ok = i8(0)

// Config is where a Session listens and which endpoints it dials, as Zenoh locators such as
// tcp/127.0.0.1:7447. HQ and the field unit each open one Session from it.
pub struct Config {
pub:
	listen  []string
	connect []string
}

// Congestion is what a put does when the send queue is full: drop the message, or block until
// there is room. ADR-0003 gives each stream one.
pub enum Congestion {
	block = 0
	drop  = 1
}

// Priority is zenoh-c's z_priority_t: a put waits only behind puts of the same or a higher
// priority. ADR-0003 gives each stream one.
pub enum Priority {
	real_time        = 1
	interactive_high = 2
	interactive_low  = 3
	data_high        = 4
	data             = 5
	data_low         = 6
	background       = 7
}

// Qos is how a Publisher's puts travel: what a full queue does to them, their priority, and
// whether they skip batching.
pub struct Qos {
pub:
	congestion Congestion = .drop
	priority   Priority   = .data
	express    bool
}

// Queue is how a Subscriber holds samples until they are read: a ring that keeps the newest cap
// and drops the oldest, or a FIFO of cap that blocks Zenoh's thread while it is full, so whoever
// reads a FIFO drains it at once.
pub struct Queue {
pub:
	ring bool
	cap  int = 1
}

// Sample is one message a Subscriber received: its key expression, its payload and its
// attachment, empty when it had none.
pub struct Sample {
pub:
	key        string
	payload    []u8
	attachment []u8
}

// Session is one open Zenoh session. Publishers and Subscribers declared on it must close
// before it does.
@[heap]
pub struct Session {
mut:
	s C.z_owned_session_t
}

// Publisher puts payloads under one key expression with one Qos, as JSON.
@[heap]
pub struct Publisher {
mut:
	p C.z_owned_publisher_t
}

// Subscriber receives the samples put under one key expression into its Queue.
@[heap]
pub struct Subscriber {
	ring bool
mut:
	sub C.z_owned_subscriber_t
	rh  C.z_owned_ring_handler_sample_t
	fh  C.z_owned_fifo_handler_sample_t
}

// open starts a peer session on c's endpoints. Multicast scouting stays off and the listen
// endpoints are always set, so the session links only to what c names and listens nowhere else.
pub fn open(c Config) !&Session {
	mut cfg := C.z_owned_config_t{}
	if C.z_config_default(&cfg) != z_ok {
		return error('zenoh: cannot build a default config')
	}
	settings := {
		'mode':                       '"peer"'
		'scouting/multicast/enabled': 'false'
		'listen/endpoints':           json2.encode(c.listen)
		'connect/endpoints':          json2.encode(c.connect)
	}
	for key, value in settings {
		if C.zc_config_insert_json5(C.z_config_loan_mut(&cfg), &char(key.str), &char(value.str)) != z_ok {
			C.z_config_drop(C.z_config_move(&cfg))
			return error('zenoh: config rejects ${key}')
		}
	}
	mut s := &Session{}
	if C.z_open(&s.s, C.z_config_move(&cfg), unsafe { nil }) != z_ok {
		return error('zenoh: cannot open a session on the configured endpoints')
	}
	return s
}

// close ends the session.
pub fn (mut s Session) close() {
	C.z_session_drop(C.z_session_move(&s.s))
}

// publisher declares a Publisher on key, a key expression such as gehirn/eva01/goal.
pub fn (s &Session) publisher(key string, q Qos) !&Publisher {
	mut ke := C.z_view_keyexpr_t{}
	if C.z_view_keyexpr_from_str(&ke, &char(key.str)) != z_ok {
		return error('zenoh: ${key} is not a key expression')
	}
	mut enc := C.z_owned_encoding_t{}
	C.z_encoding_clone(&enc, C.z_encoding_application_json())
	mut opts := C.z_publisher_options_t{}
	C.z_publisher_options_default(&opts)
	opts.encoding = C.z_encoding_move(&enc)
	opts.congestion_control = int(q.congestion)
	opts.priority = int(q.priority)
	opts.is_express = q.express
	mut p := &Publisher{}
	if C.z_declare_publisher(C.z_session_loan(&s.s), &p.p, C.z_view_keyexpr_loan(&ke), &opts) != z_ok {
		return error('zenoh: cannot declare a publisher on ${key}')
	}
	return p
}

// put sends payload with attachment, which may be empty.
pub fn (p &Publisher) put(payload []u8, attachment []u8) ! {
	mut body := C.z_owned_bytes_t{}
	if C.z_bytes_copy_from_buf(&body, payload.data, usize(payload.len)) != z_ok {
		return error('zenoh: cannot copy a payload of ${payload.len} bytes')
	}
	mut opts := C.z_publisher_put_options_t{}
	C.z_publisher_put_options_default(&opts)
	mut extra := C.z_owned_bytes_t{}
	if attachment.len > 0 {
		if C.z_bytes_copy_from_buf(&extra, attachment.data, usize(attachment.len)) != z_ok {
			C.z_bytes_drop(C.z_bytes_move(&body))
			return error('zenoh: cannot copy an attachment of ${attachment.len} bytes')
		}
		opts.attachment = C.z_bytes_move(&extra)
	}
	if C.z_publisher_put(C.z_publisher_loan(&p.p), C.z_bytes_move(&body), &opts) != z_ok {
		return error('zenoh: put failed')
	}
}

// close undeclares the publisher.
pub fn (mut p Publisher) close() {
	C.z_publisher_drop(C.z_publisher_move(&p.p))
}

// subscriber declares a Subscriber on key, a key expression that may hold wildcards. Samples go
// to q through zenoh-c's channel handler, so no V code runs on a Zenoh thread (ADR-0003).
pub fn (s &Session) subscriber(key string, q Queue) !&Subscriber {
	if q.cap < 1 {
		return error('zenoh: a queue needs room for at least one sample, not ${q.cap}')
	}
	mut ke := C.z_view_keyexpr_t{}
	if C.z_view_keyexpr_from_str(&ke, &char(key.str)) != z_ok {
		return error('zenoh: ${key} is not a key expression')
	}
	mut closure := C.z_owned_closure_sample_t{}
	mut sub := &Subscriber{
		ring: q.ring
	}
	if q.ring {
		C.z_ring_channel_sample_new(&closure, &sub.rh, usize(q.cap))
	} else {
		C.z_fifo_channel_sample_new(&closure, &sub.fh, usize(q.cap))
	}
	if C.z_declare_subscriber(C.z_session_loan(&s.s), &sub.sub, C.z_view_keyexpr_loan(&ke),
		C.z_closure_sample_move(&closure), unsafe { nil }) != z_ok {
		sub.drop_handler()
		return error('zenoh: cannot declare a subscriber on ${key}')
	}
	return sub
}

// recv waits for the next sample. It fails only once the subscriber is gone.
pub fn (s &Subscriber) recv() !Sample {
	mut smp := C.z_owned_sample_t{}
	rc := if s.ring {
		C.z_ring_handler_sample_recv(C.z_ring_handler_sample_loan(&s.rh), &smp)
	} else {
		C.z_fifo_handler_sample_recv(C.z_fifo_handler_sample_loan(&s.fh), &smp)
	}
	if rc != z_ok {
		return error('zenoh: the subscriber is closed')
	}
	return take(mut smp)
}

// try_recv is the next sample if one is waiting, without blocking.
pub fn (s &Subscriber) try_recv() ?Sample {
	mut smp := C.z_owned_sample_t{}
	rc := if s.ring {
		C.z_ring_handler_sample_try_recv(C.z_ring_handler_sample_loan(&s.rh), &smp)
	} else {
		C.z_fifo_handler_sample_try_recv(C.z_fifo_handler_sample_loan(&s.fh), &smp)
	}
	if rc != z_ok {
		return none
	}
	return take(mut smp)
}

// close undeclares the subscriber and frees its queue. Only the thread that reads s may close
// it, and never while a recv waits, which would read freed memory.
pub fn (mut s Subscriber) close() {
	C.z_subscriber_drop(C.z_subscriber_move(&s.sub))
	s.drop_handler()
}

fn (mut s Subscriber) drop_handler() {
	if s.ring {
		C.z_ring_handler_sample_drop(C.z_ring_handler_sample_move(&s.rh))
	} else {
		C.z_fifo_handler_sample_drop(C.z_fifo_handler_sample_move(&s.fh))
	}
}

// take copies an owned sample into V memory and drops it.
fn take(mut smp C.z_owned_sample_t) Sample {
	loaned := C.z_sample_loan(&smp)
	mut view := C.z_view_string_t{}
	C.z_keyexpr_as_view_string(C.z_sample_keyexpr(loaned), &view)
	str := C.z_view_string_loan(&view)
	key := unsafe { C.z_string_data(str).vstring_with_len(int(C.z_string_len(str))).clone() }
	payload := copy_bytes(C.z_sample_payload(loaned))
	extra := C.z_sample_attachment(loaned)
	attachment := if isnil(extra) { []u8{} } else { copy_bytes(extra) }
	C.z_sample_drop(C.z_sample_move(&smp))
	return Sample{
		key:        key
		payload:    payload
		attachment: attachment
	}
}

// copy_bytes copies loaned Zenoh bytes into a V array.
fn copy_bytes(b &C.z_loaned_bytes_t) []u8 {
	mut sl := C.z_owned_slice_t{}
	if C.z_bytes_to_slice(b, &sl) != z_ok {
		return []u8{}
	}
	l := C.z_slice_loan(&sl)
	out := unsafe { C.z_slice_data(l).vbytes(int(C.z_slice_len(l))).clone() }
	C.z_slice_drop(C.z_slice_move(&sl))
	return out
}
