import { afterEach, describe, expect, it, vi } from "vitest";
import { setActiveRail, bindRailNavigation } from "../../app/javascript/storefront/topic_rail.js";

function mountRail() {
  document.body.innerHTML = `
    <div>
      <aside>
        <a class="rail-link" data-rail-link data-target="g-1">Um</a>
        <a class="rail-link" data-rail-link data-target="g-2">Dois</a>
        <a class="rail-link" data-rail-link data-target="g-missing">Sumido</a>
      </aside>
      <div>
        <section id="g-1" data-topic-group></section>
        <section id="g-2" data-topic-group></section>
      </div>
    </div>
  `;
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("setActiveRail", () => {
  it("activates only the link matching the id", () => {
    mountRail();
    const links = document.querySelectorAll("[data-rail-link]");
    setActiveRail(links, "g-2");
    expect(document.querySelector('[data-target="g-1"]').classList.contains("is-active")).toBe(false);
    expect(document.querySelector('[data-target="g-2"]').classList.contains("is-active")).toBe(true);
  });

  it("moves the highlight when the active id changes", () => {
    mountRail();
    const links = document.querySelectorAll("[data-rail-link]");
    setActiveRail(links, "g-1");
    expect(document.querySelector('[data-target="g-1"]').classList.contains("is-active")).toBe(true);
    setActiveRail(links, "g-2");
    expect(document.querySelector('[data-target="g-1"]').classList.contains("is-active")).toBe(false);
    expect(document.querySelector('[data-target="g-2"]').classList.contains("is-active")).toBe(true);
  });
});

describe("bindRailNavigation", () => {
  it("smooth-scrolls to the target group and prevents the default jump", () => {
    mountRail();
    window.scrollTo = vi.fn();
    bindRailNavigation(document);
    const link = document.querySelector('[data-target="g-2"]');
    const prevented = !link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    expect(prevented).toBe(true);
    expect(window.scrollTo).toHaveBeenCalledWith({ top: -16, behavior: "smooth" });
  });

  it("does nothing when the target group is missing", () => {
    mountRail();
    window.scrollTo = vi.fn();
    bindRailNavigation(document);
    document.querySelector('[data-target="g-missing"]').click();
    expect(window.scrollTo).not.toHaveBeenCalled();
  });
});
