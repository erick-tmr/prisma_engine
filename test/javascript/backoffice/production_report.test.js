import { afterEach, describe, expect, it, vi } from "vitest";
import { initConfirmModal, initPrint } from "../../../app/javascript/backoffice/production_report.js";

const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
});

describe("initConfirmModal", () => {
  it("opens and closes the modal through the data hooks", () => {
    document.body.innerHTML = `
      <button data-pr-open>open</button>
      <div data-pr-modal hidden>
        <button data-pr-close>cancel</button>
      </div>`;
    const api = initConfirmModal(document);
    expect(api).not.toBeNull();

    const modal = document.querySelector("[data-pr-modal]");
    expect(modal.hasAttribute("hidden")).toBe(true);

    click(document.querySelector("[data-pr-open]"));
    expect(modal.hasAttribute("hidden")).toBe(false);

    click(document.querySelector("[data-pr-close]"));
    expect(modal.hasAttribute("hidden")).toBe(true);
  });

  it("returns null when the page has no modal", () => {
    document.body.innerHTML = `<div></div>`;
    expect(initConfirmModal(document)).toBeNull();
  });
});

describe("initPrint", () => {
  it("prints when the print button is clicked", () => {
    const print = vi.spyOn(window, "print").mockImplementation(() => {});
    document.body.innerHTML = `<button data-pr-print>print</button>`;
    initPrint(document);
    click(document.querySelector("[data-pr-print]"));
    expect(print).toHaveBeenCalledOnce();
  });

  it("does nothing when there is no print button", () => {
    document.body.innerHTML = `<div></div>`;
    expect(() => initPrint(document)).not.toThrow();
  });
});
