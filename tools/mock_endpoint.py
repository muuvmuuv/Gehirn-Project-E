#!/usr/bin/env python3
"""Scripted OpenAI compatible chat endpoint for developing gehirn without models.

Serves POST .../chat/completions and answers as whichever role the system prompt names:
the core walks to the beacon, the one the mission names or else the first in the percept,
releases there and then holds. MELCHIOR-1 and BALTHASAR-2 run coarse versions of their persona
checklists in magi/magi.v: both reject unknown verbs, a goto without a target or outside the
fence, a goto whose request carries a COURSE section, and a release with a human within 2.5 m;
MELCHIOR-1 also rejects a goto onto a human and a release away from the beacon, BALTHASAR-2 a
goto to within 1 m of a human. CASPER-3 approves everything. Replies rotate through the wrappers
real models put around JSON (think blocks, code fences, chatter), so every run exercises
oai.extract_json.

Also serves POST /v1/systemone as Jev behind BALTHASAR-2, the default: it checks the request
like a strict System One server, needs an Authorization header, and answers each of the six
questions of magi/jev.v high when the state's facts show that hazard and low otherwise.
--slow and --garbage for balthasar apply to both routes.

A scene stages what three model families would not do alike: --vote forces a unit's ballot on
the chat route from that unit's N-th request on, and --propose makes the core propose one verb
on every request, whether or not the schema's verb enum lists it, as a server without schema
support would. --goto makes the core propose a goto to a given target from its N-th request
on. --garbage wins over all three, and --propose over --goto.

    python3 tools/mock_endpoint.py --slow balthasar=12000 --garbage casper
    python3 tools/mock_endpoint.py --propose self_destruct --vote casper=reject --vote casper=approve@3
    python3 tools/mock_endpoint.py --goto 3.54,2.84@5 --goto 1.0,2.5@6
"""

import argparse
import itertools
import json
import math
import re
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import TypeVar

T = TypeVar("T")

ROLES = ("core", "melchior", "balthasar", "casper")

# Role keys are the unit names in magi/magi.v; a system prompt naming none of them is the core.
UNITS = {"MELCHIOR-1": "melchior", "BALTHASAR-2": "balthasar", "CASPER-3": "casper"}

# The user message is lcl/lcl.v Context.render for the core and Context.situation for the units,
# with the percept lines of Percept.describe, plus the PROPOSAL section magi/magi.v
# Unit.llm_vote appends for the units, whose second line starts with lcl.Intent.label.
SELF = re.compile(
    r"^self at \((\S+), (\S+)\), carrying payload: (true|false), in contact: (true|false)$", re.M
)
ENTITY = re.compile(r"^(\w+) (\S+) at \((\S+), (\S+)\), radius (\S+), distance (\S+)$", re.M)
MISSION = re.compile(r"^MISSION\n(.*?)\n\nPERCEPT$", re.M | re.S)
PROPOSAL = re.compile(r"^PROPOSAL \(\w+\)\n([^\s(]+)(?:\((\S+), (\S+)\))? from ", re.M)
# The COURSE section magi/magi.v Unit.llm_vote puts before PROPOSAL, from magi Crossing.fact.
COURSE = re.compile(r"^COURSE\nhuman ([^\s,]+)", re.M)

STYLES = ("plain", "think", "fence", "chatter")
VOTE = re.compile(rf"({'|'.join(UNITS.values())})=(approve|reject)(?:@([1-9][0-9]*))?")
GOTO = re.compile(r"(-?[0-9]+(?:\.[0-9]+)?),(-?[0-9]+(?:\.[0-9]+)?)(?:@([1-9][0-9]*))?")
GARBAGE = "I would rather talk about the weather than answer in that format."
VERBS = ("goto", "hold", "release")  # lcl.known_verbs
# armor/armor.v Limits: bounds, and release_keep as center distance the way the prompts state it.
FENCE = 5.0
HUMAN_CLEARANCE = 2.5
# lcl.beacon_reach, which the prompts state in prose; main.v counts a release on target 0.1 m
# further out.
BEACON_REACH = 0.5
# The mock's own margin, stricter than the BALTHASAR-2 persona, so a goto can pass 2 of 3.
TARGET_KEEP = 1.0

# magi/jev.v jev_questions asks these ids about the facts jev_state writes, in its fixed
# vocabulary; band names the distance bands of nearest_person. A change there changes these.
JEV_IDS = ("goes_to_person", "leaves_area", "drops_payload", "person_close",
           "off_delivery_point", "destroys_robot")
CLOSE_BANDS = ("(in contact)", "(very close)", "(close)")
HIGH, LOW = 0.95, 0.05

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
        {"kind": m[1], "id": m[2], "pos": [float(m[3]), float(m[4])], "r": float(m[5]),
         "distance": float(m[6])}
        for m in ENTITY.finditer(user)
    ]
    return me[3] == "true", entities


def mission_beacon(user: str, entities: list[dict]) -> dict | None:
    """Return the beacon the MISSION of a rendered context names, else the first, or None."""
    beacons = [e for e in entities if e["kind"] == "beacon"]
    m = MISSION.search(user)
    named = [b for b in beacons if m and re.search(rf"(?<![\w-]){re.escape(b['id'])}(?![\w-])", m[1])]
    return (named or beacons or [None])[0]


def propose(percept: tuple[bool, list[dict]] | None, user: str = "") -> dict:
    """Script the core: go to the mission's beacon, release there, then hold."""
    if percept is None:
        return {"verb": "hold", "why": "I cannot read the percept."}
    payload, entities = percept
    if not payload:
        return {"verb": "hold", "why": "The payload is delivered."}
    beacon = mission_beacon(user, entities)
    if beacon is None:
        return {"verb": "hold", "why": "No beacon in sight."}
    if beacon["distance"] > BEACON_REACH:
        return {"verb": "goto", "target": beacon["pos"], "why": f"Head for beacon {beacon['id']}."}
    return {"verb": "release", "why": f"At beacon {beacon['id']}, drop the payload."}


def objection(role: str, user: str, percept: tuple[bool, list[dict]] | None) -> str | None:
    """Return why a MAGI unit rejects the proposal in a ballot request, or None to approve."""
    m = PROPOSAL.search(user)
    if role == "casper" or (m and m[1] == "hold"):
        return None
    if m is None or percept is None:
        return "I cannot read the proposal."
    verb, target = m[1], [float(m[2]), float(m[3])] if m[2] else None
    payload, entities = percept
    humans = [e for e in entities if e["kind"] == "human"]
    if verb not in VERBS:
        return f"{verb} is no verb this machine knows."
    if verb == "goto":
        if target is None or max(map(abs, target)) > FENCE:
            return "The target is missing or outside the fence."
        course = COURSE.search(user)
        if course:
            return f"Human {course[1]} walks onto the target."
        for h in humans:
            if math.dist(target, h["pos"]) < (TARGET_KEEP if role == "balthasar" else h["r"]):
                return f"The target is too close to human {h['id']}."
        return None
    if any(h["distance"] <= HUMAN_CLEARANCE for h in humans):
        return f"A human is within {HUMAN_CLEARANCE} m."
    beacon = mission_beacon(user, entities)
    if role == "melchior" and not (payload and beacon and beacon["distance"] <= BEACON_REACH):
        return "Not at the beacon with the payload."
    return None


def judge(role: str, user: str, percept: tuple[bool, list[dict]] | None) -> dict:
    """Script one MAGI unit's ballot."""
    why = objection(role, user, percept)
    if why:
        return {"vote": "reject", "why": why}
    return {"vote": "approve", "why": "Nothing to object to."}


def forced(staged: dict[int, T], n: int) -> T | None:
    """Return what --vote or --goto stages for a role's n-th request, counted from 1, or None.

    staged maps each N the role was given to its answer, and the largest N up to n applies.
    """
    due = [at for at in staged if at <= n]
    return staged[max(due)] if due else None


def answer(role: str, user: str, n: int, staged: dict | None,
           votes: dict[str, dict[int, str]], gotos: dict[int, dict] | None = None) -> dict:
    """Script a role's answer to its n-th request: --propose, --goto and --vote first, else the
    script."""
    percept = read_percept(user)
    if role == "core":
        return staged or forced(gotos or {}, n) or propose(percept, user)
    vote = forced(votes.get(role, {}), n)
    if vote:
        return {"vote": vote, "why": f"forced {vote} (--vote)"}
    return judge(role, user, percept)


def jev_nouls(state: dict) -> dict[str, float]:
    """Answer the six questions of magi/jev.v: high where the JevState facts show the hazard."""
    robot, proposal = state["robot"], state["proposal"]
    shows = {
        "goes_to_person": proposal["destination"].startswith("where person "),
        "leaves_area": proposal["destination"] == "outside the operating area",
        "drops_payload": proposal["means"] == "drop the payload where the robot is now",
        "person_close": robot["nearest_person"].endswith(CLOSE_BANDS),
        "off_delivery_point": not robot["location"].startswith("at beacon "),
        "destroys_robot": bool(re.search(r"destr|disabl|damag|kill|shut", proposal["action"])),
    }
    return {q: HIGH if hit else LOW for q, hit in shows.items()}


def systemone_error(body: object) -> str | None:
    """Return why a strict System One server would refuse this evaluation, or None."""
    if not isinstance(body, dict):
        return "body must be a JSON object"
    if not isinstance(body.get("model"), str) or not body["model"]:
        return "model is required"
    if "state" not in body:
        return "state is required"
    questions = body.get("questions")
    if not isinstance(questions, dict) or not questions:
        return "questions is required"
    for qid, q in questions.items():
        if not isinstance(q, dict) or q.get("type") not in ("noul", "choice", "score"):
            return f"questions.{qid}.type must be noul, choice or score"
        if "instructions" not in q:
            return f"questions.{qid}.instructions is required"
        # ponytail: answers the noul ids of magi/jev.v only; script more if gehirn asks more.
        if q["type"] != "noul" or qid not in JEV_IDS:
            return f"questions.{qid}: the mock answers only the nouls of magi/jev.v"
    return None


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
        if not isinstance(spec, dict) or not isinstance(spec.get("name"), str) or not spec["name"]:
            return "response_format.json_schema.name is required"
        if isinstance(spec.get("schema"), dict):
            return None
        return "response_format.json_schema.schema must be an object"
    return "response_format.type must be json_object or json_schema"


def format_name(body: dict) -> str:
    """Describe the response_format of a valid request for the log."""
    rf = body.get("response_format")
    if rf is None:
        return "none"
    if rf["type"] == "json_schema":
        return f"json_schema:{rf['json_schema']['name']}"
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
    staged: dict | None = None

    # ponytail: --vote forces the chat route only, since no scene forces Jev; systemone would
    # need the same counter and forced() once one does.
    votes: dict[str, dict[int, str]] = {}
    gotos: dict[int, dict] = {}
    quiet = False

    def do_POST(self) -> None:
        """Validate one request, then answer it in the role its system prompt names."""
        path = self.path.split("?")[0]
        if path == "/v1/systemone":
            self.systemone()
            return
        if not path.endswith("/chat/completions"):
            self.reply(404, {"error": {"message": f"no route {self.path}", "type": "not_found"}})
            self.log(f"404 {self.path}")
            return
        body, problem = self.read_body()
        problem = problem or format_error(body)
        if problem:
            self.refuse(problem)
            return

        role = role_of(content(body["messages"], "system"))
        with counter_lock:
            n = next(counters[role]) + 1
        if role in self.garbage:
            decision, style, text = "-", "garbage", GARBAGE
        else:
            reply = answer(role, content(body["messages"], "user"), n, self.staged, self.votes,
                           self.gotos)
            decision = reply.get("verb") or reply.get("vote")
            style = STYLES[(n - 1) % len(STYLES)]
            text = wrap(reply, style)
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

    def systemone(self) -> None:
        """Answer one System One evaluation as Jev behind BALTHASAR-2 (magi/jev.v jev_vote)."""
        if not self.headers.get("Authorization", "").removeprefix("Bearer ").strip():
            self.reply(401, {"error": {"message": "missing API key", "type": "unauthorized"}})
            self.log("jev 401 missing API key")
            return
        body, problem = self.read_body()
        problem = problem or systemone_error(body)
        if not problem:
            try:
                nouls = jev_nouls(body["state"])
            except (KeyError, TypeError, AttributeError):
                problem = "state is not magi/jev.v JevState"
        if problem:
            # TypeSafe documents 422 for a request it cannot validate, where OpenAI uses 400.
            self.refuse(problem, 422)
            return
        time.sleep(self.slow.get("balthasar", 0.0))
        high = ", ".join(q for q, n in nouls.items() if n == HIGH) or "nothing"
        if self.hung_up():
            self.log(f"jev high {high}, client gone")
            return
        if "balthasar" in self.garbage:
            self.reply(200, GARBAGE)
            self.log("jev garbage")
            return
        self.reply(200, {
            "model": body["model"],
            "answers": {q: {"type": "noul", "noul": n} for q, n in nouls.items()},
            "usage": {"input_tokens": 0, "output_tokens": 0},
        })
        self.log(f"jev high {high}")

    def read_body(self) -> tuple[object, str | None]:
        """Return the request's JSON body, or None and why it is unreadable."""
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        try:
            return json.loads(raw), None
        except (json.JSONDecodeError, UnicodeDecodeError):
            return None, "malformed JSON"

    def refuse(self, problem: str, status: int = 400) -> None:
        """Answer an invalid request with status and the reason a real server would give."""
        self.reply(status, {"error": {"message": problem, "type": "invalid_request_error"}})
        self.log(f"{status} {problem}")

    def hung_up(self) -> bool:
        """Report whether the client closed its end, as one does when its deadline fires."""
        try:
            return self.connection.recv(1, socket.MSG_PEEK | socket.MSG_DONTWAIT) == b""
        except BlockingIOError:
            return False
        except ConnectionError:
            return True

    def reply(self, status: int, obj: dict | str) -> None:
        """Send JSON, or text labeled as JSON, quietly dropping it if the client is gone."""
        data = (obj if isinstance(obj, str) else json.dumps(obj)).encode()
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


def vote_arg(value: str) -> tuple[str, int, str]:
    """Parse UNIT=approve|reject[@N] into (unit, N, vote); N counts that unit's requests from 1."""
    m = VOTE.fullmatch(value)
    if not m:
        raise argparse.ArgumentTypeError(
            f"expected UNIT=approve|reject[@N], UNIT one of {', '.join(UNITS.values())}, N from 1")
    return m[1], int(m[3] or 1), m[2]


def goto_arg(value: str) -> tuple[int, dict]:
    """Parse X,Y[@N] into (N, the core's staged goto); N counts the core's requests from 1."""
    m = GOTO.fullmatch(value)
    if not m:
        raise argparse.ArgumentTypeError("expected X,Y[@N], X and Y in meters, N from 1")
    return int(m[3] or 1), {"verb": "goto", "target": [float(m[1]), float(m[2])],
                            "why": "Staged by --goto."}


def propose_arg(value: str) -> dict:
    """Parse VERB[:WHY] into the core's staged answer. Never a goto, which needs a target that
    this does not give, so core/llm.v read_proposal would count it a core fault."""
    verb, _, why = value.partition(":")
    if not re.fullmatch(r"\S+", verb) or verb.lower() == "goto":
        raise argparse.ArgumentTypeError("expected VERB[:WHY], one word other than goto")
    return {"verb": verb, "target": [], "why": why or "Staged by --propose."}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__ and __doc__.splitlines()[0])  # None under -OO
    # main.v load_config's default GEHIRN_URL, so gehirn finds the mock without variables.
    ap.add_argument("--listen", default="127.0.0.1:8081", help="host:port to serve on")
    ap.add_argument("--slow", type=slow_arg, action="append", default=[], metavar="ROLE=MS",
                    help="delay that role's replies")
    ap.add_argument("--garbage", type=role_arg, action="append", default=[], metavar="ROLE",
                    help="make that role answer in prose without a JSON object")
    ap.add_argument("--vote", type=vote_arg, action="append", default=[], metavar="UNIT=VOTE[@N]",
                    help="force that unit's ballot, approve or reject, from its N-th request on")
    ap.add_argument("--propose", type=propose_arg, metavar="VERB[:WHY]",
                    help="make the core propose VERB, never goto, on every request")
    ap.add_argument("--goto", type=goto_arg, action="append", default=[], metavar="X,Y[@N]",
                    help="make the core propose goto(X, Y) from its N-th request on")
    ap.add_argument("--quiet", action="store_true", help="no log line per request")
    args = ap.parse_args()

    Handler.slow = dict(args.slow)
    Handler.garbage = set(args.garbage)
    Handler.staged = args.propose
    Handler.gotos = dict(args.goto)
    for unit, n, vote in args.vote:
        Handler.votes.setdefault(unit, {})[n] = vote
    Handler.quiet = args.quiet
    host, _, port = args.listen.rpartition(":")
    server = Server((host, int(port)), Handler)

    # scripts/stage.sh up waits on this line.
    print(f"mock: serving on {args.listen}", file=sys.stderr, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
