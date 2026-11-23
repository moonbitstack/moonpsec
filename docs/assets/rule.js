// The page scroll bar is out of the way at the top and shows from the first
// pixel scrolled; its width stays, so nothing shifts when it appears.
//
// Wrapped, because a classic script shares the global scope with every other
// classic script on the page: a bare `const root` here would stop theme.js
// from parsing, and the theme button would be dead.
(() => {
  const root = document.documentElement;
  const mark = () => root.classList.toggle("at-top", scrollY === 0);
  addEventListener("scroll", mark, { passive: true });
  addEventListener("resize", mark, { passive: true });
  mark();
})();
