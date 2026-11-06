#!/usr/bin/env python3
"""PulseWatch backend: status numbers and a simulated sign-in form.
Standard library only. Stores nothing: no database, no emails, no logs."""
import hashlib, json, math, os, random, re, time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("PULSE_HOST", "127.0.0.1")
PORT = int(os.environ.get("PULSE_PORT", "8081"))
DAYS = 90
EMAIL_RE = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,255}\.[^@\s]{2,}$")
hits = []


def h(s):
    return int(hashlib.sha256(s.encode()).hexdigest()[:8], 16)


def day_state(d):
    """Deterministic history: same answer for every visitor, rolls forward daily."""
    v = h("pulsewatch-" + d.isoformat()) % 1000
    if v < 4:
        return "outage", 25 + v * 9      # minutes of downtime
    if v < 24:
        return "degraded", 6 + v % 9
    return "ok", 0


def status():
    now = datetime.now(timezone.utc)
    days, down = [], 0
    for i in range(DAYS - 1, -1, -1):
        st, m = day_state(now.date() - timedelta(days=i)) if i else ("ok", 0)
        days.append(st)
        down += m
    since = next((i for i, s in enumerate(reversed(days)) if s != "ok"), DAYS)
    minute = now.hour * 60 + now.minute + now.second / 60
    base = 2400 + 700 * math.sin((minute / 1440 - 0.375) * 2 * math.pi)   # daily curve
    probes = int(base) + h("c%d" % int(now.timestamp() // 30)) % 61 - 30   # small jitter
    return {"status": "operational", "uptime_90d": round(100 - down / (DAYS * 1440) * 100, 3),
            "since_incident": since, "probes": probes, "days": days}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/api/status":
            self.reply(200, status())
        elif p == "/api/subscribe":
            self.reply(405, {"error": "Method not allowed."})
        else:
            self.reply(404, {"error": "Not found."})

    def do_POST(self):
        p = self.path.split("?")[0]
        if p == "/api/status":
            return self.reply(405, {"error": "Method not allowed."})
        if p != "/api/subscribe":
            return self.reply(404, {"error": "Not found."})
        try:
            if not (self.headers.get("Content-Type") or "").startswith("application/json"):
                raise ValueError
            n = int(self.headers.get("Content-Length") or 0)
            d = json.loads(self.rfile.read(min(n, 1024)) or b"{}")
            email = str(d.get("email", "")).strip()
            if not EMAIL_RE.match(email):
                raise ValueError
        except (ValueError, AttributeError):
            return self.reply(400, {"error": "Please enter a valid email address."})
        now = time.time()
        hits[:] = [t for t in hits if now - t < 60]
        if len(hits) >= 30:
            return self.reply(429, {"error": "Too many requests. Please try again in a minute."})
        hits.append(now)
        time.sleep(0.4 + random.random() * 0.6)   # looks like a real mail request
        self.reply(200, {"ok": True})


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), H).serve_forever()
