// The cover's one instrument: a line of text, read character by character, with
// the library's own answer printed beside it.
//
// Every offset is asked twice — what the reader makes of the text before a
// character, and what it makes of the text up to it — so the head can sit on a
// character and the report can say what that character did.

const engine = await import("../engine/moonpsec.js").catch(() => null);

/* ---- day and night ---- */

const root = document.documentElement;
const themeButton = document.querySelector("[data-theme-toggle]");

function themeNow() {
  return root.dataset.theme ||
    (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
}

function paintTheme() {
  const now = themeNow();
  if (themeButton) {
    themeButton.textContent = now === "dark" ? "day" : "night";
    themeButton.setAttribute("aria-label", `Switch to the ${now === "dark" ? "day" : "night"} plate`);
  }
}

paintTheme();

themeButton?.addEventListener("click", () => {
  const next = themeNow() === "dark" ? "light" : "dark";
  root.dataset.theme = next;
  sessionStorage.setItem("moonpsec-theme", next);
  paintTheme();
});

/* ---- the tape ---- */

const tape = document.querySelector("[data-tape]");
const strip = document.querySelector("[data-strip]");
const readEl = document.querySelector("[data-read]");
const headEl = document.querySelector("[data-head]");
const unreadEl = document.querySelector("[data-unread]");
const posEl = document.querySelector("[data-pos]");
const stateEl = document.querySelector("[data-state]");
const gotEl = document.querySelector("[data-got]");
const wantEl = document.querySelector("[data-want]");
const hold = document.querySelector("[data-hold]");

if (tape && strip && readEl && headEl && unreadEl) {
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

  // The two answers at every offset, asked once when the page loads.
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

  const stripLeft = () => Number.parseFloat(getComputedStyle(strip).left) || 0;
  const shift = () => Number.parseFloat(strip.style.getPropertyValue("--x")) || 0;

  function charWidth() {
    return length > 0 ? strip.getBoundingClientRect().width / length : 8;
  }

  // The line is wider than the frame on a small screen; past that, the strip
  // slides so the head stays inside it.
  function scrollFor(head) {
    return -Math.max(0, head.offsetLeft + 96 - tape.clientWidth);
  }

  function draw() {
    const step = steps[Math.min(at, length - 1)];
    const isStop = Boolean(step && step.refused);
    const state = !engine ? "no reader" : isStop ? "refused" : "waiting";

    readEl.textContent = text.slice(0, at);
    headEl.textContent = at < length ? text[at] : "";
    headEl.className = isStop ? "stop" : "head";
    unreadEl.textContent = text.slice(at + 1);
    unreadEl.className = "unread";

    strip.style.setProperty("--x", `${scrollFor(headEl)}px`);

    if (posEl) posEl.textContent = step ? `${step.line}:${step.column}` : "—";
    if (stateEl) {
      stateEl.textContent = state;
      stateEl.classList.toggle("is-refused", isStop);
      stateEl.classList.toggle("hot", !isStop);
    }
    if (gotEl) {
      gotEl.textContent = isStop && step.got ? step.got : "—";
      gotEl.classList.toggle("hot", isStop);
    }
    if (wantEl) {
      wantEl.textContent = isStop && step.want.length ? step.want.join(", ") : "—";
      wantEl.classList.toggle("hot", isStop);
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
          holdUntil = now + 2800;
          draw();
        } else {
          at += 1;
          nextStep = now + 55;
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

  tape.addEventListener("click", (event) => {
    const box = tape.getBoundingClientRect();
    const stripX = event.clientX - box.left - stripLeft() - shift();
    paused = true;
    label();
    place(Math.round(stripX / charWidth()));
  });

  tape.addEventListener("keydown", (event) => {
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
  if (!engine && stateEl) stateEl.textContent = "no reader";
  if (!engine && hold) hold.hidden = true;

  build();
  label();
  at = reduced ? stopAt : 0;
  draw();
  if (!reduced && engine) requestAnimationFrame(frame);

  // Monospace means one measurement holds for the whole line — once the face
  // has arrived. Until then the browser is measuring a fallback.
  document.fonts?.ready.then(() => draw());
}
