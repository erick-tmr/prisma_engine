import { afterEach, describe, expect, it, vi } from "vitest";
import { bindAccordion, setActiveRail, bindRailNavigation } from "../../app/javascript/storefront/faq.js";

function mountFaq() {
  document.body.innerHTML = `
    <div data-faq>
      <aside>
        <a class="rail-link" data-rail-link data-target="g-1">Um</a>
        <a class="rail-link" data-rail-link data-target="g-2">Dois</a>
        <a class="rail-link" data-rail-link data-target="g-missing">Sumido</a>
      </aside>
      <div>
        <section id="g-1" data-faq-group>
          <article data-faq-item>
            <button data-faq-toggle aria-expanded="false">P1</button>
            <div class="qa__a"></div>
          </article>
          <article data-faq-item>
            <button data-faq-toggle aria-expanded="false">P2</button>
            <div class="qa__a"></div>
          </article>
        </section>
        <section id="g-2" data-faq-group>
          <article data-faq-item>
            <button data-faq-toggle aria-expanded="false">P3</button>
            <div class="qa__a"></div>
          </article>
        </section>
      </div>
    </div>
  `;
  return document.querySelector("[data-faq]");
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("bindAccordion", () => {
  it("opens the first item by default and leaves the rest closed", () => {
    const root = mountFaq();
    bindAccordion(root);
    const items = root.querySelectorAll("[data-faq-item]");
    expect(items[0].classList.contains("is-open")).toBe(true);
    expect(items[0].querySelector("[data-faq-toggle]").getAttribute("aria-expanded")).toBe("true");
    expect(items[1].classList.contains("is-open")).toBe(false);
    expect(items[1].querySelector("[data-faq-toggle]").getAttribute("aria-expanded")).toBe("false");
  });

  it("toggles an item open and closed on click", () => {
    const root = mountFaq();
    bindAccordion(root);
    const second = root.querySelectorAll("[data-faq-item]")[1];
    const button = second.querySelector("[data-faq-toggle]");

    button.click();
    expect(second.classList.contains("is-open")).toBe(true);
    expect(button.getAttribute("aria-expanded")).toBe("true");

    button.click();
    expect(second.classList.contains("is-open")).toBe(false);
    expect(button.getAttribute("aria-expanded")).toBe("false");
  });

  it("closes the first item when its own button is clicked", () => {
    const root = mountFaq();
    bindAccordion(root);
    const first = root.querySelector("[data-faq-item]");
    first.querySelector("[data-faq-toggle]").click();
    expect(first.classList.contains("is-open")).toBe(false);
  });
});

describe("setActiveRail", () => {
  it("activates only the link matching the id", () => {
    mountFaq();
    const links = document.querySelectorAll("[data-rail-link]");
    setActiveRail(links, "g-2");
    expect(document.querySelector('[data-target="g-1"]').classList.contains("is-active")).toBe(false);
    expect(document.querySelector('[data-target="g-2"]').classList.contains("is-active")).toBe(true);
  });

  it("moves the highlight when the active id changes", () => {
    mountFaq();
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
    mountFaq();
    window.scrollTo = vi.fn();
    bindRailNavigation(document);
    const link = document.querySelector('[data-target="g-2"]');
    const prevented = !link.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
    expect(prevented).toBe(true);
    expect(window.scrollTo).toHaveBeenCalledWith({ top: -16, behavior: "smooth" });
  });

  it("does nothing when the target group is missing", () => {
    mountFaq();
    window.scrollTo = vi.fn();
    bindRailNavigation(document);
    document.querySelector('[data-target="g-missing"]').click();
    expect(window.scrollTo).not.toHaveBeenCalled();
  });
});
