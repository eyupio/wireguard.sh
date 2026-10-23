#!/usr/bin/env python3
"""Static checks for the wireguard.sh landing page and installer."""

from __future__ import annotations

import os
import re
import struct
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HTML_PATH = ROOT / "index.html"
CSS_PATH = ROOT / "index.css"
JS_PATH = ROOT / "index.js"
INSTALLER_PATH = ROOT / "wireguard.sh"
SYNC_PATH = ROOT / "scripts" / "sync_release.py"

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
        self.remote_refs: list[str] = []
        self.scripts: list[str] = []
        self.stylesheets: list[str] = []
        self.buttons = 0
        self.tui_cards = 0
        self.release_versions = 0
        self.release_links = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if "id" in values and values["id"]:
            self.ids.append(values["id"])
        if "data-copy" in values and values["data-copy"]:
            self.copy_targets.append(values["data-copy"])
        if "data-release-version" in values:
            self.release_versions += 1
        if "data-release-link" in values:
            self.release_links += 1
        classes = (values.get("class") or "").split()
        if "tui-card" in classes:
            self.tui_cards += 1
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
                if re.match(r"^https?:", value):
                    self.remote_refs.append(value)


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path.name} is not a PNG")
    return struct.unpack(">II", data[16:24])


def run_installer(*args: str) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment.update({"TERM": "xterm-256color", "COLUMNS": "70", "TUI_COLOR": "never"})
    return subprocess.run(
        ["bash", str(INSTALLER_PATH), *args],
        cwd=ROOT,
        env=environment,
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )


def main() -> int:
    for path in (HTML_PATH, CSS_PATH, JS_PATH, INSTALLER_PATH, SYNC_PATH):
        check(path.exists(), f"missing file: {path.name}")

    if errors:
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    html = HTML_PATH.read_text(encoding="utf-8")
    css = CSS_PATH.read_text(encoding="utf-8")
    js = JS_PATH.read_text(encoding="utf-8")
    installer = INSTALLER_PATH.read_text(encoding="utf-8")
    lower_html = html.lower()

    parser = DocumentParser()
    parser.feed(html)

    def has_link(url: str) -> bool:
        return any(link == url for link in parser.local_refs)

    check(lower_html.lstrip().startswith("<!doctype html>"), "index.html must start with <!DOCTYPE html>")
    check('<html lang="en">' in html, "html element must declare lang=\"en\"")
    check('<meta charset="utf-8">' in lower_html, "missing UTF-8 charset meta")
    check('name="viewport"' in lower_html, "missing responsive viewport meta")
    check("width=device-width" in lower_html, "viewport must use width=device-width")
    check(html.count("<h1") == 1, "page must contain exactly one h1")
    check('id="main"' in lower_html, "missing main landmark")
    check("<header" in lower_html and "<footer" in lower_html, "missing header/footer landmarks")

    check("Install a WireGuard VPN server" in html, "missing value proposition headline")
    check('id="cmd-wget"' in html, "missing wget command element")
    check('id="cmd-curl"' in html, "missing curl command element")
    check("bash &lt;(wget -q -O - https://wireguard.sh/wireguard.sh)" in html, "wget command text changed")
    check("bash &lt;(curl -s https://wireguard.sh/wireguard.sh)" in html, "curl command text changed")
    check(parser.buttons >= 2, "both commands need copy buttons")
    check(len(parser.copy_targets) >= 2, "copy buttons must declare data-copy targets")
    check('aria-live="polite"' in lower_html, "copy feedback needs an aria-live status region")
    check("<noscript" in lower_html, "missing no-JS fallback")
    check('id="tui"' in html, "missing TUI preview section")
    check(parser.tui_cards >= 3, "TUI preview needs at least three screens")
    check("A terminal UI that shows its working." in html, "missing TUI section headline")
    check("Developed by EyUp.io" in html, "missing EyUp.io credit in the page")
    check(has_link("https://eyup.io"), "missing EyUp.io link")
    check(
        re.search(
            r'<a href="https://eyup\.io" target="_blank" rel="noopener noreferrer">EyUp\.io</a>',
            html,
        )
        is not None,
        "footer must link to EyUp.io like the Zoomies footer",
    )
    check(has_link("https://github.com/Nyr/wireguard-install"), "missing Nyr/wireguard-install credit")
    check(has_link("https://www.wireguard.com/"), "missing WireGuard credit link")
    check("Jason A. Donenfeld" in html, "missing WireGuard author credit")
    check("not affiliated with" in html, "missing independence note")
    check(has_link("https://github.com/eyupio/wireguard.sh"), "missing current GitHub source link")
    check(has_link("https://github.com/eyupio/wireguard.sh/blob/main/wireguard.sh"), "installer links must use the rendered GitHub view")
    check("jnnngs" not in html, "landing page still links to the old repository")
    check('href="wireguard.sh"' not in html, "do not link directly to the .sh download")
    check(has_link("https://www.wireguard.com/install/"), "missing client download link")
    check("51820" in html, "missing default port trust information")
    check("Ubuntu 18.04+" in html, "missing supported OS information")
    check(parser.release_versions >= 1, "missing data-release-version fallback")
    check(parser.release_links >= 2, "missing data-release-link hooks")

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

    remote_assets = [
        ref for ref in parser.scripts + parser.stylesheets if re.match(r"^https?:", ref)
    ]
    check(not remote_assets, f"scripts/styles must be self-hosted: {remote_assets}")
    for legacy in ("jquery", "googleapis", "unpkg.com", "fontawesome", "clipboard.min.js"):
        check(legacy not in lower_html, f"legacy dependency still referenced: {legacy}")

    compact_css = re.sub(r"\s+", "", css)
    check("width:750px" not in compact_css, "fixed 750px terminal width is back")
    check("prefers-reduced-motion:reduce" in compact_css, "missing reduced-motion support")
    check("@media(max-width:620px)" in compact_css, "missing mobile breakpoint")
    check(".skip-link" in css, "missing skip link styling")
    check(".tui-grid" in css, "missing TUI preview grid styles")
    check(".tui-screen" in css, "missing TUI preview styles")
    check(".tui-card--wide" in css, "missing wide TUI preview styles")

    check("navigator.clipboard" in js, "copy should use the async clipboard API")
    check("execCommand" in js, "copy needs a non-secure-context fallback")
    check("innerHTML" not in js, "do not rewrite the DOM with innerHTML")
    check("setInterval" not in js, "typing animation must not be reintroduced")
    check("scrollBy" not in js, "page must not hijack scrolling")
    check("RELEASE_API" in js and "data-release-link" in js, "release sync is not wired up")
    check("data-release-version" in js, "release version hook is not wired up")

    check('APP_AUTHOR="EyUp.io"' in installer, "installer is missing the EyUp.io credit")
    check('UPSTREAM_URL="https://github.com/Nyr/wireguard-install"' in installer, "installer is missing Nyr credit")
    check('WIREGUARD_URL="https://www.wireguard.com/"' in installer, "installer is missing WireGuard credit")
    check("screen_about" in installer, "installer is missing the about/credits screen")
    check("tui_menu" in installer and "wizard_run" in installer, "installer TUI functions are missing")
    check("management_loop" in installer, "installer dashboard flow is missing")
    check("--preview" in installer, "installer is missing the preview flag")

    installer_version = re.search(r'^APP_VERSION="([^"]+)"', installer, re.MULTILINE)
    check(installer_version is not None, "installer is missing APP_VERSION")
    expected_version = installer_version.group(1) if installer_version else ""
    check(
        has_link(f"https://github.com/eyupio/wireguard.sh/releases/tag/v{expected_version}"),
        "missing release tag link",
    )

    structured_version = re.search(r'"softwareVersion"\s*:\s*"([^"]+)"', html)
    check(structured_version is not None, "missing JSON-LD softwareVersion")
    page_versions = re.findall(r"<span data-release-version>v?([^<]+)</span>", html)
    check(bool(page_versions), "missing static release version")
    check(
        structured_version is not None and structured_version.group(1) == expected_version,
        "JSON-LD softwareVersion does not match the installer version",
    )
    check(
        all(version == expected_version for version in page_versions),
        "static release version does not match the installer version",
    )
    check(
        has_link(f"https://github.com/eyupio/wireguard.sh/releases/tag/v{expected_version}"),
        "release links do not match the installer version",
    )

    try:
        syntax = subprocess.run(
            ["bash", "-n", str(INSTALLER_PATH)],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        check(syntax.returncode == 0, f"wireguard.sh has a syntax error: {syntax.stderr.strip()}")
    except (OSError, subprocess.TimeoutExpired) as error:
        check(False, f"could not syntax-check wireguard.sh: {error}")

    version_run = run_installer("--version")
    check(version_run.returncode == 0, "wireguard.sh --version failed")
    check(
        f"wireguard.sh {expected_version}" in version_run.stdout,
        f"wireguard.sh --version did not report {expected_version}",
    )

    help_run = run_installer("--help")
    check(help_run.returncode == 0, "wireguard.sh --help failed")
    check("Nyr" in help_run.stdout and "Jason A. Donenfeld" in help_run.stdout, "help is missing credits")

    preview_run = run_installer("--preview")
    check(preview_run.returncode == 0, "wireguard.sh --preview failed")
    for expected in ("EyUp.io", "Review your setup", "Dashboard", "Nyr", "WireGuard"):
        check(expected in preview_run.stdout, f"TUI preview is missing: {expected}")

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
