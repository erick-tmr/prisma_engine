import { afterEach, describe, expect, it, vi } from "vitest";
import { createResendCooldown } from "../../app/javascript/storefront/resend_cooldown.js";

function mount(deadlineISO) {
  document.body.innerHTML = `
    <form data-resend data-resend-deadline="${deadlineISO}" data-resend-wait-text="Aguarde {s}s para reenviar">
      <button type="submit" data-resend-submit></button>
      <span data-resend-status></span>
    </form>`;
  return document.querySelector("[data-resend]");
}

afterEach(() => {
  vi.useRealTimers();
  document.body.innerHTML = "";
});

describe("createResendCooldown", () => {
  it("disables the button and shows the remaining seconds while cooling down", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-06-13T10:00:00Z"));
    const root = mount("2026-06-13T10:00:45Z"); // 45s ahead
    const cooldown = createResendCooldown(root);

    expect(cooldown.tick()).toBe(true);
    expect(root.querySelector("[data-resend-submit]").disabled).toBe(true);
    expect(root.querySelector("[data-resend-status]").textContent).toBe("Aguarde 45s para reenviar");
  });

  it("re-enables the button and clears the label once the deadline passes", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-06-13T10:00:01Z"));
    const root = mount("2026-06-13T10:00:00Z"); // already past
    const button = root.querySelector("[data-resend-submit]");
    button.disabled = true;
    const cooldown = createResendCooldown(root);

    expect(cooldown.tick()).toBe(false);
    expect(button.disabled).toBe(false);
    expect(root.querySelector("[data-resend-status]").textContent).toBe("");
  });
});
