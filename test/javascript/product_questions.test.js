import { afterEach, describe, expect, it } from "vitest";
import {
  bindComposer,
  bindReveal,
  moreLabel,
  initProductQuestions
} from "../../app/javascript/storefront/product_questions.js";

function composerMarkup() {
  return `
    <form data-question-form>
      <textarea data-question-body maxlength="500" data-min-length="10"></textarea>
      <span data-question-counter>0/500</span>
      <button type="submit" data-question-submit></button>
    </form>
  `;
}

function listMarkup(total, pageSize) {
  const items = Array.from({ length: total }, (_, i) => `<li data-question-item>P${i + 1}</li>`).join("");
  return `
    <ol data-question-list data-page-size="${pageSize}">${items}</ol>
    <p data-question-count data-template="Mostrando {n} de ${total} perguntas"></p>
    <button data-question-more hidden
            data-template-one="Ver mais {n} pergunta"
            data-template-other="Ver mais {n} perguntas"></button>
  `;
}

function mount(markup) {
  document.body.innerHTML = `<section data-product-questions>${markup}</section>`;
  return document.querySelector("[data-product-questions]");
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("bindComposer", () => {
  it("does nothing when the composer is absent", () => {
    const root = mount(`<div data-question-gate></div>`);

    expect(() => bindComposer(root)).not.toThrow();
  });

  it("disables the submit button on bind while the body is empty", () => {
    const root = mount(composerMarkup());
    bindComposer(root);

    expect(root.querySelector("[data-question-submit]").disabled).toBe(true);
    expect(root.querySelector("[data-question-counter]").textContent).toBe("0/500");
  });

  it("tracks the character count as the customer types", () => {
    const root = mount(composerMarkup());
    bindComposer(root);
    const input = root.querySelector("[data-question-body]");

    input.value = "Tem nota fiscal?";
    input.dispatchEvent(new Event("input"));

    expect(root.querySelector("[data-question-counter]").textContent).toBe("16/500");
  });

  it("enables the submit button once the body reaches the minimum length", () => {
    const root = mount(composerMarkup());
    bindComposer(root);
    const input = root.querySelector("[data-question-body]");

    input.value = "Funciona?";
    input.dispatchEvent(new Event("input"));
    expect(root.querySelector("[data-question-submit]").disabled).toBe(true);

    input.value = "Funciona no GBA?";
    input.dispatchEvent(new Event("input"));
    expect(root.querySelector("[data-question-submit]").disabled).toBe(false);
  });

  it("keeps the submit button disabled for whitespace only", () => {
    const root = mount(composerMarkup());
    bindComposer(root);
    const input = root.querySelector("[data-question-body]");

    input.value = "            ";
    input.dispatchEvent(new Event("input"));

    expect(root.querySelector("[data-question-submit]").disabled).toBe(true);
  });
});

describe("moreLabel", () => {
  it("picks the singular template for a single remaining question", () => {
    const root = mount(listMarkup(5, 4));
    const button = root.querySelector("[data-question-more]");

    expect(moreLabel(button, 1)).toBe("Ver mais 1 pergunta");
    expect(moreLabel(button, 3)).toBe("Ver mais 3 perguntas");
  });
});

describe("bindReveal", () => {
  it("does nothing when there is no list", () => {
    const root = mount(`<div class="product-questions__empty"></div>`);

    expect(() => bindReveal(root)).not.toThrow();
  });

  it("collapses the overflow and offers the rest behind the button", () => {
    const root = mount(listMarkup(7, 4));
    bindReveal(root);
    const items = root.querySelectorAll("[data-question-item]");

    expect(Array.from(items).map((item) => item.hidden))
      .toEqual([ false, false, false, false, true, true, true ]);
    expect(root.querySelector("[data-question-count]").textContent).toBe("Mostrando 4 de 7 perguntas");

    const more = root.querySelector("[data-question-more]");
    expect(more.hidden).toBe(false);
    expect(more.textContent).toBe("Ver mais 3 perguntas");
  });

  it("reveals the remaining questions and retires the button", () => {
    const root = mount(listMarkup(7, 4));
    bindReveal(root);
    const more = root.querySelector("[data-question-more]");

    more.click();

    expect(Array.from(root.querySelectorAll("[data-question-item]")).every((item) => !item.hidden)).toBe(true);
    expect(root.querySelector("[data-question-count]").textContent).toBe("Mostrando 7 de 7 perguntas");
    expect(more.hidden).toBe(true);
  });

  it("labels a single remaining question in the singular", () => {
    const root = mount(listMarkup(5, 4));
    bindReveal(root);

    expect(root.querySelector("[data-question-more]").textContent).toBe("Ver mais 1 pergunta");
  });

  it("hides the button when everything already fits", () => {
    const root = mount(listMarkup(3, 4));
    bindReveal(root);

    expect(root.querySelector("[data-question-more]").hidden).toBe(true);
    expect(root.querySelector("[data-question-count]").textContent).toBe("Mostrando 3 de 3 perguntas");
  });
});

describe("initProductQuestions", () => {
  it("binds the composer and the reveal together", () => {
    const root = mount(composerMarkup() + listMarkup(7, 4));
    initProductQuestions(root);

    expect(root.querySelector("[data-question-submit]").disabled).toBe(true);
    expect(root.querySelector("[data-question-more]").hidden).toBe(false);
  });
});
