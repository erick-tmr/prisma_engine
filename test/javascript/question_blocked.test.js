import { afterEach, describe, expect, it } from "vitest";
import { initQuestionBlocked } from "../../app/javascript/storefront/question_blocked.js";

function mount() {
  document.body.innerHTML = `
    <form data-question-form>
      <textarea data-question-body>Chama no meu perfil que eu vendo mais barato</textarea>
      <button type="submit" data-question-submit>Enviar pergunta</button>
    </form>
    <div class="question-blocked" data-question-blocked aria-hidden="true">
      <div class="question-blocked__card" tabindex="-1" data-question-blocked-card>
        <button type="button" data-question-blocked-close aria-label="Fechar"></button>
        <button type="button" data-question-blocked-close>Entendi</button>
      </div>
    </div>
  `;

  const modal = document.querySelector("[data-question-blocked]");
  const form = document.querySelector("[data-question-form]");
  return { modal, form, api: initQuestionBlocked(modal, form) };
}

function pressEscape() {
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
}

afterEach(() => {
  document.body.innerHTML = "";
  document.body.style.overflow = "";
});

describe("initQuestionBlocked", () => {
  it("leaves the modal shut until the customer tries to send", () => {
    const { modal } = mount();

    expect(modal.classList.contains("is-open")).toBe(false);
    expect(modal.getAttribute("aria-hidden")).toBe("true");
  });

  it("opens the modal instead of submitting the question", () => {
    const { modal, form } = mount();
    const event = new Event("submit", { cancelable: true });

    form.dispatchEvent(event);

    expect(event.defaultPrevented).toBe(true);
    expect(modal.classList.contains("is-open")).toBe(true);
    expect(modal.getAttribute("aria-hidden")).toBe("false");
    expect(document.body.style.overflow).toBe("hidden");
  });

  it("keeps the unsent question in the field", () => {
    const { form } = mount();

    form.dispatchEvent(new Event("submit", { cancelable: true }));

    expect(form.querySelector("[data-question-body]").value)
      .toBe("Chama no meu perfil que eu vendo mais barato");
  });

  it("moves focus into the card on open and back to the button on close", () => {
    const { modal, api } = mount();

    api.open();
    expect(document.activeElement).toBe(modal.querySelector("[data-question-blocked-card]"));

    api.close();
    expect(document.activeElement).toBe(document.querySelector("[data-question-submit]"));
  });

  it("closes on the dismiss button and releases the page scroll", () => {
    const { modal, api } = mount();
    api.open();

    modal.querySelectorAll("[data-question-blocked-close]")[1].click();

    expect(modal.classList.contains("is-open")).toBe(false);
    expect(modal.getAttribute("aria-hidden")).toBe("true");
    expect(document.body.style.overflow).toBe("");
  });

  it("closes on the corner X", () => {
    const { modal, api } = mount();
    api.open();

    modal.querySelectorAll("[data-question-blocked-close]")[0].click();

    expect(modal.classList.contains("is-open")).toBe(false);
  });

  it("closes when the backdrop itself is clicked", () => {
    const { modal, api } = mount();
    api.open();

    modal.click();

    expect(modal.classList.contains("is-open")).toBe(false);
  });

  it("stays open when the click lands inside the card", () => {
    const { modal, api } = mount();
    api.open();

    modal.querySelector("[data-question-blocked-card]").click();

    expect(modal.classList.contains("is-open")).toBe(true);
  });

  it("closes on Escape", () => {
    const { modal, api } = mount();
    api.open();

    pressEscape();

    expect(modal.classList.contains("is-open")).toBe(false);
  });

  it("ignores Escape while the modal is already shut", () => {
    const { modal } = mount();
    const submit = document.querySelector("[data-question-submit]");

    pressEscape();

    expect(modal.classList.contains("is-open")).toBe(false);
    expect(document.activeElement).not.toBe(submit);
  });

  it("ignores other keys while the modal is open", () => {
    const { modal, api } = mount();
    api.open();

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));

    expect(modal.classList.contains("is-open")).toBe(true);
  });
});
