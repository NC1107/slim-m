# SPDX-License-Identifier: Apache-2.0
"""Drive one Flutter web client over the Chrome DevTools Protocol.

Flutter paints to a canvas, so the app is unreachable from a script until its
accessibility tree is on; clicking the placeholder Flutter leaves in the DOM
turns every widget into an <flt-semantics> element with a real bounding box.
That is what makes this label-driven rather than pixel-driven, and so survives
a layout change.

Split out of voice_e2e.py, which owns the scenario these methods are used by.
"""
import base64
import json
import os
import tempfile
import time
import urllib.request

TIMEOUT = 90
# A private directory when unset, rather than a guessable shared one.
SHOTS = os.environ.get("VOICE_E2E_SHOTS") or tempfile.mkdtemp(prefix="voice-e2e-")


class Client:
    """One browser, addressed over the Chrome DevTools Protocol."""

    def __init__(self, name, port):
        self.name = name
        self.port = port
        self._ws = None
        self._id = 0

    def _connect(self):
        from websocket import create_connection

        targets = json.load(urllib.request.urlopen(
            f"http://127.0.0.1:{self.port}/json/list"))
        page = next(t for t in targets if t["type"] == "page")
        self._ws = create_connection(page["webSocketDebuggerUrl"],
                                     suppress_origin=True, timeout=30)

    def send(self, method, params=None):
        if self._ws is None:
            self._connect()
        self._id += 1
        self._ws.send(json.dumps({"id": self._id, "method": method,
                                  "params": params or {}}))
        while True:
            msg = json.loads(self._ws.recv())
            if msg.get("id") == self._id:
                return msg

    def ev(self, expr):
        r = self.send("Runtime.evaluate",
                      {"expression": expr, "returnByValue": True})
        return r.get("result", {}).get("result", {}).get("value")

    def enable_semantics(self):
        for _ in range(20):
            if (self.ev("document.querySelectorAll('flt-semantics').length") or 0) > 0:
                return
            self.ev("(function(){var p=document.querySelector("
                    "'flt-semantics-placeholder');if(p){p.click();}})()")
            time.sleep(2)
        raise AssertionError(f"{self.name}: accessibility tree never came up")

    def nodes(self):
        """Every leaf widget on screen, plus the fields.

        A text field's accessible name lands on the <input> Flutter creates for
        it, not on the wrapping semantics node, so both have to be collected or
        every field on every screen looks unlabelled.
        """
        raw = self.ev("""
        (function(){
          var out=[];
          document.querySelectorAll('flt-semantics').forEach(function(e){
            // A row that names itself (a channel, a member) keeps its label on
            // the node wrapping its icon and text, so leaves alone miss it.
            var named=e.getAttribute('aria-label');
            if (!named && e.querySelector('flt-semantics')) return;
            var t=(named||e.textContent||'').trim();
            if(!t) return;
            var r=e.getBoundingClientRect();
            if(r.width<1||r.height<1) return;
            out.push({t:t,x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2),
                      field:false});
          });
          document.querySelectorAll('input,textarea').forEach(function(e){
            var t=(e.getAttribute('aria-label')||e.getAttribute('placeholder')||'').trim();
            if(!t) return;
            var r=e.getBoundingClientRect();
            out.push({t:t,x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2),
                      field:true});
          });
          return JSON.stringify(out);
        })()""")
        return json.loads(raw or "[]")

    def find(self, label, field=None):
        for n in self.nodes():
            if field is not None and n.get("field") != field:
                continue
            if label.lower() in n["t"].lower():
                return n
        return None

    def wait_for(self, label, timeout=TIMEOUT, field=None):
        deadline = time.time() + timeout
        while time.time() < deadline:
            n = self.find(label, field=field)
            if n:
                return n
            time.sleep(1)
        self.shot(f"missing-{label[:20].replace(' ', '-')}")
        raise AssertionError(f"{self.name}: never saw {label!r}")

    def tap(self, x, y):
        for kind in ("mousePressed", "mouseReleased"):
            self.send("Input.dispatchMouseEvent",
                      {"type": kind, "x": x, "y": y, "button": "left",
                       "clickCount": 1})
            time.sleep(0.06)

    def click(self, label, settle=1.5):
        """Activate a widget the way a screen reader would.

        Dispatching a mouse event at the widget's coordinates hits whatever
        Flutter has layered over the canvas there and silently does nothing on
        some screens; clicking the semantics element itself is what the
        framework listens for.
        """
        self.wait_for(label)
        hit = self.ev(f"""
        (function(){{
          var want={json.dumps(label.lower())};
          var hits=[];
          document.querySelectorAll('flt-semantics').forEach(function(e){{
            var t=((e.getAttribute('aria-label')||'')+' '+
                   (e.textContent||'')).toLowerCase();
            if (t.indexOf(want)>=0) hits.push(e);
          }});
          // Flutter paints the same label onto a plain node and onto the
          // tappable one beside it; only the tappable one answers a click.
          var tappable=hits.filter(function(e){{
            return e.hasAttribute('flt-tappable') ||
                   e.getAttribute('role')==='button';
          }});
          // Closest name wins, not the last one found: a channel row and its
          // "Manage <name>" button both match the channel's own name, and
          // taking the last opened the manage sheet every time.
          function name(e){{
            return (e.getAttribute('aria-label')||e.textContent||'').trim();
          }}
          tappable.sort(function(x,y){{
            var nx=name(x), ny=name(y);
            if ((nx.toLowerCase()===want)!==(ny.toLowerCase()===want)) {{
              return nx.toLowerCase()===want ? -1 : 1;
            }}
            return nx.length-ny.length;
          }});
          var target=tappable[0];
          if (!target) {{
            target=hits.filter(function(e){{
              return !e.querySelector('flt-semantics');
            }}).pop();
          }}
          if (!target) return false;
          target.click();
          return true;
        }})()""")
        if not hit:
            n = self.wait_for(label)
            self.tap(n["x"], n["y"])
        time.sleep(settle)

    def type_into(self, label, text):
        """Focus the field's own element rather than clicking where it looks.

        A click lands on whatever is topmost at that point, which on a dialog is
        sometimes the barrier; focusing the input Flutter already made cannot
        miss. Flutter only builds that input for the field holding focus, so a
        field that has never held it is clicked once to bring it into being.
        """
        if not self.find(label, field=True):
            self.click(label, settle=1.0)
        self.wait_for(label, field=True)
        focused = self.ev(f"""
        (function(){{
          var els=document.querySelectorAll('input,textarea');
          for (var i=0;i<els.length;i++) {{
            var t=(els[i].getAttribute('aria-label')||
                   els[i].getAttribute('placeholder')||'');
            if (t.toLowerCase().indexOf({json.dumps(label.lower())})>=0) {{
              els[i].focus(); return true;
            }}
          }}
          return false;
        }})()""")
        if not focused:
            n = self.wait_for(label, field=True)
            self.tap(n["x"], n["y"])
        time.sleep(0.4)
        self.send("Input.insertText", {"text": text})
        time.sleep(0.4)

    def wait_url(self, fragment, timeout=TIMEOUT):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if fragment in (self.ev("location.href") or ""):
                return
            time.sleep(1)
        self.shot(f"stuck-at{fragment.replace('/', '-')}")
        raise AssertionError(
            f"{self.name}: never reached {fragment!r}, still at "
            f"{self.ev('location.href')}")

    def shot(self, tag):
        os.makedirs(SHOTS, mode=0o700, exist_ok=True)
        r = self.send("Page.captureScreenshot", {"format": "png"})
        data = (r.get("result", {}).get("result", {}).get("data")
                or r.get("result", {}).get("data"))
        if not data:
            return
        path = os.path.join(SHOTS, f"{self.name}-{tag}.png")
        with open(path, "wb") as fh:
            fh.write(base64.b64decode(data))
        print(f"    shot {path}")


