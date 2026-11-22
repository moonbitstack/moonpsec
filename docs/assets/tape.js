// The tape: one document, cut at a place the reader can move. At every cut the
// page asks the library two things — is it waiting for more, and what would it
// say if the text ended here — and draws the answers. The reader is the
// library's own incremental one, built from the sources by the docs workflow.

const engine = await import("../engine/moonpsec.js").catch(() => null);

const root = document.querySelector("[data-tape-root]");
if (root) {
  const line = root.querySelector("[data-line]");
  const read = root.querySelector("[data-read]");
  const bad = root.querySelector("[data-bad]");
  const rest = root.querySelector("[data-rest]");
  const caret = root.querySelector("[data-caret]");
  const scrub = root.querySelector("[data-scrub]");
  const pos = root.querySelector("[data-pos]");
  const got = root.querySelector("[data-got]");
  const want = root.querySelector("[data-want]");
  const state = root.querySelector("[data-state]");
  const playButton = root.querySelector("[data-play]");
  const samples = [...document.querySelectorAll("[data-sample]")];

  const field = root.querySelector("[data-text-input]");
  let text = field ? field.value : samples[0]?.dataset.sample ?? "";
  let cut = 0;
  let timer = null;

  if (!engine) {
    root.classList.add("no-engine");
    if (state) state.textContent = "the reader is built when this page is deployed";
  }

  const clamp = (value) => Math.max(0, Math.min(text.length, value));

  function draw(place) {
    const at = clamp(place);
    const finding = engine && at < text.length ? JSON.parse(engine.cut(text, at)) : null;
    const ending = engine && at === text.length ? JSON.parse(engine.verdict(text)) : null;
    const refusal = ending && !ending.ok ? ending : finding && !finding.ending.ok ? finding.ending : null;

    read.textContent = text.slice(0, at);
    const culpable = refusal ? refusal.at : -1;
    if (culpable >= at && culpable < text.length) {
      bad.textContent = text[culpable];
      bad.hidden = false;
      rest.textContent = text.slice(at, culpable) + text.slice(culpable + 1);
    } else {
      bad.hidden = true;
      bad.textContent = "";
      rest.textContent = text.slice(at);
    }

    caret.hidden = false;
    caret.style.left = `${read.getBoundingClientRect().width}px`;

    if (pos) {
      pos.textContent = refusal ? `${refusal.line}:${refusal.column}` : at === text.length ? "end" : "—:—";
      pos.classList.toggle("red", Boolean(refusal));
    }
    if (got) {
      got.textContent = refusal ? refusal.got || "(nothing named)" : "—";
      got.classList.toggle("red", Boolean(refusal));
    }
    if (want) {
      want.textContent = refusal && refusal.want.length ? refusal.want.join(", ") : refusal ? "nothing named" : "—";
      want.classList.toggle("red", Boolean(refusal));
    }
    if (state) {
      state.textContent = !engine
        ? "reader not built here"
        : ending
          ? ending.ok
            ? "accepted; the text ends here"
            : "refused"
          : finding.waiting
            ? "waiting for the rest of the text"
            : "a value is complete";
      state.classList.toggle("red", Boolean(refusal));
      state.classList.toggle("muted", !refusal);
    }
  }

  function seek(value) {
    cut = clamp(value);
    scrub.value = String(cut);
    draw(cut);
  }

  scrub.max = String(text.length);
  scrub.addEventListener("input", () => {
    stop();
    seek(Number(scrub.value));
  });

  function choose(sample) {
    stop();
    text = sample;
    scrub.max = String(text.length);
    for (const button of samples) button.setAttribute("aria-pressed", String(button.dataset.sample === sample));
    seek(0);
  }

  field?.addEventListener("input", () => {
    stop();
    text = field.value;
    scrub.max = String(text.length);
    seek(0);
  });

  for (const button of samples) {
    button.setAttribute("aria-pressed", String(button.dataset.sample === text));
    button.addEventListener("click", () => choose(button.dataset.sample));
  }

  function stop() {
    if (timer) {
      clearInterval(timer);
      timer = null;
      if (playButton) playButton.textContent = "read it";
    }
  }

  playButton?.addEventListener("click", () => {
    if (timer) {
      stop();
      return;
    }
    if (cut >= text.length) seek(0);
    playButton.textContent = "hold";
    timer = setInterval(() => {
      if (cut >= text.length) {
        stop();
        return;
      }
      seek(cut + 1);
    }, 55);
  });

  addEventListener("resize", () => draw(cut), { passive: true });
  draw(0);
}
