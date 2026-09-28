import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { COPIED_MS, bindReturnFreight } from "../../../app/javascript/backoffice/return_freight.js";

const PRICES = {
  sedex: { price_cents: 3270, price_formatted: "R$ 32,70" },
  pac: { price_cents: 2140, price_formatted: "R$ 21,40" },
  mini_envios: null
};

// Mirrors app/views/admin/orders/_status_card, _return_payer and _return_freight_card.
function mount({ customer = false } = {}) {
  document.body.innerHTML = `
    <div data-bo-order>
      <form data-return-form data-quote-url="/admin/pedidos/PG-1/devolucao/cotacao">
        <select data-return-service>
          <option value="sedex">SEDEX</option>
          <option value="pac" selected>PAC</option>
          <option value="mini_envios">Mini Envios</option>
        </select>
        <input type="radio" name="payer" value="store" data-return-payer="store" ${customer ? "" : "checked"}>
        <input type="radio" name="payer" value="customer" data-return-payer="customer" ${customer ? "checked" : ""}>
        <b data-return-quote-price data-loading="Cotando…" data-unavailable="Cotação indisponível">–</b>
        <textarea name="reason"></textarea>
      </form>
      <div class="fc-link">
        <span data-copy-source> https://example.com/minha-conta/pedidos/PG-1 </span>
        <button type="button" data-copy-link data-copied-label="Copiado"><i></i> <span data-copy-text>Copiar</span></button>
      </div>
      <select id="outside"><option>x</option></select>
    </div>`;
  return document.querySelector("[data-bo-order]");
}

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 502, json: () => Promise.resolve(body) });
}

function change(el) {
  el.dispatchEvent(new window.Event("change", { bubbles: true }));
}

function pick(root, payer) {
  const input = root.querySelector(`[data-return-payer="${payer}"]`);
  input.checked = true;
  change(input);
}

const price = () => document.querySelector("[data-return-quote-price]");
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("bindReturnFreight quote", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("does not quote while the store pays", async () => {
    const fetchFn = vi.fn(() => jsonResponse(PRICES));
    const root = mount();
    bindReturnFreight(root, { fetchFn });

    change(root.querySelector("[data-return-service]"));
    await settle();

    expect(fetchFn).not.toHaveBeenCalled();
    expect(price().textContent).toBe("–");
  });

  it("quotes once when the customer pays and follows the service picker", async () => {
    const fetchFn = vi.fn(() => jsonResponse(PRICES));
    const root = mount();
    bindReturnFreight(root, { fetchFn });

    pick(root, "customer");
    expect(price().textContent).toBe("Cotando…");
    await settle();
    expect(price().textContent).toBe("R$ 21,40");

    const service = root.querySelector("[data-return-service]");
    service.value = "sedex";
    change(service);
    await settle();

    expect(price().textContent).toBe("R$ 32,70");
    expect(fetchFn).toHaveBeenCalledTimes(1);
    expect(fetchFn).toHaveBeenCalledWith("/admin/pedidos/PG-1/devolucao/cotacao", { headers: { Accept: "application/json" } });
  });

  it("says a service Correios will not carry is unavailable", async () => {
    const root = mount({ customer: true });
    const service = root.querySelector("[data-return-service]");
    service.value = "mini_envios";
    bindReturnFreight(root, { fetchFn: () => jsonResponse(PRICES) });
    await settle();

    expect(price().textContent).toBe("Cotação indisponível");
    expect(price().classList.contains("is-unavailable")).toBe(true);

    service.value = "pac";
    change(service);
    expect(price().classList.contains("is-unavailable")).toBe(false);
    await settle();
    expect(price().textContent).toBe("R$ 21,40");
  });

  it("retries the quote after Correios failed", async () => {
    const fetchFn = vi.fn()
      .mockReturnValueOnce(jsonResponse({}, false))
      .mockReturnValueOnce(jsonResponse(PRICES));
    const root = mount({ customer: true });
    bindReturnFreight(root, { fetchFn });
    await settle();

    expect(price().textContent).toBe("Cotação indisponível");

    pick(root, "customer");
    await settle();

    expect(price().textContent).toBe("R$ 21,40");
    expect(fetchFn).toHaveBeenCalledTimes(2);
  });

  it("ignores changes that are not the payer or the service", async () => {
    const fetchFn = vi.fn(() => jsonResponse(PRICES));
    const root = mount({ customer: true });
    bindReturnFreight(root, { fetchFn });
    await settle();

    change(root.querySelector("textarea"));
    change(root.querySelector("#outside"));
    await settle();

    expect(fetchFn).toHaveBeenCalledTimes(1);
  });

  it("uses the page fetch by default", async () => {
    const fetchFn = vi.fn(() => jsonResponse(PRICES));
    vi.stubGlobal("fetch", fetchFn);
    bindReturnFreight(mount({ customer: true }));
    await settle();

    expect(fetchFn).toHaveBeenCalledTimes(1);
    expect(price().textContent).toBe("R$ 21,40");
  });
});

describe("bindReturnFreight copy link", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("copies the charge link and flashes a confirmation", async () => {
    const clipboard = { writeText: vi.fn(() => Promise.resolve()) };
    const root = mount();
    bindReturnFreight(root, { fetchFn: vi.fn(), clipboard });
    const button = root.querySelector("[data-copy-link]");

    button.querySelector("i").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    await vi.waitFor(() => expect(button.classList.contains("is-copied")).toBe(true));

    expect(clipboard.writeText).toHaveBeenCalledWith("https://example.com/minha-conta/pedidos/PG-1");
    expect(button.querySelector("[data-copy-text]").textContent).toBe("Copiado");

    vi.advanceTimersByTime(COPIED_MS);
    expect(button.classList.contains("is-copied")).toBe(false);
    expect(button.querySelector("[data-copy-text]").textContent).toBe("Copiar");
  });

  it("still flashes when the browser offers no clipboard", async () => {
    vi.stubGlobal("navigator", {});
    const root = mount();
    bindReturnFreight(root, { fetchFn: vi.fn() });
    const button = root.querySelector("[data-copy-link]");

    button.click();
    await vi.waitFor(() => expect(button.classList.contains("is-copied")).toBe(true));
  });

  it("ignores clicks elsewhere", () => {
    const clipboard = { writeText: vi.fn(() => Promise.resolve()) };
    const root = mount();
    bindReturnFreight(root, { fetchFn: vi.fn(), clipboard });

    root.querySelector("#outside").click();

    expect(clipboard.writeText).not.toHaveBeenCalled();
  });
});
