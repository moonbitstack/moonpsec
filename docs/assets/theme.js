// The page follows the system until someone chooses; the choice lasts for the
// visit and no longer, so a refresh goes back to following the system.
const root = document.documentElement;
const button = document.querySelector("[data-theme-toggle]");

function current() {
  return root.dataset.theme || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
}

function paint(theme) {
  root.dataset.theme = theme;
  if (button) {
    button.textContent = theme === "dark" ? "light" : "dark";
    button.setAttribute("aria-label", `Switch to the ${theme === "dark" ? "light" : "dark"} plate`);
  }
}

paint(current());

button?.addEventListener("click", () => {
  const next = current() === "dark" ? "light" : "dark";
  sessionStorage.setItem("moonpsec-theme", next);
  paint(next);
});
