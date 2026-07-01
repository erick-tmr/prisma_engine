import { afterEach, describe, expect, it, vi } from "vitest";
import { buildDots, goToSlide, initCarousel } from "../../app/javascript/storefront/game_of_month.js";

function mountFull(slideCount) {
  const slides = Array.from({ length: slideCount }, () => '<article class="gotm-slide"></article>').join("");
  document.body.innerHTML = `
    <section data-gotm>
      <div class="gotm-carousel">
        <button data-gotm-prev>prev</button>
        <div class="gotm-viewport">
          <div class="gotm-track" data-gotm-track>${slides}</div>
        </div>
        <button data-gotm-next>next</button>
      </div>
      <div data-gotm-dots></div>
      <p class="gotm-count"><b data-gotm-cur>1</b> / <span data-gotm-total>${slideCount}</span></p>
    </section>
  `;
  return document.querySelector("[data-gotm]");
}

function mountBare(slideCount) {
  const slides = Array.from({ length: slideCount }, () => '<article class="gotm-slide"></article>').join("");
  document.body.innerHTML = `
    <section data-gotm>
      <div class="gotm-track" data-gotm-track>${slides}</div>
    </section>
  `;
  return document.querySelector("[data-gotm]");
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("buildDots", () => {
  it("creates one button per slide, marks the first active, and reports clicks by index", () => {
    document.body.innerHTML = "<div data-gotm-dots></div>";
    const wrap = document.querySelector("[data-gotm-dots]");
    const onSelect = vi.fn();

    const dots = buildDots(wrap, 3, onSelect);

    expect(dots).toHaveLength(3);
    expect(wrap.children).toHaveLength(3);
    expect(dots[0].classList.contains("is-active")).toBe(true);
    expect(dots[1].classList.contains("is-active")).toBe(false);
    expect(dots[2].getAttribute("aria-label")).toBe("Jogo 3");

    dots[2].click();
    expect(onSelect).toHaveBeenCalledWith(2);
  });
});

describe("goToSlide", () => {
  it("slides the track, updates the active dot, and writes the current-index label", () => {
    const track = document.createElement("div");
    const dots = [document.createElement("button"), document.createElement("button")];
    const curEl = document.createElement("b");
    const state = { track, dots, slides: [1, 2], curEl };

    const idx = goToSlide(state, 1);

    expect(idx).toBe(1);
    expect(track.style.transform).toBe("translateX(-100%)");
    expect(dots[0].classList.contains("is-active")).toBe(false);
    expect(dots[1].classList.contains("is-active")).toBe(true);
    expect(curEl.textContent).toBe("2");
  });

  it("wraps forward past the last slide and backward past the first", () => {
    const track = document.createElement("div");
    const dots = [document.createElement("button"), document.createElement("button")];
    const state = { track, dots, slides: [1, 2], curEl: null };

    expect(goToSlide(state, 2)).toBe(0);
    expect(goToSlide(state, -1)).toBe(1);
  });

  it("tolerates a missing current-index label", () => {
    const track = document.createElement("div");
    const state = { track, dots: [], slides: [1], curEl: null };
    expect(() => goToSlide(state, 0)).not.toThrow();
  });
});

describe("initCarousel", () => {
  it("hides prev/next/dots/count for a single slide and still fills the total", () => {
    const root = mountFull(1);

    const controller = initCarousel(root);

    expect(controller).toBeNull();
    expect(root.querySelector("[data-gotm-prev]").style.display).toBe("none");
    expect(root.querySelector("[data-gotm-next]").style.display).toBe("none");
    expect(root.querySelector("[data-gotm-dots]").style.display).toBe("none");
    expect(root.querySelector(".gotm-count").style.display).toBe("none");
    expect(root.querySelector("[data-gotm-total]").textContent).toBe("1");
  });

  it("tolerates a single slide with no controls in the DOM at all", () => {
    const root = mountBare(1);
    expect(() => initCarousel(root)).not.toThrow();
    expect(initCarousel(root)).toBeNull();
  });

  it("wires arrows and dots, wraps around, and keeps total/current labels in sync", () => {
    const root = mountFull(3);

    const controller = initCarousel(root);

    expect(root.querySelector("[data-gotm-total]").textContent).toBe("3");
    expect(root.querySelector("[data-gotm-cur]").textContent).toBe("1");

    root.querySelector("[data-gotm-next]").click();
    expect(root.querySelector("[data-gotm-cur]").textContent).toBe("2");

    root.querySelectorAll(".gotm-dot")[2].click();
    expect(root.querySelector("[data-gotm-cur]").textContent).toBe("3");

    root.querySelector("[data-gotm-next]").click();
    expect(root.querySelector("[data-gotm-cur]").textContent).toBe("1");

    root.querySelector("[data-gotm-prev]").click();
    expect(root.querySelector("[data-gotm-cur]").textContent).toBe("3");

    expect(controller.goTo(0)).toBe(0);
    expect(controller.next()).toBe(1);
    expect(controller.prev()).toBe(0);
  });

  it("still returns a working controller when arrows, dots, and labels are absent from the DOM", () => {
    const root = mountBare(2);

    const controller = initCarousel(root);

    expect(controller).not.toBeNull();
    expect(controller.next()).toBe(1);
    expect(controller.next()).toBe(0);
    expect(controller.prev()).toBe(1);
  });
});
