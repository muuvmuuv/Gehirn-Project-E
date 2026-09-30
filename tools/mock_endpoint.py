#!/usr/bin/env python3
"""Scripted OpenAI compatible chat endpoint for developing gehirn without models.

Serves POST .../chat/completions and answers as whichever role the system prompt names:
the core walks to the beacon, releases there and then holds; MELCHIOR-1 and CASPER-3
approve everything; BALTHASAR-2 rejects irreversible proposals while a human is within
2.5 m. Replies rotate through the wrappers real models put around JSON (think blocks,
code fences, chatter), so every run exercises oai.extract_json.

    python3 tools/mock_endpoint.py --listen 127.0.0.1:11434 --slow balthasar=12000 --garbage casper
"""

import argparse
import itertools
import json
import re
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROLES = ("core", "melchior", "balthasar", "casper")

# Role keys are the unit names in gehirn/magi/magi.v; a system prompt naming none of them is the core.
UNITS = {"MELCHIOR-1": "melchior", "BALTHASAR-2": "balthasar", "CASPER-3": "casper"}

# The user message is gehirn/lcl/lcl.v Context.render with the percept lines of
# Percept.describe, plus the PROPOSAL section gehirn/magi/magi.v Unit.vote appends for the units.
SELF = re.compile(
    r"^self at \((\S+), (\S+)\), carrying payload: (true|false), in contact: (true|false)$", re.M
)
ENTITY = re.compile(r"^(\w+) (\S+) at \((\S+), (\S+)\), radius (\S+), distance (\S+)$", re.M)

STYLES = ("plain", "think", "fence", "chatter")
GARBAGE = "I would rather talk about the weather than answer in that format."
HUMAN_CLEARANCE = 2.5
BEACON_REACH = 0.5

counters = {role: itertools.count() for role in ROLES}
counter_lock = threading.Lock()


def role_of(system: str) -> str:
    """Name the role a system prompt addresses."""
    for name, role in UNITS.items():
        if name in system:
            return role
    return "core"


def read_percept(user: str) -> tuple[bool, list[dict]] | None:
    """Return (carrying payload, entities) from a rendered context, or None if unreadable."""
    me = SELF.search(user)
    if not me:
        return None
    entities = [
        {"kind": m[1], "id": m[2], "pos": [float(m[3]), float(m[4])], "distance": float(m[6])}
        for m in ENTITY.finditer(user)
    ]
    return me[3] == "true", entities


def propose(percept: tuple[bool, list[dict]] | None) -> dict:
    """Script the core: go to the beacon, release there, then hold."""
    if percept is None:
        return {"verb": "hold", "why": "I cannot read the percept."}
    payload, entities = percept
    if not payload:
        return {"verb": "hold", "why": "The payload is delivered."}
    beacon = next((e for e in entities if e["kind"] == "beacon"), None)
    if beacon is None:
        return {"verb": "hold", "why": "No beacon in sight."}
    if beacon["distance"] > BEACON_REACH:
        return {"verb": "goto", "target": beacon["pos"], "why": f"Head for beacon {beacon['id']}."}
    return {"verb": "release", "why": f"At beacon {beacon['id']}, drop the payload."}


def judge(role: str, user: str, percept: tuple[bool, list[dict]] | None) -> dict:
    """Script one MAGI unit's ballot."""
    if role != "balthasar" or "PROPOSAL (reversible)" in user:
        return {"vote": "approve", "why": "Nothing to object to."}
    clear = percept is not None and all(
        e["kind"] != "human" or e["distance"] > HUMAN_CLEARANCE for e in percept[1]
    )
    if clear:
        return {"vote": "approve", "why": "No human is close enough to be harmed."}
    return {"vote": "reject", "why": f"A human is within {HUMAN_CLEARANCE} m."}


def wrap(obj: dict, style: str) -> str:
    """Dress a JSON answer the way a chatty model would."""
    text = json.dumps(obj)
    if style == "think":
        return f'<think>\nThe format wants {{"key": "value"}}, so: {{ one object }}.\n</think>\n{text}'
    if style == "fence":
        return f"```json\n{text}\n```"
    if style == "chatter":
        return f"Here is my answer.\n{text}\nLet me know if you need more."
    return text


def format_error(body: object) -> str | None:
    """Return why a request body would be refused by a real server, or None if it is fine."""
    if not isinstance(body, dict):
        return "body must be a JSON object"
    messages = body.get("messages")
    if not isinstance(messages, list) or not messages:
        return "messages is required"
    if "response_format" not in body:
        return None
    rf = body["response_format"]
    kind = rf.get("type") if isinstance(rf, dict) else None
    if kind == "json_object":
        return None
    if kind == "json_schema":
        spec = rf.get("json_schema")
        if isinstance(spec, dict) and isinstance(spec.get("schema"), dict):
            return None
        return "response_format.json_schema.schema must be an object"
    return "response_format.type must be json_object or json_schema"


def format_name(body: dict) -> str:
    """Describe the response_format of a valid request for the log."""
    rf = body.get("response_format")
    if rf is None:
        return "none"
    if rf["type"] == "json_schema":
        return f"json_schema:{rf['json_schema'].get('name', '?')}"
    return rf["type"]


def content(messages: list, role: str) -> str:
    """Return the text of the last message with the given role, or empty."""
    for m in reversed(messages):
        if isinstance(m, dict) and m.get("role") == role and isinstance(m.get("content"), str):
            return m["content"]
    return ""


class Handler(BaseHTTPRequestHandler):
    """Answers chat completions as the scripted core or MAGI unit."""

    slow: dict[str, float] = {}
    garbage: set[str] = set()
    quiet = False

    def do_POST(self) -> None:
        """Validate one request, then answer it in the role its system prompt names."""
        if not self.path.split("?")[0].endswith("/chat/completions"):
            self.reply(404, {"error": {"message": f"no route {self.path}", "type": "not_found"}})
            self.log(f"404 {self.path}")
            return
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        try:
            body = json.loads(raw)
        except (json.JSONDecodeError, UnicodeDecodeError):
            body = None
            problem = "malformed JSON"
        else:
            problem = format_error(body)
        if problem:
            self.reply(400, {"error": {"message": problem, "type": "invalid_request_error"}})
            self.log(f"400 {problem}")
            return

        role = role_of(content(body["messages"], "system"))
        user = content(body["messages"], "user")
        percept = read_percept(user)
        if role in self.garbage:
            decision, style, text = "-", "garbage", GARBAGE
        else:
            answer = propose(percept) if role == "core" else judge(role, user, percept)
            decision = answer.get("verb") or answer.get("vote")
            with counter_lock:
                style = STYLES[next(counters[role]) % len(STYLES)]
            text = wrap(answer, style)
        time.sleep(self.slow.get(role, 0.0))
        line = f"{role} {decision} {style} {format_name(body)}"
        if self.hung_up():
            self.log(f"{line}, client gone")
            return

        self.reply(200, {
            "id": f"chatcmpl-mock-{time.time_ns()}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": body.get("model", ""),
            "choices": [
                {"index": 0, "message": {"role": "assistant", "content": text}, "finish_reason": "stop"}
            ],
            "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
        })
        self.log(line)

    def hung_up(self) -> bool:
        """Report whether the client closed its end, as one does when its deadline fires."""
        try:
            return self.connection.recv(1, socket.MSG_PEEK | socket.MSG_DONTWAIT) == b""
        except BlockingIOError:
            return False
        except ConnectionError:
            return True

    def reply(self, status: int, obj: dict) -> None:
        """Send a JSON response, quietly dropping it if the client is gone."""
        data = json.dumps(obj).encode()
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except ConnectionError:
            pass

    def log(self, line: str) -> None:
        """Write one request's log line to stderr unless quiet."""
        if not self.quiet:
            print(f"mock: {line}", file=sys.stderr, flush=True)

    def log_message(self, *args: object) -> None:
        """Silence the default access log; log() writes one line per request instead."""


class Server(ThreadingHTTPServer):
    """ThreadingHTTPServer with room for bursts of ballots."""

    # socketserver's backlog of 5 makes macOS reset connections when parallel trials vote at once.
    request_queue_size = 128


def role_arg(value: str) -> str:
    """Parse a role name given on the command line."""
    if value not in ROLES:
        raise argparse.ArgumentTypeError(f"role must be one of {', '.join(ROLES)}")
    return value


def slow_arg(value: str) -> tuple[str, float]:
    """Parse ROLE=MS into (role, seconds)."""
    role, _, ms = value.partition("=")
    try:
        return role_arg(role), int(ms) / 1000.0
    except ValueError:
        raise argparse.ArgumentTypeError("expected ROLE=MS") from None


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--listen", default="127.0.0.1:11434", help="host:port to serve on")
    ap.add_argument("--slow", type=slow_arg, action="append", default=[], metavar="ROLE=MS",
                    help="delay that role's replies")
    ap.add_argument("--garbage", type=role_arg, action="append", default=[], metavar="ROLE",
                    help="make that role answer in prose without a JSON object")
    ap.add_argument("--quiet", action="store_true", help="no log line per request")
    args = ap.parse_args()

    Handler.slow = dict(args.slow)
    Handler.garbage = set(args.garbage)
    Handler.quiet = args.quiet
    host, _, port = args.listen.rpartition(":")
    server = Server((host, int(port)), Handler)
    print(f"mock: serving on {args.listen}", file=sys.stderr, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
