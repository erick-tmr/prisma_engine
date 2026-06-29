import { afterEach, describe, expect, it } from "vitest";
import { bindAccordion } from "../../app/javascript/storefront/faq.js";

function mountFaq() {
  document.body.innerHTML = `
    <div data-faq>
      <section data-topic-group>
        <article data-faq-item>
          <button data-faq-toggle aria-expanded="false">P1</button>
          <div class="qa__a"></div>
        </article>
        <article data-faq-item>
          <button data-faq-toggle aria-expanded="false">P2</button>
          <div class="qa__a"></div>
        </article>
      </section>
      <section data-topic-group>
        <article data-faq-item>
          <button data-faq-toggle aria-expanded="false">P3</button>
          <div class="qa__a"></div>
        </article>
      </section>
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
