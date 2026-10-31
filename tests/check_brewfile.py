#!/usr/bin/env python3
"""Checks every app and tool in the Brewfile against Homebrew right now:
it must exist and must not be deprecated or disabled.

Usage: python3 tests/check_brewfile.py [Brewfile]
Exit 1 if anything is missing or retired; network problems are reported
separately and also fail, so a broken connection is never read as success.
"""

import concurrent.futures
import datetime
import pathlib
import re
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
brewfile = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Brewfile"

CORE = "https://raw.githubusercontent.com/Homebrew/homebrew-core/HEAD/Formula/{l}/{n}.rb"
CASK = "https://raw.githubusercontent.com/Homebrew/homebrew-cask/HEAD/Casks/{l}/{n}.rb"
TAP = "https://raw.githubusercontent.com/{user}/homebrew-{repo}/HEAD/{kind}/{n}.rb"


def url_for(kind, name):
    if name.count("/") == 2:
        user, repo, n = name.split("/")
        return TAP.format(user=user, repo=repo, kind="Casks" if kind == "cask" else "Formula", n=n)
    return (CASK if kind == "cask" else CORE).format(l=name[0].lower(), n=name)


def check(entry):
    kind, name = entry
    try:
        with urllib.request.urlopen(url_for(kind, name), timeout=20) as r:
            body = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return entry, "missing" if e.code == 404 else f"network error ({e.code})"
    except Exception as e:  # timeouts, DNS, proxy
        return entry, f"network error ({type(e).__name__})"
    today = datetime.date.today().isoformat()
    disable = re.search(r'^\s*disable!(?:\s+date:\s*"([\d-]+)")?(.*)$', body, re.M)
    if disable and (not disable.group(1) or disable.group(1) <= today):
        return entry, "disabled" + replacement(body)
    if disable or re.search(r"^\s*deprecate!", body, re.M):
        when = f", stops working {disable.group(1)}" if disable else ""
        return entry, f"deprecated{when}" + replacement(body)
    return entry, "ok"


def replacement(body):
    m = re.search(r'replacement_(?:formula|cask):\s*"([^"]+)"', body)
    return f" (replace with {m.group(1)})" if m else ""


entries = re.findall(r'^\s*(brew|cask)\s+"([^"]+)"', brewfile.read_text(), re.M)
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
    results = list(pool.map(check, entries))

problems = [(f"{k} {n}", status) for (k, n), status in results if status != "ok"]
for item, status in problems:
    print(f"{item}: {status}")
if problems:
    sys.exit(1)
print(f"All {len(entries)} Brewfile entries exist in Homebrew and are current")
