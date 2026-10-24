#!/usr/bin/env python3
"""Check internal links and anchors in a built Wyrd docs site."""

import argparse
import sys
import tempfile
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit, urlunsplit


SITE_ORIGIN = "https://trusdan.github.io/wyrd"
SITE_ROOT = "/wyrd"


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.refs = []
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if "href" in values:
            self.refs.append(values["href"])
        if "src" in values:
            self.refs.append(values["src"])
        if "id" in values:
            self.ids.add(values["id"])
        if tag == "a" and values.get("name"):
            self.ids.add(values["name"])


def load(path: Path) -> Page:
    page = Page()
    page.feed(path.read_text(encoding="utf-8", errors="replace"))
    return page


def strip_query(url: str) -> str:
    parts = urlsplit(url)
    if parts.scheme or parts.netloc:
        return urlunsplit((parts.scheme, parts.netloc, parts.path, "", parts.fragment))
    path, _, _query = url.partition("?")
    if "#" in url and "#" not in path:
        fragment = url.split("#", 1)[1]
        return path + "#" + fragment
    return path


def classify(url: str):
    """Return ('external', None), ('skip', None), or ('internal', (path, fragment))."""
    raw = strip_query(url.strip())
    if not raw or raw.startswith(("#", "mailto:", "javascript:", "data:")):
        if raw.startswith("#"):
            return "internal", ("", unquote(raw[1:]))
        return "external" if raw.startswith("mailto:") else "skip", None
    if raw.startswith(("http://", "https://")):
        if raw == SITE_ORIGIN or raw.startswith(SITE_ORIGIN + "/"):
            rest = raw[len(SITE_ORIGIN):]
            return "internal", _split_path(rest)
        return "external", None
    if raw.startswith("/"):
        if raw == SITE_ROOT or raw.startswith(SITE_ROOT + "/"):
            return "internal", _split_path(raw[len(SITE_ROOT):])
        return "outside", None
    if raw.startswith("//"):
        return "external", None
    return "internal", _split_path(raw)


def _split_path(raw: str):
    path, _, fragment = raw.partition("#")
    return unquote(path), unquote(fragment)


def locate(page: Path, site: Path, url_path: str) -> Path:
    if url_path in ("", "/"):
        return site / "index.html"
    if url_path.startswith("/"):
        target = (site / url_path.lstrip("/")).resolve()
    else:
        target = (page.parent / url_path).resolve()
    if url_path.endswith("/") or target.is_dir():
        target = target / "index.html"
    return target


def check(site: Path) -> list:
    site = site.resolve()
    pages = sorted(path for path in site.rglob("*.html") if path.is_file())
    parsed = {path: load(path) for path in pages}
    broken = []
    for path, page in parsed.items():
        rel = path.relative_to(site).as_posix()
        for ref in page.refs:
            kind, data = classify(ref)
            if kind in ("external", "skip"):
                continue
            if kind == "outside":
                broken.append((rel, ref.strip(), "outside site"))
                continue
            url_path, fragment = data
            if url_path == "" and fragment:
                target = path
            else:
                target = locate(path, site, url_path)
            try:
                target.relative_to(site)
            except ValueError:
                broken.append((rel, ref.strip(), "outside site"))
                continue
            if not target.is_file():
                broken.append((rel, ref.strip(), "missing file"))
                continue
            if fragment and fragment not in parsed.get(target, load(target)).ids:
                broken.append((rel, ref.strip(), "missing anchor"))
    return broken


def report(broken: list) -> None:
    for page, link, reason in broken:
        print("%s: %s (%s)" % (page, link, reason))
    print("%d broken links." % len(broken))


def self_test() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "ok.html").write_text('<h1 id="here">Ok</h1>\n', encoding="utf-8")
        (root / "index.html").write_text(
            "\n".join([
                '<a href="ok.html">good</a>',
                '<a href="ok.html#here">good anchor</a>',
                '<a href="missing.html">missing</a>',
                '<a href="ok.html#nope">bad anchor</a>',
                '<a href="https://trusdan.github.io/wyrd/ok.html">absolute</a>',
            ]),
            encoding="utf-8",
        )
        broken = check(root)
    report(broken)
    expected = {
        ("index.html", "missing.html", "missing file"),
        ("index.html", "ok.html#nope", "missing anchor"),
    }
    found = set(broken)
    if found != expected:
        print("self-test expected %s, found %s" % (sorted(expected), sorted(found)), file=sys.stderr)
        return 1
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Check internal links in a built site.")
    parser.add_argument("site", nargs="?")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        sys.exit(self_test())
    if not args.site:
        print("usage: tools/site_links.py <built site dir>", file=sys.stderr)
        sys.exit(2)
    site = Path(args.site)
    if not site.is_dir():
        print("%s is not a directory" % site, file=sys.stderr)
        sys.exit(2)
    broken = check(site)
    report(broken)
    sys.exit(1 if broken else 0)


if __name__ == "__main__":
    main()
