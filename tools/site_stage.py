#!/usr/bin/env python3
"""Copy docs/ into a Jekyll source tree. Wraps each page so Liquid leaves {{ alone."""

import argparse
import shutil
import sys
from pathlib import Path


# Process notes and moved pointers are not site pages.
EXCLUDED = (
    "docs/spikes",
    "docs/m3-exit-demo.md",
    "docs/grammar-v1.md",
    "docs/statements-draft.md",
    "docs/conditions-draft.md",
    "docs/events-draft.md",
)

ROOT = Path.cwd()
DOCS = ROOT / "docs"
SITE = ROOT / "tools" / "site"
GITHUB = "https://github.com/Trusdan/wyrd/blob/main/"


def excluded(rel: str) -> bool:
    rel = rel.replace("\\", "/")
    if rel == "docs/spikes" or rel.startswith("docs/spikes/"):
        return True
    return rel in EXCLUDED


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


def title_of(text: str, name: str) -> str:
    heading = ""
    for line in text.splitlines():
        if line.startswith("#"):
            heading = line.lstrip("#").strip().replace("`", "")
            break
    if not heading:
        heading = Path(name).stem
    return heading.replace("\\", "\\\\").replace('"', '\\"')


def split_target(raw: str) -> tuple:
    body = raw.strip()
    if body.startswith("<") and ">" in body:
        body = body[1:body.index(">")]
    body = body.split()[0] if body else ""
    path = body
    fragment = ""
    if "#" in path:
        path, fragment = path.split("#", 1)
        fragment = "#" + fragment
    query = ""
    if "?" in path:
        path, query = path.split("?", 1)
        query = "?" + query
    return path, query, fragment


def rewrite_links(text: str, page_rel: Path) -> str:
    lines = text.splitlines(keepends=True)
    out = []
    fence = False
    page_dir = DOCS / page_rel.parent
    for line in lines:
        stripped = line.lstrip()
        if stripped.startswith("```"):
            fence = not fence
            out.append(line)
            continue
        if fence:
            out.append(line)
            continue
        out.append(_rewrite_line(line, page_rel, page_dir))
    return "".join(out)


def _rewrite_line(line: str, page_rel: Path, page_dir: Path) -> str:
    result = []
    index = 0
    while True:
        start = line.find("](", index)
        if start < 0:
            result.append(line[index:])
            break
        # Keep image and ordinary links; both use ](.
        end = line.find(")", start + 2)
        if end < 0:
            result.append(line[index:])
            break
        result.append(line[index:start + 2])
        target = line[start + 2:end]
        result.append(_one_link(target, page_rel, page_dir))
        result.append(")")
        index = end + 1
    return "".join(result)


def _one_link(target: str, page_rel: Path, page_dir: Path) -> str:
    path, query, fragment = split_target(target)
    if not path or path.startswith("#"):
        return target
    if path.startswith(("http://", "https://", "mailto:")):
        return target
    if path.startswith("/"):
        return target
    dest = (page_dir / path).resolve()
    try:
        rel = dest.relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        fail("%s: %s (outside the checkout)" % (page_rel.as_posix(), target.strip()))
    inside = rel == "docs" or rel.startswith("docs/")
    if inside and not excluded(rel):
        return target
    if not dest.is_file():
        fail("%s: %s (missing target)" % (page_rel.as_posix(), target.strip()))
    return GITHUB + rel + query + fragment


def copy_docs(out: Path) -> list:
    copied = []
    for source in DOCS.rglob("*"):
        if not source.is_file():
            continue
        rel = source.relative_to(ROOT).as_posix()
        if excluded(rel):
            continue
        dest = out / source.relative_to(DOCS)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)
        copied.append(source.relative_to(DOCS))
    return copied


def wrap_markdown(out: Path, pages: list) -> int:
    count = 0
    for rel in pages:
        if rel.suffix != ".md":
            continue
        path = out / rel
        text = path.read_text(encoding="utf-8")
        if text.startswith("---"):
            fail("%s starts with front matter" % rel.as_posix())
        if "{% endraw %}" in text:
            fail("%s contains {% endraw %}" % rel.as_posix())
        rewritten = rewrite_links(text, rel)
        title = title_of(text, rel.name)
        if not rewritten.endswith("\n"):
            rewritten += "\n"
        path.write_text(
            '---\ntitle: "%s"\n---\n{%% raw %%}\n%s{%% endraw %%}\n' % (title, rewritten),
            encoding="utf-8",
            newline="\n",
        )
        count += 1
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description="Stage docs/ as a Jekyll site source.")
    parser.add_argument("--out", default="_site_src")
    args = parser.parse_args()
    if not DOCS.is_dir():
        fail("docs/ is missing; run from the repo root")
    out = Path(args.out)
    if not out.is_absolute():
        out = ROOT / out
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    pages = copy_docs(out)
    shutil.copy2(SITE / "_config.yml", out / "_config.yml")
    shutil.copytree(SITE / "_layouts", out / "_layouts")
    (out / ".gdignore").write_text("Staged Jekyll copy. Godot must not import it.\n", encoding="utf-8")
    count = wrap_markdown(out, pages)
    print("Staged %d pages." % count)


if __name__ == "__main__":
    main()
