"""Write docs/api.html from the package's interface file and the `///` comments
in its sources, so the reference follows the code.

Usage: python scripts/gen_api.py, from the repository root. CI runs it and then
`git diff --exit-code`, so a page that no longer matches the code stops the
deploy instead of shipping a name the library does not have.
"""

import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKAGE = "moonpsec"
FOLDER = "src"
INTRO = (
    "Everything a grammar can name: the parsers that read a character or a run of "
    "them, the combinators that build bigger parsers out of smaller ones, the four "
    "ways to run one, and what comes back when the text is refused."
)
NOTE = (
    "Two types appear at the end because the interface names them, not because a "
    "grammar does: `State` is where a parser stands and `Reply` is what it answers "
    "with. They are built by the library; a grammar only holds parsers."
)

DECL = re.compile(r"^pub(?:\((?:\w+)\))?\s+(fn(?:\[[^\]]*\])?|let|struct|enum|suberror|type|typealias)\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)?)")
TYPE_KINDS = ("struct", "enum", "suberror")


def docs_of(folder):
    """Doc comments by declared name, and `//` notes on enum variants by
    `Enum::Variant`."""
    found = {}
    for path in sorted((ROOT / folder).glob("*.mbt")):
        if path.name.endswith(("_test.mbt", "_wbtest.mbt")):
            continue
        pending, owner = [], None
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped == "///|":
                pending = []
                continue
            if stripped.startswith("///"):
                pending.append(stripped[3:].strip())
                continue
            if stripped.startswith("#"):
                continue
            m = DECL.match(line)
            if m:
                if pending:
                    found[m.group(2)] = "\n".join(pending)
                owner = m.group(2).replace("::", "-") if (m.group(1) == "enum" and line.rstrip().endswith("{")) else None
                pending = []
                continue
            if owner:
                if line.startswith("}"):
                    owner = None
                else:
                    v = re.match(r"\s+([A-Z]\w*)\s*(?:\([^)]*\))?\s*$", line)
                    if v:
                        note = "\n".join(pending).strip()
                        if note:
                            found[owner + "::" + v.group(1)] = note
                        pending = []
                        continue
            pending = []
    return found


def items_of():
    """Declarations from the interface file, in the order it lists them."""
    lines = (ROOT / FOLDER / "pkg.generated.mbti").read_text(encoding="utf-8").splitlines()
    items, block, derives = [], None, []
    for line in lines:
        m = re.match(r"#derive\((.*)\)$", line)
        if m:
            derives = [part.strip().split(".")[-1] for part in m.group(1).split(",")]
            continue
        if block is not None:
            if line.startswith("}"):
                items.append(block)
                block = None
            else:
                block["variants"].append(line.strip())
            continue
        m = re.match(r"pub(?:\(\w+\))?\s+(enum|struct|suberror)\s+(\w+)", line)
        if m:
            block = {
                "kind": m.group(1),
                "name": m.group(2),
                "sig": line.rstrip(" {"),
                "variants": [],
                "derives": derives,
            }
            derives = []
            if not line.rstrip().endswith("{"):
                items.append(block)
                block = None
            continue
        m = re.match(r"pub fn(?:\[[^\]]*\])? (\w+)::(\w+)", line)
        if m:
            items.append({"kind": "method", "name": m.group(1) + "::" + m.group(2), "sig": line, "owner": m.group(1)})
            continue
        m = re.match(r"pub fn(?:\[[^\]]*\])? (\w+)", line)
        if m:
            items.append({"kind": "fn", "name": m.group(1), "sig": line})
            continue
        m = re.match(r"pub let (\w+)\s*:", line)
        if m:
            items.append({"kind": "let", "name": m.group(1), "sig": line})
            continue
    return items


def inline(text):
    if not text:
        return ""
    return f"<p>{markup(text)}</p>"


def markup(text):
    """Prose as HTML: code spans, and references to other names as links."""
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", html.escape(text, quote=False))

    def link(m):
        label, target = m.group(1), m.group(2)
        if target.startswith(("http://", "https://", "#")):
            return f'<a href="{target}">{label}</a>'
        if re.fullmatch(r"[A-Za-z_]\w*(?:::[A-Za-z_]\w*)?", target):
            return f'<a href="#{anchor(target)}">{label}</a>'
        return label

    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)


FENCE = re.compile(r"```[^\n`]*\n(.*?)```", re.S)


def prose(text):
    """A doc comment: its prose as paragraphs, its code as blocks, verbatim."""
    if not text:
        return ""
    out, pos = [], 0
    for m in FENCE.finditer(text):
        out.append(inline(text[pos : m.start()].strip()))
        out.append(f'<pre class="code">{html.escape(m.group(1).strip(chr(10)), quote=False)}</pre>')
        pos = m.end()
    out.append(inline(text[pos:].strip()))
    return "".join(part for part in out if part)


def sig(text):
    return f'<pre class="sig">{html.escape(text.strip(), quote=False)}</pre>'


def anchor(name):
    return "api-" + name.replace("::", "-").lower()


def declared():
    names = set()
    for line in (ROOT / FOLDER / "pkg.generated.mbti").read_text(encoding="utf-8").splitlines():
        m = re.match(r"pub(?:\(\w+\))?\s+(?:fn(?:\[[^\]]*\])?|let|struct|enum|suberror|trait|type|typealias)\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)?)", line)
        if m:
            names.add(m.group(1))
    return names


def render():
    docs = docs_of(FOLDER)
    items = items_of()
    types = [i for i in items if i["kind"] in TYPE_KINDS]
    methods, values, functions = {}, [], []
    for item in items:
        if item["kind"] == "method":
            methods.setdefault(item["owner"], []).append(item)
        elif item["kind"] == "let":
            values.append(item)
        elif item["kind"] == "fn":
            functions.append(item)

    nav = ['<li><a href="#api-top">moonpsec</a>']
    nav.append('<li><a href="#api-types">types</a><ol class="sub">')
    nav += [f'<li><a href="#{anchor(t["name"])}">{t["name"]}</a></li>' for t in types]
    nav.append("</ol></li>")
    nav.append('<li><a href="#api-values">values</a><ol class="sub">')
    nav += [f'<li><a href="#{anchor(v["name"])}">{v["name"]}</a></li>' for v in values]
    nav.append("</ol></li>")
    nav.append('<li><a href="#api-functions">functions</a><ol class="sub">')
    nav += [f'<li><a href="#{anchor(f["name"])}">{f["name"]}</a></li>' for f in functions]
    nav.append("</ol></li></li>")

    body = [f'<section id="api-top"><div class="band-head"><h2>moonpsec</h2><span class="route">moonbitstack/moonpsec</span></div>{inline(INTRO)}</section>']

    body.append('<section id="api-types"><h2 class="group">types</h2>')
    for t in types:
        body.append(f'<div class="entry" id="{anchor(t["name"])}">')
        body.append(f'<h3><span class="kind">{t["kind"]}</span>{t["name"]}</h3>')
        body.append(prose(docs.get(t["name"], "")))
        body.append(sig(t["sig"] + (" {" if t["variants"] else "")))
        if t["variants"]:
            rows = []
            for v in t["variants"]:
                name = re.match(r"([A-Z]\w*)", v)
                note = docs.get(f'{t["name"]}::{name.group(1)}', "") if name else ""
                rows.append(f'<li><code>{html.escape(v, quote=False)}</code>' + (f"<small>{markup(note)}</small>" if note else "") + "</li>")
            body.append(f'<ul class="variants">{"".join(rows)}</ul>')
        if t.get("derives"):
            body.append(inline("Derives " + ", ".join(f"`{n}`" for n in t["derives"]) + "."))
        for m in methods.get(t["name"], []):
            body.append(f'<div class="member" id="{anchor(m["name"])}">{sig(m["sig"])}{prose(docs.get(m["name"].replace("::", "::"), ""))}</div>')
        body.append("</div>")
    body.append("</section>")

    body.append('<section id="api-values"><h2 class="group">values</h2>')
    for v in values:
        body.append(f'<div class="entry" id="{anchor(v["name"])}"><h3><span class="kind">let</span>{v["name"]}</h3>{sig(v["sig"])}{prose(docs.get(v["name"], ""))}</div>')
    body.append("</section>")

    body.append('<section id="api-functions"><h2 class="group">functions</h2>')
    for f in functions:
        body.append(f'<div class="entry" id="{anchor(f["name"])}"><h3><span class="kind">fn</span>{f["name"]}</h3>{sig(f["sig"])}{prose(docs.get(f["name"], ""))}</div>')
    body.append("</section>")

    body.append(f'<section><div class="note" style="max-width:74ch">{inline(NOTE)}</div></section>')

    shown = {t["name"] for t in types} | {v["name"] for v in values} | {f["name"] for f in functions}
    shown |= {m["name"] for group in methods.values() for m in group}
    missing = sorted(name for name in declared() if name not in shown and name.split("::")[0] not in shown)
    if missing:
        raise SystemExit(f"the reference leaves out: {', '.join(missing)}")

    page = (ROOT / "docs" / "api.template.html").read_text(encoding="utf-8")
    page = page.replace("<!-- nav -->", "\n".join(nav)).replace("<!-- body -->", "\n".join(body))
    (ROOT / "docs" / "api.html").write_text(page, encoding="utf-8", newline="\n")
    print(f"{len(types)} types, {len(values)} values, {sum(len(v) for v in methods.values())} methods, {len(functions)} functions")


render()
