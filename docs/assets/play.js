// Two benches: the reader on a document of your own, and the tree an operator
// table builds. Both run the library compiled from the sources.

const engine = await import("../engine/moonpsec.js").catch(() => null);

/* ---- the tree ---- */

const bench = document.querySelector("[data-tree-bench]");

if (bench) {
  const field = bench.querySelector("[data-expression]");
  const out = bench.querySelector("[data-tree]");
  const verdict = bench.querySelector("[data-tree-verdict]");

  function node(value) {
    const wrap = document.createElement("div");
    if (value.kind === "number") {
      wrap.className = "leaf";
      wrap.textContent = String(value.value);
      return wrap;
    }
    if (value.kind === "negate") {
      wrap.className = "branch";
      const chip = document.createElement("span");
      chip.className = "op";
      chip.textContent = "−";
      wrap.append(chip, list([value.inner]));
      return wrap;
    }
    const chip = document.createElement("span");
    chip.className = "op";
    chip.textContent = value.op;
    wrap.className = "branch";
    wrap.append(chip, list([value.left, value.right]));
    return wrap;
  }

  function list(children) {
    const ul = document.createElement("ul");
    for (const child of children) {
      const li = document.createElement("li");
      li.append(node(child));
      ul.append(li);
    }
    return ul;
  }

  function draw() {
    const text = field.value;
    out.replaceChildren();
    if (!engine) {
      verdict.textContent = "the reader is built when this page is deployed";
      return;
    }
    const answer = JSON.parse(engine.expression(text));
    if (!answer.ok) {
      verdict.textContent = `${answer.line}:${answer.column} — unexpected ${answer.got || "nothing"}, expecting ${answer.want.join(" or ") || "something"}`;
      verdict.classList.add("red");
      return;
    }
    verdict.classList.remove("red");
    verdict.textContent = `= ${answer.value}`;
    out.append(node(answer.tree));
  }

  field.addEventListener("input", draw);

  for (const chip of document.querySelectorAll("[data-sample-expr]")) {
    chip.addEventListener("click", () => {
      field.value = chip.dataset.sampleExpr;
      draw();
      field.focus();
    });
  }

  draw();
}

/* ---- the document bench ---- */

const docBench = document.querySelector("[data-doc-bench]");
if (docBench) {
  const field = docBench.querySelector("[data-document]");
  const counter = docBench.querySelector("[data-count]");
  const update = () => {
    if (counter) counter.textContent = `${field.value.length} characters · ${[...field.value].length} code points`;
  };
  field.addEventListener("input", update);
  update();
}
