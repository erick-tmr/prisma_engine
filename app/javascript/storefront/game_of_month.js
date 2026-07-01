export function buildDots(dotsWrap, count, onSelect) {
  const dots = [];
  for (let i = 0; i < count; i += 1) {
    const dot = document.createElement("button");
    dot.type = "button";
    dot.className = "gotm-dot" + (i === 0 ? " is-active" : "");
    dot.setAttribute("aria-label", "Jogo " + (i + 1));
    dot.addEventListener("click", function () {
      onSelect(i);
    });
    dotsWrap.appendChild(dot);
    dots.push(dot);
  }
  return dots;
}

export function goToSlide(state, index) {
  const idx = (index + state.slides.length) % state.slides.length;
  state.track.style.transform = "translateX(-" + idx * 100 + "%)";
  state.dots.forEach(function (dot, i) {
    dot.classList.toggle("is-active", i === idx);
  });
  if (state.curEl) state.curEl.textContent = idx + 1;
  return idx;
}

export function initCarousel(root) {
  const track = root.querySelector("[data-gotm-track]");
  const slides = Array.prototype.slice.call(track.children);
  const dotsWrap = root.querySelector("[data-gotm-dots]");
  const prevBtn = root.querySelector("[data-gotm-prev]");
  const nextBtn = root.querySelector("[data-gotm-next]");
  const curEl = root.querySelector("[data-gotm-cur]");
  const totalEl = root.querySelector("[data-gotm-total]");
  const countEl = root.querySelector(".gotm-count");

  if (totalEl) totalEl.textContent = slides.length;

  if (slides.length < 2) {
    if (prevBtn) prevBtn.style.display = "none";
    if (nextBtn) nextBtn.style.display = "none";
    if (dotsWrap) dotsWrap.style.display = "none";
    if (countEl) countEl.style.display = "none";
    return null;
  }

  const state = { track: track, slides: slides, curEl: curEl, idx: 0, dots: [] };
  if (dotsWrap) {
    state.dots = buildDots(dotsWrap, slides.length, function (i) {
      controller.goTo(i);
    });
  }

  const controller = {
    goTo: function (index) {
      state.idx = goToSlide(state, index);
      return state.idx;
    },
    next: function () {
      return controller.goTo(state.idx + 1);
    },
    prev: function () {
      return controller.goTo(state.idx - 1);
    },
  };

  if (prevBtn) prevBtn.addEventListener("click", function () { controller.prev(); });
  if (nextBtn) nextBtn.addEventListener("click", function () { controller.next(); });

  controller.goTo(0);
  return controller;
}

/* v8 ignore start -- browser bootstrap; initCarousel is unit-tested */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-gotm]");
  if (root) {
    const carousel = initCarousel(root);
    if (carousel) {
      let timer = null;
      const autoplayAllowed = function () {
        return !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      };
      const start = function () {
        if (autoplayAllowed() && !timer) timer = setInterval(carousel.next, 6000);
      };
      const stop = function () {
        clearInterval(timer);
        timer = null;
      };
      root.addEventListener("mouseenter", stop);
      root.addEventListener("mouseleave", start);
      start();
    }
  }
}
/* v8 ignore stop */
