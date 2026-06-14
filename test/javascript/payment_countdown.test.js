import { afterEach, describe, expect, it, vi } from "vitest";
import { createPaymentCountdown } from "../../app/javascript/storefront/payment_countdown.js";

function mount(deadlineISO) {
  document.body.innerHTML = `
    <div data-countdown data-deadline="${deadlineISO}">
      <span data-cd-h></span><span data-cd-m></span><span data-cd-s></span>
    </div>`;
  return document.querySelector("[data-countdown]");
}

afterEach(() => vi.useRealTimers());

describe("createPaymentCountdown", () => {
  it("renders the remaining h:m:s (zero-padded) and keeps counting", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-06-13T10:00:00Z"));
    const root = mount("2026-06-13T12:34:05Z"); // 2h 34m 05s ahead
    const onExpire = vi.fn();
    const countdown = createPaymentCountdown(root, onExpire);

    expect(countdown.tick()).toBe(true);
    expect(root.querySelector("[data-cd-h]").textContent).toBe("02");
    expect(root.querySelector("[data-cd-m]").textContent).toBe("34");
    expect(root.querySelector("[data-cd-s]").textContent).toBe("05");
    expect(onExpire).not.toHaveBeenCalled();
  });

  it("calls onExpire and stops once the deadline has passed", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-06-13T12:00:01Z"));
    const root = mount("2026-06-13T12:00:00Z"); // already past
    const onExpire = vi.fn();
    const countdown = createPaymentCountdown(root, onExpire);

    expect(countdown.tick()).toBe(false);
    expect(onExpire).toHaveBeenCalledOnce();
  });
});
