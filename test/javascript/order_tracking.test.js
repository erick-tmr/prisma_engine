import { afterEach, describe, expect, it, vi } from "vitest";
import { bindCopy, COPIED_MS } from "../../app/javascript/storefront/order_tracking.js";

function mount({ withButton = true, withValue = true } = {}) {
  document.body.innerHTML = `
    <div data-order-tracking>
      ${withValue ? '<span data-tracking-code> PG515656026BR </span>' : ""}
      ${withButton ? '<button data-tracking-copy><i class="bi bi-clipboard"></i></button>' : ""}
    </div>`;
  return document.querySelector("[data-order-tracking]");
}

const flush = async () => { await Promise.resolve(); await Promise.resolve(); };

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  document.body.innerHTML = "";
});

describe("bindCopy", () => {
  it("does nothing when the copy button is absent", () => {
    const root = mount({ withButton: false });
    expect(() => bindCopy(root)).not.toThrow();
  });

  it("does nothing when the code value is absent", () => {
    const root = mount({ withValue: false });
    bindCopy(root);
    const button = root.querySelector("[data-tracking-copy]");
    button.click();
    expect(button.classList.contains("is-copied")).toBe(false);
  });

  it("copies the trimmed code, flips to a check, then restores after the delay", async () => {
    vi.useFakeTimers();
    const writeText = vi.fn().mockResolvedValue(undefined);
    vi.stubGlobal("navigator", { clipboard: { writeText } });
    const root = mount();
    const button = root.querySelector("[data-tracking-copy]");
    const icon = button.querySelector("i");
    bindCopy(root);

    button.click();
    await flush();
    expect(writeText).toHaveBeenCalledWith("PG515656026BR");
    expect(button.classList.contains("is-copied")).toBe(true);
    expect(icon.className).toBe("bi bi-check2");

    vi.advanceTimersByTime(COPIED_MS);
    expect(button.classList.contains("is-copied")).toBe(false);
    expect(icon.className).toBe("bi bi-clipboard");
  });

  it("still confirms when the clipboard write rejects", async () => {
    vi.useFakeTimers();
    vi.stubGlobal("navigator", { clipboard: { writeText: vi.fn().mockRejectedValue(new Error("denied")) } });
    const root = mount();
    const button = root.querySelector("[data-tracking-copy]");
    bindCopy(root);

    button.click();
    await flush();
    expect(button.classList.contains("is-copied")).toBe(true);
    vi.advanceTimersByTime(COPIED_MS);
    expect(button.classList.contains("is-copied")).toBe(false);
  });

  it("falls back gracefully when the Clipboard API is unavailable", async () => {
    vi.useFakeTimers();
    vi.stubGlobal("navigator", {});
    const root = mount();
    const button = root.querySelector("[data-tracking-copy]");
    const icon = button.querySelector("i");
    bindCopy(root);

    button.click();
    await flush();
    expect(button.classList.contains("is-copied")).toBe(true);
    expect(icon.className).toBe("bi bi-check2");
  });
});
