import { afterEach, describe, expect, it } from "vitest";
import { createSignupEmailEdit } from "../../app/javascript/storefront/signup_email_edit.js";

function mount() {
  document.body.innerHTML = `
    <div data-email-edit>
      <span data-email-edit-view>
        errado@gmial.com
        <button type="button" data-email-edit-open>Alterar</button>
      </span>
      <form data-email-edit-form hidden>
        <input type="email" value="errado@gmial.com">
        <button type="submit">Salvar e reenviar</button>
        <button type="button" data-email-edit-cancel>Cancelar</button>
      </form>
    </div>`;
  const root = document.querySelector("[data-email-edit]");
  return {
    root,
    view: root.querySelector("[data-email-edit-view]"),
    form: root.querySelector("[data-email-edit-form]"),
    input: root.querySelector('input[type="email"]'),
    openButton: root.querySelector("[data-email-edit-open]"),
    cancelButton: root.querySelector("[data-email-edit-cancel]"),
  };
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("createSignupEmailEdit", () => {
  it("swaps the pill for the form and focuses the address", () => {
    const { root, view, form, input, openButton } = mount();
    createSignupEmailEdit(root);

    openButton.click();

    expect(view.hidden).toBe(true);
    expect(form.hidden).toBe(false);
    expect(document.activeElement).toBe(input);
  });

  it("cancelling restores the pill and discards the typed address", () => {
    const { root, view, form, input, openButton, cancelButton } = mount();
    createSignupEmailEdit(root);
    openButton.click();
    input.value = "meio-digitado@";

    cancelButton.click();

    expect(form.hidden).toBe(true);
    expect(view.hidden).toBe(false);
    expect(input.value).toBe("errado@gmial.com");
    expect(document.activeElement).toBe(openButton);
  });

  it("Escape inside the form cancels the edit", () => {
    const { root, view, form, input, openButton } = mount();
    createSignupEmailEdit(root);
    openButton.click();

    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));

    expect(form.hidden).toBe(true);
    expect(view.hidden).toBe(false);
  });

  it("other keys leave the form open", () => {
    const { root, form, input, openButton } = mount();
    createSignupEmailEdit(root);
    openButton.click();

    input.dispatchEvent(new KeyboardEvent("keydown", { key: "a", bubbles: true }));

    expect(form.hidden).toBe(false);
  });
});
