import { beforeEach, describe, expect, it, vi } from "vitest";
import { bindConfirm, bindMenu, bindFlashDismiss } from "../../../app/javascript/backoffice/order.js";

// Mirrors the data hooks in app/views/admin/orders/show.html.erb.
function mount() {
  document.body.innerHTML = `
    <div data-bo-order>
      <aside data-sidebar></aside>
      <button data-menu-toggle></button>
      <form data-confirm="Cancelar o pedido?" id="danger"><button type="submit"></button></form>
      <form id="safe"><button type="submit"></button></form>
    </div>`;
  return document.querySelector("[data-bo-order]");
}

function submit(form) {
  const event = new window.Event("submit", { cancelable: true, bubbles: true });
  form.dispatchEvent(event);
  return event;
}

describe("bindConfirm", () => {
  beforeEach(() => bindConfirm(mount()));

  it("lets the form submit when the operator confirms", () => {
    window.confirm = vi.fn(() => true);
    const event = submit(document.getElementById("danger"));
    expect(window.confirm).toHaveBeenCalledWith("Cancelar o pedido?");
    expect(event.defaultPrevented).toBe(false);
  });

  it("blocks the submit when the operator cancels", () => {
    window.confirm = vi.fn(() => false);
    const event = submit(document.getElementById("danger"));
    expect(event.defaultPrevented).toBe(true);
  });

  it("leaves forms without a confirm prompt untouched", () => {
    window.confirm = vi.fn(() => false);
    const event = submit(document.getElementById("safe"));
    expect(window.confirm).not.toHaveBeenCalled();
    expect(event.defaultPrevented).toBe(false);
  });
});

describe("bindMenu", () => {
  it("toggles the mobile sidebar open and closed", () => {
    const root = mount();
    bindMenu(root);
    const toggle = root.querySelector("[data-menu-toggle]");
    const sidebar = root.querySelector("[data-sidebar]");

    toggle.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    expect(sidebar.classList.contains("show")).toBe(true);

    toggle.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    expect(sidebar.classList.contains("show")).toBe(false);
  });
});

describe("bindFlashDismiss", () => {
  it("removes the flash when its close button is clicked", () => {
    document.body.innerHTML = `
      <div data-bo-order>
        <div class="od-flash od-flash--ok" role="alert">
          <span class="od-flash__msg">Pagamento confirmado.</span>
          <button type="button" class="od-flash__close" data-flash-close></button>
        </div>
      </div>`;
    const root = document.querySelector("[data-bo-order]");
    bindFlashDismiss(root);

    root.querySelector("[data-flash-close]").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    expect(document.querySelector(".od-flash")).toBeNull();
  });

  it("ignores a stray close button with no flash ancestor", () => {
    document.body.innerHTML = `<div data-bo-order><button type="button" data-flash-close></button></div>`;
    const root = document.querySelector("[data-bo-order]");
    bindFlashDismiss(root);

    expect(() =>
      root.querySelector("[data-flash-close]").dispatchEvent(new window.MouseEvent("click", { bubbles: true }))
    ).not.toThrow();
  });
});
