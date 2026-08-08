import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { bindConfirm, bindFlashDismiss } from "../../../app/javascript/backoffice/shell.js";
import { ELAPSED_TICK_MS, RETRY_FAILED, bindMenu, elapsedText, initOrder, tickElapsed } from "../../../app/javascript/backoffice/order.js";
import { POLL_STEPS } from "../../../app/javascript/backoffice/label_feedback.js";

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

describe("elapsedText", () => {
  it("counts in seconds under a minute and in minutes past it", () => {
    expect(elapsedText(0)).toBe("0s");
    expect(elapsedText(59)).toBe("59s");
    expect(elapsedText(60)).toBe("1min 0s");
    expect(elapsedText(185)).toBe("3min 5s");
  });
});

describe("tickElapsed", () => {
  it("counts up from the moment the step started", () => {
    document.body.innerHTML = `<div data-bo-order><b data-elapsed-since="2026-08-06T10:00:00Z">0s</b></div>`;
    const root = document.querySelector("[data-bo-order]");

    tickElapsed(root, Date.parse("2026-08-06T10:00:42Z"));
    expect(root.querySelector("b").textContent).toBe("42s");
  });

  it("leaves an unparseable timestamp alone", () => {
    document.body.innerHTML = `<div data-bo-order><b data-elapsed-since="later">0s</b></div>`;
    const root = document.querySelector("[data-bo-order]");

    tickElapsed(root, Date.now());
    expect(root.querySelector("b").textContent).toBe("0s");
  });
});

describe("initOrder", () => {
  const detail = (state, extra = "") => `
    <div data-bo-order data-feedback-url="/admin/pedidos/PG-1/correios">
      <aside data-sidebar></aside>
      <button data-menu-toggle></button>
      <div class="od-head-num" data-part="head" data-cor-state="${state}"></div>
      <div data-part="status-card">${extra}</div>
    </div>`;

  let page;

  const mountDetail = (state, extra) => {
    document.body.innerHTML = detail(state, extra);
    document.head.innerHTML = `<meta name="csrf-token" content="test-token">`;
    page = initOrder(document.querySelector("[data-bo-order]"));
    return document.querySelector("[data-bo-order]");
  };

  beforeEach(() => {
    vi.spyOn(window, "fetch").mockResolvedValue({ ok: true, text: async () => "" });
  });

  afterEach(() => {
    page?.destroy();
    page = null;
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it("starts polling when the label is already in flight", () => {
    mountDetail("running");
    expect(page.feedback.running).toBe(true);
  });

  it("stays quiet on a settled order", () => {
    mountDetail("done");
    expect(page.feedback.running).toBe(false);
  });

  it("swaps the status card in place and rebinds its confirm prompts", async () => {
    vi.useFakeTimers();
    mountDetail("running");
    window.fetch.mockResolvedValue({
      ok: true,
      text: async () => `
        <div class="od-head-num" data-part="head" data-cor-state="done"></div>
        <div data-part="status-card"><form data-confirm="Cancelar?"><button type="submit"></button></form></div>`
    });

    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);

    expect(document.querySelector("[data-part='head']").dataset.corState).toBe("done");
    window.confirm = vi.fn(() => false);
    const event = new window.Event("submit", { cancelable: true, bubbles: true });
    document.querySelector("form[data-confirm]").dispatchEvent(event);
    expect(event.defaultPrevented).toBe(true);
  });

  it("retries a rejected label and resumes polling", async () => {
    const root = mountDetail("failed", `<button class="ap-retry" data-retry-url="/admin/etiquetas/PG-1"></button>`);

    root.querySelector(".ap-retry").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

    await vi.waitFor(() => expect(window.fetch).toHaveBeenCalledWith("/admin/etiquetas/PG-1", expect.objectContaining({
      method: "POST",
      headers: expect.objectContaining({ "X-CSRF-Token": "test-token" })
    })));
    await vi.waitFor(() => expect(page.feedback.running).toBe(true));
  });

  it("tells the operator when the retry is refused", async () => {
    window.fetch.mockResolvedValue({ ok: false });
    window.alert = vi.fn();
    const root = mountDetail("failed", `<button class="ap-retry" data-retry-url="/admin/etiquetas/PG-1"></button>`);

    root.querySelector(".ap-retry").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

    await vi.waitFor(() => expect(window.alert).toHaveBeenCalledWith(RETRY_FAILED));
  });

  it("sends no CSRF token when the page has no meta tag", async () => {
    document.body.innerHTML = detail("failed", `<button class="ap-retry" data-retry-url="/admin/etiquetas/PG-1"></button>`);
    document.head.innerHTML = "";
    page = initOrder(document.querySelector("[data-bo-order]"));

    document.querySelector(".ap-retry").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

    await vi.waitFor(() => expect(window.fetch).toHaveBeenCalledWith("/admin/etiquetas/PG-1", expect.objectContaining({
      headers: expect.objectContaining({ "X-CSRF-Token": "" })
    })));
  });

  it("ignores clicks that are not on a retry button", () => {
    const root = mountDetail("done");
    root.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

    expect(window.fetch).not.toHaveBeenCalled();
  });

  it("keeps the elapsed counter ticking until it is destroyed", async () => {
    vi.useFakeTimers();
    mountDetail("running", `<b data-elapsed-since="${new Date(Date.now() - 5000).toISOString()}">0s</b>`);

    await vi.advanceTimersByTimeAsync(ELAPSED_TICK_MS);
    expect(document.querySelector("[data-elapsed-since]").textContent).toBe("6s");
  });
});
