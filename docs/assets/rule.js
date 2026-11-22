// The page scroll bar is out of the way at the top and shows from the first
// pixel scrolled; its width stays, so nothing shifts when it appears.
const root = document.documentElement;
const mark = () => root.classList.toggle("at-top", scrollY === 0);
addEventListener("scroll", mark, { passive: true });
addEventListener("resize", mark, { passive: true });
mark();
