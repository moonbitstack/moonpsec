// The page follows the system until someone chooses; the choice lasts for the
// visit and no longer, so a refresh goes back to following the system.
//
// Wrapped for the same reason rule.js is: these are classic scripts in one
// global scope, and two `const root` declarations silently kill the second.
(() => {
  const root = document.documentElement;
  const button = document.querySelector("[data-theme-toggle]");

  const current = () =>
    root.dataset.theme ||
    (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");

  function paint(theme) {
    root.dataset.theme = theme;
    if (!button) return;
    const next = theme === "dark" ? "light" : "dark";
    button.textContent = next;
    button.setAttribute("aria-label", `Switch to the ${next} plate`);
  }

  paint(current());

  button?.addEventListener("click", () => {
    const next = current() === "dark" ? "light" : "dark";
    try {
      sessionStorage.setItem("moonpsec-theme", next);
    } catch {
      // Private modes refuse storage; the visit still changes, it just does
      // not survive to the next page.
    }
    paint(next);
  });
})();
