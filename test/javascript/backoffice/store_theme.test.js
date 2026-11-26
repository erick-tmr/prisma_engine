import { afterEach, describe, expect, it, vi } from "vitest";
import { initStoreTheme } from "../../../app/javascript/backoffice/store_theme.js";

const mount = () => {
  document.body.innerHTML = `
    <div class="app" data-list="store-theme">
      <aside data-sidebar></aside>
      <button id="menu-toggle" type="button">menu</button>
      <div class="od-flash"><button type="button" data-flash-close>x</button></div>
      <form data-confirm="Desligar?"><button type="submit">off</button></form>
    </div>`;
  return document.querySelector("[data-list]");
};

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
});

describe("initStoreTheme", () => {
  it("wires the sidebar toggle, flash dismissal and the turn-off confirmation", () => {
    const root = mount();
    initStoreTheme(root);

    root.querySelector("#menu-toggle").click();
    expect(root.querySelector("[data-sidebar]").classList.contains("show")).toBe(true);

    root.querySelector("[data-flash-close]").click();
    expect(root.querySelector(".od-flash")).toBeNull();

    vi.spyOn(window, "confirm").mockReturnValue(false);
    const event = new window.Event("submit", { cancelable: true });
    root.querySelector("form").dispatchEvent(event);
    expect(event.defaultPrevented).toBe(true);
  });
});
