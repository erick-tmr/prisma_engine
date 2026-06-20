import { afterEach, describe, expect, it, vi } from "vitest";
import { bindFlashDismiss } from "../../app/javascript/storefront/flash.js";

afterEach(() => {
  document.body.innerHTML = "";
  vi.useRealTimers();
});

describe("bindFlashDismiss", () => {
  it("fades out then removes the flash when its close button is clicked", () => {
    vi.useFakeTimers();
    document.body.innerHTML = `
      <div class="flash-stack">
        <div class="flash flash--info" role="alert">
          <div class="flash__body">Login efetuado com sucesso.</div>
          <button type="button" class="flash__close" aria-label="Fechar"></button>
        </div>
      </div>
    `;
    bindFlashDismiss(document);

    const flash = document.querySelector(".flash");
    document.querySelector(".flash__close").click();

    expect(flash.style.opacity).toBe("0");
    expect(document.querySelector(".flash")).not.toBeNull();

    vi.advanceTimersByTime(150);
    expect(document.querySelector(".flash")).toBeNull();
  });

  it("ignores a stray close button that is not inside a flash", () => {
    document.body.innerHTML = `<button type="button" class="flash__close"></button>`;
    bindFlashDismiss(document);

    expect(() => document.querySelector(".flash__close").click()).not.toThrow();
  });
});
