#!/usr/bin/env python3
"""Serves the Flutter web bundle and proxies Odoo JSON-RPC calls on the same
origin so browsers never see a CORS preflight.

  - `/`, `/index.html`, `/main.dart.js`, `/assets/…`, `/canvaskit/…`, and any
    other file living under `build/web/` are served locally.
  - Everything else is forwarded verbatim to Odoo, with permissive CORS
    headers added so `withCredentials` fetch calls succeed.

Run:
  python3 scripts/cors_proxy.py
Open http://localhost:8088/ in the browser.
"""
from __future__ import annotations

import http.server
import mimetypes
import os
import socketserver
import urllib.error
import urllib.request

TARGET = "http://188.245.169.118:20064"
PORT = 8088
STATIC_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "build", "web")
)

_STATIC_FILES = {
    "index.html",
    "main.dart.js",
    "flutter.js",
    "flutter_bootstrap.js",
    "flutter_service_worker.js",
    "manifest.json",
    "favicon.png",
    "favicon.ico",
    "version.json",
}
_STATIC_PREFIXES = ("/assets/", "/canvaskit/", "/icons/")

CORS_BASE_HEADERS = {
    "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": (
        "Content-Type, Authorization, X-Openerp-Session-Id, X-Requested-With"
    ),
    "Access-Control-Allow-Credentials": "true",
    "Access-Control-Expose-Headers": "Set-Cookie",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
}

HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "content-length",
    "host",
    # Frame-blocking headers — must be stripped so the Flutter web build
    # can embed /odoo/action-N in an iframe. Without this, browsers
    # refuse the embed and the tile just spins forever.
    "x-frame-options",
    "content-security-policy",
    "content-security-policy-report-only",
}

# CSS injected into every HTML response served through the proxy.
# Only the Odoo top logo/user navbar (`.o_main_navbar`) plus the
# website portal header/footer are hidden — the action title (in
# `.o_breadcrumb` / `.o_control_panel`) and everything else stay
# visible. The Flutter Scaffold draws its own purple AppBar above
# the iframe, so the top logo bar would double up.
#
# The `.o_list_renderer table → block` rules at the bottom force the
# backend list view to render as stacked labeled cards (Timetables-
# style) even on desktop-wide iframes, so every module page has the
# same mobile-friendly look.
_EMBED_CSS = (
    b"<style id=\"flutter-embed-overrides\">"
    b".o_main_navbar, .o_navbar, header.o_main_navbar,"
    b" nav.o_main_navbar { display: none !important; }"
    b".o_loading_indicator { display: none !important; }"
    b".o_action_manager { top: 0 !important; padding-top: 0 !important; }"
    b".o_main_content { top: 0 !important; }"
    b"header.o_header_standard, header.o_header_affixed, #wrapwrap > header,"
    b" .o_portal_navbar { display: none !important; }"
    b"footer.o_footer, #wrapwrap > footer { display: none !important; }"
    b"#wrapwrap { padding-top: 0 !important; }"
    b"body { background: #fff !important; }"
    # ── Force list → mobile-card layout on every viewport ─────────
    b".o_list_renderer table, .o_list_view table,"
    b" .o_list_renderer tbody, .o_list_renderer thead,"
    b" .o_list_renderer tr, .o_list_renderer td, .o_list_renderer th"
    b" { display: block !important; width: auto !important; }"
    b".o_list_renderer thead, .o_list_view thead"
    b" { display: none !important; }"
    b".o_list_renderer tbody tr, .o_list_view tbody tr"
    b" { background: #fff !important;"
    b"   border: 1px solid #E1E5EB !important;"
    b"   border-radius: 8px !important;"
    b"   margin: 8px 12px !important;"
    b"   padding: 8px 12px !important;"
    b"   box-shadow: 0 1px 2px rgba(0,0,0,0.03) !important; }"
    b".o_list_renderer tbody td, .o_list_view tbody td"
    b" { padding: 4px 0 !important;"
    b"   border: none !important;"
    b"   white-space: normal !important;"
    b"   position: relative !important; }"
    b".o_list_renderer tbody td::before,"
    b" .o_list_view tbody td::before"
    b" { content: attr(data-tooltip) attr(name);"
    b"   display: inline-block;"
    b"   min-width: 100px;"
    b"   font-size: 12px;"
    b"   color: #7F8CA0;"
    b"   text-transform: capitalize;"
    b"   margin-right: 8px; }"
    # ── Portal tables (/my/*): stack rows so they fit mobile ──────
    # OpenEducat portal LIST templates (holidays, homework, etc.) use
    # plain Bootstrap `.table`. On narrow viewports the columns
    # overflow off-screen and the user has to scroll. Fold each row
    # into a labeled stack. `.table-borderless` and `.table-sm` are
    # excluded because those variants are used for *detail views*
    # (key/value pairs on /my/student) which should keep the label +
    # value inline, not fan out into boxes.
    b"#wrapwrap { overflow-x: hidden !important; }"
    b"#wrapwrap .table-responsive { overflow: visible !important; }"
    b"#wrapwrap table.table:not(.table-borderless):not(.table-sm)"
    b" { display: block !important; width: 100% !important;"
    b"   table-layout: fixed !important; }"
    b"#wrapwrap table.table:not(.table-borderless):not(.table-sm) thead"
    b" { display: none !important; }"
    b"#wrapwrap table.table:not(.table-borderless):not(.table-sm) tbody"
    b" { display: block !important; width: 100% !important; }"
    b"#wrapwrap table.table:not(.table-borderless):not(.table-sm) tbody tr"
    b" { display: block !important; width: auto !important;"
    b"   background: #fff !important;"
    b"   border: 1px solid #E1E5EB !important;"
    b"   border-radius: 8px !important;"
    b"   margin: 8px 0 !important;"
    b"   padding: 10px 14px !important; }"
    b"#wrapwrap table.table:not(.table-borderless):not(.table-sm) tbody td"
    b" { display: block !important; width: 100% !important;"
    b"   padding: 4px 0 !important;"
    b"   border: none !important;"
    b"   white-space: normal !important;"
    b"   word-break: break-word !important;"
    b"   text-align: left !important; }"
    # ── Detail tables (.table-borderless / .table-sm): hide empty
    # value rows so labels like "Blood Group:" don't appear when the
    # student's DB row has no value for that column.
    b"#wrapwrap table.table-borderless tr:has(td:last-child:empty),"
    b" #wrapwrap table.table-sm tr:has(td:last-child:empty)"
    b" { display: none !important; }"
    # ── Student portal avatar tile: brand color + white user icon
    # instead of the generic Bootstrap silhouette when image_1920 is
    # empty. Targets the `.bg-light.rounded` container the template
    # uses when no photo is available.
    b"#wrapwrap .bg-light.rounded.mx-auto"
    b" { background: linear-gradient(135deg, #139794, #0B7C79) !important;"
    b"   border: none !important;"
    b"   color: #ffffff !important; }"
    b"#wrapwrap .bg-light.rounded.mx-auto svg,"
    b" #wrapwrap .bg-light.rounded.mx-auto i,"
    b" #wrapwrap .bg-light.rounded.mx-auto .fa"
    b" { color: #ffffff !important;"
    b"   fill: #ffffff !important;"
    b"   opacity: 0.95 !important; }"
    # ── /my/security noise reduction: hide advanced blocks (Passkeys,
    # Revoke Sessions, Delete Account) and the useful-links / footer
    # links so the page reads like the compact Addresses card.
    b"#wrapwrap #o_wsale_passkeys_container,"
    b" #wrapwrap [id^='revoke'],"
    b" #wrapwrap [id*='revoke_session'],"
    b" #wrapwrap [id*='delete_account'],"
    b" #wrapwrap .o_portal_useful_links,"
    b" #wrapwrap .o_portal_useful_link,"
    b" #wrapwrap .o_footer_socials,"
    b" #wrapwrap .o_portal_footer,"
    b" #wrapwrap section.o_portal_useful_links_section,"
    b" #wrapwrap div.o_portal_useful_links"
    b" { display: none !important; }"
    # ── /my/account (Addresses) form: hide business-only fields the
    # student never fills — VAT, Company Name, Apartment/Suite. Keeps
    # the form compact and student-appropriate. Uses :has() to hide
    # the containing wrapper.
    b"#wrapwrap form div:has(> label[for*='company_name']),"
    b" #wrapwrap form div:has(> label[for='company_name']),"
    b" #wrapwrap form div:has(> label[for*='vat']),"
    b" #wrapwrap form div:has(> label[for='vat']),"
    b" #wrapwrap form div:has(> label[for*='street2']),"
    b" #wrapwrap form div:has(> input[name='company_name']),"
    b" #wrapwrap form div:has(> input[name='vat']),"
    b" #wrapwrap form div:has(> input[name='street2'])"
    b" { display: none !important; }"
    # ── /my/competitions polish: make the "+ New Challenge" link look
    # like a button, tighten the tables into legible mobile cards,
    # style Accept buttons, and give each section a heading gap.
    b"#wrapwrap a[href*='/my/competitions/new']"
    b" { display: inline-block !important;"
    b"   padding: 10px 18px !important;"
    b"   background: #1F82BC !important;"
    b"   color: #fff !important;"
    b"   border-radius: 8px !important;"
    b"   text-decoration: none !important;"
    b"   font-weight: 600 !important;"
    b"   margin: 8px 0 16px 0 !important; }"
    b"#wrapwrap h2, #wrapwrap h3"
    b" { margin-top: 20px !important;"
    b"   color: #16324F !important; }"
    b"#wrapwrap .btn-primary, #wrapwrap button[type='submit']"
    b" { background: #17A67A !important;"
    b"   border-color: #17A67A !important;"
    b"   color: #fff !important; }"
    # (Removed the over-broad `.container > .row` card wrapping rule —
    # it double-wrapped the Addresses page's "Delivery address" /
    # "Billing address" rows and clobbered their native layout. The
    # per-section CSS elsewhere is enough.)
    b"</style>"
)


def _inject_embed_css(html: bytes) -> bytes:
    idx = html.lower().find(b"</head>")
    if idx < 0:
        return html
    return html[:idx] + _EMBED_CSS + html[idx:]


class CORSProxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        print(f"[proxy] {self.address_string()} {fmt % args}")

    def _send_cors_headers(self) -> None:
        origin = self.headers.get("Origin", "*")
        self.send_header("Access-Control-Allow-Origin", origin)
        for k, v in CORS_BASE_HEADERS.items():
            self.send_header(k, v)

    def do_OPTIONS(self) -> None:
        self.send_response(200)
        self._send_cors_headers()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _is_static_path(self) -> bool:
        path = self.path.split("?", 1)[0]
        if path in ("", "/"):
            return True
        if any(path.startswith(p) for p in _STATIC_PREFIXES):
            return True
        rel = path.lstrip("/")
        if rel in _STATIC_FILES:
            return True
        full = os.path.normpath(os.path.join(STATIC_ROOT, rel))
        return full.startswith(STATIC_ROOT) and os.path.isfile(full)

    def _serve_static(self) -> None:
        path = self.path.split("?", 1)[0]
        rel = "index.html" if path in ("", "/") else path.lstrip("/")
        full = os.path.normpath(os.path.join(STATIC_ROOT, rel))
        if not full.startswith(STATIC_ROOT) or not os.path.isfile(full):
            self.send_response(404)
            self._send_cors_headers()
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        ctype, _ = mimetypes.guess_type(full)
        ctype = ctype or "application/octet-stream"
        with open(full, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self._send_cors_headers()
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def _forward(self) -> None:
        if self._is_static_path():
            self._serve_static()
            return
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length > 0 else None
        req_headers = {}
        for k, v in self.headers.items():
            if k.lower() in HOP_BY_HOP:
                continue
            req_headers[k] = v
        url = f"{TARGET}{self.path}"
        req = urllib.request.Request(
            url, data=body, method=self.command, headers=req_headers
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
                content_type = ""
                for k, v in resp.getheaders():
                    if k.lower() == "content-type":
                        content_type = v.lower()
                        break
                # If Odoo returned an HTML shell (any /odoo/* or portal
                # page), inject our CSS override so the iframe skips its
                # own navbar/chatter/footer.
                if "text/html" in content_type:
                    data = _inject_embed_css(data)
                self.send_response(resp.status)
                for k, v in resp.getheaders():
                    if k.lower() in HOP_BY_HOP or k.lower() == "content-length":
                        continue
                    self.send_header(k, v)
                self.send_header("Content-Length", str(len(data)))
                self._send_cors_headers()
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(data)
        except urllib.error.HTTPError as e:
            data = e.read() or b""
            self.send_response(e.code)
            for k, v in e.headers.items():
                if k.lower() in HOP_BY_HOP:
                    continue
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(data)))
            self._send_cors_headers()
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(data)
        except urllib.error.URLError as e:
            msg = str(e).encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(msg)))
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(msg)

    def do_GET(self) -> None:
        self._forward()

    def do_POST(self) -> None:
        self._forward()

    def do_PUT(self) -> None:
        self._forward()

    def do_PATCH(self) -> None:
        self._forward()

    def do_DELETE(self) -> None:
        self._forward()

    def do_HEAD(self) -> None:
        self._forward()


class ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> None:
    if not os.path.isdir(STATIC_ROOT):
        print(f"[proxy] warning: {STATIC_ROOT} does not exist — run `flutter build web` first.")
    with ThreadingServer(("", PORT), CORSProxy) as httpd:
        print(f"[proxy] serving on http://localhost:{PORT}/  →  {TARGET}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[proxy] shutting down")


if __name__ == "__main__":
    main()
