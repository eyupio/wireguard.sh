#!/usr/bin/env python3
"""Static checks for the wireguard.sh landing page."""

from __future__ import annotations

import re
import struct
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HTML_PATH = ROOT / "index.html"
CSS_PATH = ROOT / "index.css"
JS_PATH = ROOT / "index.js"

errors: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


class DocumentParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: list[str] = []
        self.copy_targets: list[str] = []
        self.local_refs: list[str] = []
        self.scripts: list[str] = []
        self.stylesheets: list[str] = []
        self.buttons = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if "id" in values and values["id"]:
            self.ids.append(values["id"])
        if "data-copy" in values and values["data-copy"]:
            self.copy_targets.append(values["data-copy"])
        if tag == "button":
            self.buttons += 1
        if tag == "script" and values.get("src"):
            self.scripts.append(values["src"] or "")
        if tag == "link" and "stylesheet" in (values.get("rel") or ""):
            self.stylesheets.append(values.get("href") or "")
        for attribute in ("href", "src"):
            value = values.get(attribute)
            if value:
                self.local_refs.append(value)


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path.name} is not a PNG")
    return struct.unpack(">II", data[16:24])


def main() -> int:
    for path in (HTML_PATH, CSS_PATH, JS_PATH):
        check(path.exists(), f"missing file: {path.name}")

    html = HTML_PATH.read_text(encoding="utf-8")
    css = CSS_PATH.read_text(encoding="utf-8")
    js = JS_PATH.read_text(encoding="utf-8")
    lower_html = html.lower()

    parser = DocumentParser()
    parser.feed(html)

    # Document basics
    check(lower_html.lstrip().startswith("<!doctype html>"), "index.html must start with <!DOCTYPE html>")
    check('<html lang="en">' in html, "html element must declare lang=\"en\"")
    check('<meta charset="utf-8">' in lower_html, "missing UTF-8 charset meta")
    check('name="viewport"' in lower_html, "missing responsive viewport meta")
    check("width=device-width" in lower_html, "viewport must use width=device-width")
    check(html.count("<h1") == 1, "page must contain exactly one h1")
    check("<main" in lower_html and 'id="main"' in lower_html, "missing main landmark")
    check("<header" in lower_html and "<footer" in lower_html, "missing header/footer landmarks")

    # Conversion content must be in the static HTML
    check("Install a WireGuard VPN server" in html, "missing value proposition headline")
    check('id="cmd-wget"' in html, "missing wget command element")
    check('id="cmd-curl"' in html, "missing curl command element")
    check("bash &lt;(wget -q -O - https://wireguard.sh/wireguard.sh)" in html, "wget command text changed")
    check("bash &lt;(curl -s https://wireguard.sh/wireguard.sh)" in html, "curl command text changed")
    check(parser.buttons >= 2, "both commands need copy buttons")
    check(len(parser.copy_targets) >= 2, "copy buttons must declare data-copy targets")
    check('aria-live="polite"' in lower_html, "copy feedback needs an aria-live status region")
    check("<noscript" in lower_html, "missing no-JS fallback")
    check("https://github.com/jnnngs/wireguard.sh" in html, "missing GitHub source link")
    check(
        "https://github.com/jnnngs/wireguard.sh/blob/main/wireguard.sh" in html,
        "installer links must use the rendered GitHub view",
    )
    check('href="wireguard.sh"' not in html, "do not link directly to the .sh download")
    check("https://www.wireguard.com/install/" in html, "missing client download link")
    check("51820" in html, "missing default port trust information")
    check("Ubuntu 18.04+" in html, "missing supported OS information")

    # IDs and local references
    duplicates = sorted({item for item in parser.ids if parser.ids.count(item) > 1})
    check(not duplicates, f"duplicate ids: {duplicates}")
    for target in parser.copy_targets:
        check(target in parser.ids, f"data-copy target does not exist: {target}")

    for ref in parser.local_refs:
        if re.match(r"^(?:[a-z]+:|#)", ref):
            continue
        clean = ref.split("?")[0].split("#")[0].lstrip("/")
        if not clean:
            continue
        check((ROOT / clean).exists(), f"local reference does not exist: {ref}")

    # No remote runtime dependencies
    remote_assets = [
        ref
        for ref in parser.scripts + parser.stylesheets
        if re.match(r"^https?:", ref)
    ]
    check(not remote_assets, f"scripts/styles must be self-hosted: {remote_assets}")
    for legacy in ("jquery", "googleapis", "unpkg.com", "fontawesome", "clipboard.min.js"):
        check(legacy not in lower_html, f"legacy dependency still referenced: {legacy}")

    # CSS requirements
    compact_css = re.sub(r"\s+", "", css)
    check("width:750px" not in compact_css, "fixed 750px terminal width is back")
    check("prefers-reduced-motion:reduce" in compact_css, "missing reduced-motion support")
    check("@media(max-width:620px)" in compact_css, "missing mobile breakpoint")
    check(".skip-link" in css, "missing skip link styling")

    # JS requirements
    check("navigator.clipboard" in js, "copy should use the async clipboard API")
    check("execCommand" in js, "copy needs a non-secure-context fallback")
    check("innerHTML" not in js, "do not rewrite the DOM with innerHTML")
    check("setInterval" not in js, "typing animation must not be reintroduced")
    check("scrollBy" not in js, "page must not hijack scrolling")

    # Social assets
    for asset, expected in (("og.png", (1200, 630)), ("apple-touch-icon.png", (180, 180))):
        path = ROOT / asset
        check(path.exists(), f"missing {asset}")
        if path.exists():
            check(png_size(path) == expected, f"{asset} must be {expected[0]}x{expected[1]}")

    if errors:
        print("Validation failed:\n", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print("Site validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
