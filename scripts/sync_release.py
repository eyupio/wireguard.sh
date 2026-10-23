#!/usr/bin/env python3
"""Sync the site and installer version labels with the latest GitHub release."""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INSTALLER_PATH = ROOT / "wireguard.sh"
HTML_PATH = ROOT / "index.html"
API_URL = "https://api.github.com/repos/eyupio/wireguard.sh/releases/latest"


def fetch_latest_release(url: str) -> dict:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "wireguard.sh-release-sync",
        },
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)


def version_from_tag(tag: str) -> str:
    version = tag.strip().removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", version):
        raise ValueError(f"unexpected release tag: {tag!r}")
    return version


def update_installer(text: str, version: str) -> str:
    updated, count = re.subn(
        r'^APP_VERSION="[^"]+"',
        f'APP_VERSION="{version}"',
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise ValueError("could not find APP_VERSION in wireguard.sh")
    return updated


def update_html(text: str, version: str) -> str:
    tag = f"v{version}"
    updated, version_count = re.subn(
        r'(<span data-release-version>)v?[^<]+(</span>)',
        rf"\g<1>{tag}\g<2>",
        text,
    )
    if version_count < 1:
        raise ValueError("could not find the static release version in index.html")

    updated = re.sub(
        r"https://github\.com/eyupio/wireguard\.sh/releases/tag/v[0-9.]+",
        f"https://github.com/eyupio/wireguard.sh/releases/tag/{tag}",
        updated,
    )
    updated = re.sub(
        r'"softwareVersion"\s*:\s*"[^"]+"',
        f'"softwareVersion": "{version}"',
        updated,
        count=1,
    )
    return updated


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="report drift without writing files",
    )
    parser.add_argument(
        "--from-tag",
        metavar="TAG",
        help="use a tag instead of asking the GitHub API",
    )
    args = parser.parse_args()

    try:
        if args.from_tag:
            tag = args.from_tag
        else:
            release = fetch_latest_release(API_URL)
            tag = release.get("tag_name") or ""
        version = version_from_tag(tag)
    except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError) as error:
        print(f"Could not read the latest release: {error}", file=sys.stderr)
        return 2

    changes: list[tuple[Path, str, str]] = []
    for path, updater in (
        (INSTALLER_PATH, update_installer),
        (HTML_PATH, update_html),
    ):
        original = path.read_text(encoding="utf-8")
        updated = updater(original, version)
        if updated != original:
            changes.append((path, original, updated))

    if not changes:
        print(f"Already in sync with release v{version}.")
        return 0

    if args.check:
        for path, _, _ in changes:
            print(f"Out of sync: {path.relative_to(ROOT)}", file=sys.stderr)
        return 1

    for path, _, updated in changes:
        path.write_text(updated, encoding="utf-8")
        print(f"Updated {path.relative_to(ROOT)} for v{version}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
