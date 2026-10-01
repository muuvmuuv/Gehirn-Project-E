// The core carries the self: a backend that proposes goals, plus a journal that outlives any
// backend. Canon puts a soul in the core and requires it to be compatible with the pilot;
// here that means one journal per pilot, and swapping the substrate keeps the soul.
module core

import x.json2
import os
import lcl

// Core is a backend that proposes goals and takes their outcomes back. main.v hq runs one,
// an LlmCore or a Cl1Core, beside the pilot's Memory.
pub interface Core {
	name() string
mut:
	propose(ctx lcl.Context) !lcl.Intent
	feedback(o lcl.Outcome)
}

// Memory is an append only journal. Its tail goes into every context; the whole file is the
// raw material for fine tuning a core on its own history later.
pub struct Memory {
	path string
	keep int
mut:
	items []string
}

struct Entry {
	t_ms i64
	text string
	kind string @[omitempty] // set on structured lines only, which never enter the tail
}

// open_memory loads the newest keep text entries of the journal at path.
pub fn open_memory(path string, keep int) Memory {
	mut texts := []string{}
	for line in os.read_lines(path) or { []string{} } {
		e := json2.decode[Entry](line) or { continue }
		if e.kind == '' && e.text != '' {
			texts << e.text
		}
	}
	start := if texts.len > keep { texts.len - keep } else { 0 }
	return Memory{
		path:  path
		keep:  keep
		items: texts[start..].clone()
	}
}

// add remembers text and appends it to the journal on disk.
pub fn (mut m Memory) add(text string) {
	m.items << text
	if m.items.len > m.keep {
		m.items.delete(0)
	}
	m.log(Entry{ t_ms: lcl.now_ms(), text: text })
}

// log appends entry to the journal on disk as one JSON line, leaving the remembered tail alone.
pub fn (m Memory) log[T](entry T) {
	m.append(json2.encode(entry))
}

// append writes one line to the journal on disk. It is kept out of the generic log: an or block
// there trips the V 0.5.2 checker (too many expr levels).
fn (m Memory) append(line string) {
	mut f := os.open_append(m.path) or { return }
	defer {
		f.close()
	}
	f.writeln(line) or {}
}

// recent is the newest n entries, oldest first.
pub fn (m Memory) recent(n int) []string {
	start := if m.items.len > n { m.items.len - n } else { 0 }
	return m.items[start..].clone()
}
