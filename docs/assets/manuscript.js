// The document on the cover, read by the library itself.
//
// Every offset is asked twice: what the reader makes of the text before a
// character, and what it makes of the text up to it. That is enough for the
// caret, for the marginal note, and for the character that stops it.

const engine = await import("../engine/moonpsec.js").catch(() => null);

const manuscript = document.querySelector("[data-manuscript]");
const textWrap = document.querySelector(".m-text");
const readEl = document.querySelector("[data-read]");
const headEl = document.querySelector("[data-head]");
const unreadEl = document.querySelector("[data-unread]");
const caret = document.querySelector("[data-caret]");
const posEl = document.querySelector("[data-pos]");
const stateEl = document.querySelector("[data-state]");
const detailEl = document.querySelector("[data-detail]");
const hold = document.querySelector("[data-hold]");

if (manuscript && textWrap && readEl && headEl && unreadEl) {
  const text = unreadEl.textContent;
  const length = text.length;
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

  let steps = [];
  let stopAt = length;
  let at = 0;
  let paused = false;
  let phase = "read";
  let nextStep = 0;
  let holdUntil = 0;

  // The two answers at every offset, asked once, when the page loads.
  function build() {
    steps = [];
    stopAt = length;
    if (!engine) return;
    for (let index = 0; index < length; index += 1) {
      const before = JSON.parse(engine.cut(text, index));
      const after = JSON.parse(engine.cut(text, Math.min(index + 1, length)));
      const refused = !after.waiting && !after.ending.ok;
      steps.push({
        line: before.ending.line,
        column: before.ending.column,
        refused,
        got: refused ? after.ending.got : null,
        want: refused ? after.ending.want : [],
      });
      if (refused && stopAt === length) stopAt = index;
    }
  }

  function draw() {
    const step = steps[Math.min(at, length - 1)];
    const isStop = Boolean(step && step.refused);

    readEl.textContent = text.slice(0, at);
    headEl.textContent = at < length ? text[at] : "";
    headEl.className = isStop ? "stop" : "";
    unreadEl.textContent = text.slice(at + 1);
    unreadEl.className = "unread";

    if (caret) {
      if (!engine || at >= length) {
        caret.hidden = true;
      } else {
        const glyph = headEl.getBoundingClientRect();
        const box = textWrap.getBoundingClientRect();
        caret.hidden = false;
        caret.style.transform =
          `translate(${glyph.left - box.left}px, ${glyph.top - box.top}px)`;
        caret.style.height = `${glyph.height}px`;
      }
    }

    if (posEl) posEl.textContent = step ? `${step.line}:${step.column}` : "—:—";
    if (stateEl) {
      stateEl.textContent = !engine ? "not read" : isStop ? "refused" : "waiting";
      stateEl.classList.toggle("is-refused", isStop);
    }
    if (detailEl) {
      detailEl.textContent = !engine
        ? "the reader is built when this page is published"
        : isStop
          ? `unexpected ${step.got} — expecting ${step.want.join(" or ")}`
          : "the text could still continue here";
      detailEl.classList.toggle("is-refused", isStop);
    }
  }

  function label() {
    if (hold) hold.textContent = paused ? "read" : "hold";
  }

  function place(index) {
    at = Math.max(0, Math.min(stopAt, index));
    phase = "read";
    nextStep = performance.now() + 600;
    draw();
  }

  function frame(now) {
    if (!paused && steps.length) {
      if (phase === "read" && now >= nextStep) {
        if (at >= stopAt) {
          phase = "hold";
          holdUntil = now + 2600;
        } else {
          at += 1;
          nextStep = now + 70;
          draw();
        }
      } else if (phase === "hold" && now >= holdUntil) {
        phase = "restart";
        holdUntil = now + 650;
      } else if (phase === "restart" && now >= holdUntil) {
        at = 0;
        phase = "read";
        nextStep = now + 420;
        draw();
      }
    }
    requestAnimationFrame(frame);
  }

  /** The offset in the document under a point, which is what a click means. */
  function offsetAt(x, y) {
    let range = null;
    if (document.caretRangeFromPoint) {
      range = document.caretRangeFromPoint(x, y);
    } else if (document.caretPositionFromPoint) {
      const spot = document.caretPositionFromPoint(x, y);
      if (spot) {
        range = document.createRange();
        range.setStart(spot.offsetNode, spot.offset);
      }
    }
    if (!range || range.startContainer.nodeType !== Node.TEXT_NODE) return null;
    const parent = range.startContainer.parentElement;
    if (!parent || !manuscript.contains(parent)) return null;
    let index = range.startOffset;
    for (const span of manuscript.querySelectorAll("span")) {
      if (span === parent) break;
      index += span.textContent.length;
    }
    return index;
  }

  hold?.addEventListener("click", () => {
    paused = !paused;
    if (!paused) {
      if (at >= stopAt) at = 0;
      phase = "read";
      nextStep = performance.now() + 120;
    }
    label();
    draw();
  });

  manuscript.addEventListener("click", (event) => {
    const index = offsetAt(event.clientX, event.clientY);
    if (index === null) return;
    paused = true;
    label();
    place(index);
  });

  manuscript.addEventListener("keydown", (event) => {
    const step = { ArrowLeft: -1, ArrowRight: 1 }[event.key];
    if (step) {
      paused = true;
      label();
      place(at + step);
      event.preventDefault();
    } else if (event.key === " ") {
      paused = !paused;
      label();
      event.preventDefault();
    }
  });

  if (reduced && hold) hold.hidden = true;

  build();
  label();
  at = reduced ? stopAt : 0;
  draw();
  if (!reduced && engine) requestAnimationFrame(frame);
}
