// Four documents, read by the library itself.
//
// The verdicts on the cover are not written into the page: each row hands its
// document to the parser compiled for this site and prints what comes back.
// With no reader (the engine is built at deploy time) the rows say so rather
// than inventing an answer.

const engine = await import("../engine/moonpsec.js").catch(() => null);
const rows = document.querySelectorAll("tr[data-doc]");

for (const row of rows) {
  const cell = row.querySelector(".verdict");
  const word = cell?.querySelector(".word");
  if (!cell || !word) continue;

  if (!engine) {
    word.textContent = "not read";
    continue;
  }

  const text = row.querySelector(".input code")?.textContent ?? "";
  let answer;
  try {
    answer = JSON.parse(engine.verdict(text));
  } catch {
    answer = null;
  }

  if (!answer) {
    word.textContent = "—";
    continue;
  }

  if (answer.ok) {
    word.textContent = "accepted";
    cell.classList.add("accepted");
    continue;
  }

  word.textContent = "refused";
  cell.classList.add("refused");
  const where = document.createElement("span");
  where.className = "where";
  where.textContent =
    ` · ${answer.line}:${answer.column} · unexpected ${answer.got} · expecting ${answer.want.join(" or ")}`;
  cell.append(where);
}
