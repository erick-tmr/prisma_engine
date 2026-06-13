import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { money, createCheckout } from "../../app/javascript/storefront/checkout.js";

// Mirrors the data hooks in app/views/checkout/show.html.erb: the address step
// (saved-address radios + add-form), the shipping step ([data-ship-opts]), the
// hidden checkout form, the summary rail, the mobile bar, and the overlay.
const DEFAULT_ADDR = {
  id: 1, default: true, selected: true, cep: "01310100", city: "São Paulo, SP",
  receiver: "Cliente", cpf: "529.982.247-25", street: "Av. Paulista, 1578",
  line1: "Bela Vista", line2: "São Paulo — SP · CEP 01310-100"
};
const OTHER_ADDR = {
  id: 2, default: false, selected: false, cep: "37500100", city: "Itajubá, MG",
  receiver: "Maria", cpf: "390.533.447-05", street: "Rua das Acácias, 45",
  line1: "Centro", line2: "Itajubá — MG · CEP 37500-100"
};

const QUOTE = {
  destination: { city: "São Paulo", state: "SP" },
  services: [
    { key: "sedex", label: "SEDEX", eligible: true, price_cents: 3840, business_days: 2 },
    { key: "pac", label: "PAC", eligible: true, price_cents: 2500, business_days: 7 },
    { key: "mini_envios", label: "Mini Envios", eligible: false, message: "Não disponível." }
  ]
};
const ALL_INELIGIBLE = {
  destination: { city: "São Paulo", state: "SP" },
  services: [ { key: "sedex", label: "SEDEX", eligible: false, message: "Não disponível." } ]
};

function addrOpt(a) {
  return `<label class="addr-opt${a.selected ? " sel" : ""}" data-addr-opt
    data-address-id="${a.id}" data-receiver="${a.receiver}" data-cpf="${a.cpf}"
    data-street="${a.street}" data-line1="${a.line1}" data-line2="${a.line2}"
    data-default="${a.default ? "1" : "0"}" data-city="${a.city}" data-cep="${a.cep}">
    <input type="radio" name="address_id" value="${a.id}" form="checkout-form"${a.selected ? " checked" : ""}>
  </label>`;
}

function mountCheckout({ preselected = "", addresses = [DEFAULT_ADDR] } = {}) {
  document.head.innerHTML = '<meta name="csrf-token" content="test-token">';
  document.body.innerHTML = `
    <section id="step-address">
      <div class="addr-selected">
        <span data-sel-receiver></span><span data-sel-cpf></span><span data-sel-street></span>
        <span data-sel-line1></span><span data-sel-line2></span><span data-sel-badge></span>
      </div>
      <button data-addr-change-btn type="button">Alterar</button>
      <div class="addr-list" data-addr-list>
        ${addresses.map(addrOpt).join("")}
        <button data-addr-add-btn type="button">Adicionar</button>
      </div>
      <form data-addr-form id="addr-form"><button data-addr-cancel type="button">Cancelar</button></form>
    </section>
    <section id="step-shipping">
      <span class="step-flag" data-ship-flag style="display:none"></span>
      <strong data-ship-dest></strong>
      <div class="ship-opts" data-ship-opts data-preselected="${preselected}" data-quote-url="/carrinho/frete"></div>
    </section>
    <form id="checkout-form" data-checkout-form>
      <input type="hidden" name="shipping_service" data-checkout-service>
      <div class="pay-error" data-pay-error></div>
      <button type="submit" data-pay-btn>Confirmar e pagar</button>
    </form>
    <span data-subtotal data-subtotal-cents="48500"></span>
    <span class="pending" data-shipping>Selecione o envio</span>
    <span data-ship-method></span>
    <span data-total></span>
    <span data-mb-total></span>
    <span data-installment></span>
    <div data-redirect></div>
  `;
  return createCheckout(document);
}

afterEach(() => { vi.restoreAllMocks(); });

describe("money", () => {
  it("formats integer cents as pt-BR BRL", () => {
    expect(money(2500)).toMatch(/^R\$\s25,00$/);
    expect(money(0)).toMatch(/^R\$\s0,00$/);
  });
});

describe("renderSummary", () => {
  it("shows the placeholder with no service and folds frete into the total once chosen", () => {
    const co = mountCheckout();
    co.renderSummary();
    expect(document.querySelector("[data-shipping]").textContent).toBe("Selecione o envio");
    expect(document.querySelector("[data-shipping]").classList.contains("pending")).toBe(true);
    expect(document.querySelector("[data-total]").textContent).toMatch(/485,00/);

    co.renderQuote(QUOTE); // auto-selects the first eligible (SEDEX, 3840)
    expect(document.querySelector("[data-shipping]").classList.contains("pending")).toBe(false);
    expect(document.querySelector("[data-ship-method]").textContent).toBe("· SEDEX");
    expect(document.querySelector("[data-total]").textContent).toMatch(/523,40/); // 485 + 38,40
    expect(document.querySelector("[data-mb-total]").textContent).toMatch(/523,40/);
    expect(document.querySelector("[data-installment]").textContent).toMatch(/43,62/); // 52340/12
  });
});

describe("renderQuote", () => {
  it("renders eligible options (SEDEX tagged) and ineligible ones disabled with a reason", () => {
    const co = mountCheckout();
    co.renderQuote(QUOTE);
    const opts = document.querySelector("[data-ship-opts]");
    expect(opts.querySelector('[data-opt="sedex"]')).not.toBeNull();
    expect(opts.innerHTML).toContain("Mais rápido");        // sedex fast tag
    expect(opts.querySelector('[data-opt="pac"]')).not.toBeNull();
    expect(opts.querySelector('[data-opt-disabled="mini_envios"]')).not.toBeNull();
    expect(opts.innerHTML).toContain("Não disponível.");    // ineligible message
  });

  it("auto-selects the cart's preselected service when present", () => {
    const co = mountCheckout({ preselected: "pac" });
    co.renderQuote(QUOTE);
    expect(co.shipping.method).toBe("pac");
    expect(document.querySelector("[data-checkout-service]").value).toBe("pac");
  });

  it("falls back to the first eligible service when nothing is preselected", () => {
    const co = mountCheckout({ preselected: "" });
    co.renderQuote(QUOTE);
    expect(co.shipping.method).toBe("sedex");
  });

  it("selects nothing when no service is eligible", () => {
    const co = mountCheckout({ preselected: "pac" });
    co.renderQuote(ALL_INELIGIBLE);
    expect(co.shipping).toBeNull();
    expect(document.querySelector("[data-checkout-service]").value).toBe("");
    expect(document.querySelector("[data-shipping]").textContent).toBe("Selecione o envio");
  });

  it("clicking an option selects it and marks the step done", () => {
    const co = mountCheckout({ preselected: "sedex" });
    co.renderQuote(QUOTE);
    document.querySelector('[data-opt="pac"]').dispatchEvent(new Event("click"));
    expect(co.shipping.method).toBe("pac");
    expect(document.querySelector("#step-shipping").classList.contains("step-done")).toBe(true);
    expect(document.querySelector("[data-ship-flag]").style.display).toBe("inline-flex");
  });
});

describe("fetchQuote", () => {
  it("posts to data-quote-url with the CSRF token then renders the quote", async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => QUOTE });
    vi.stubGlobal("fetch", fetchMock);
    const co = mountCheckout();

    await co.fetchQuote("01310100");

    const [url, opts] = fetchMock.mock.calls[0];
    expect(url).toBe("/carrinho/frete");
    expect(opts.headers["X-CSRF-Token"]).toBe("test-token");
    expect(JSON.parse(opts.body)).toEqual({ cep: "01310100" });
    expect(document.querySelector('[data-opt="sedex"]')).not.toBeNull();
  });

  it("shows the server error message on a non-ok response", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, json: async () => ({ error: "CEP inválido." }) }));
    const co = mountCheckout();
    await co.fetchQuote("00000000");
    expect(document.querySelector("[data-ship-opts]").textContent).toContain("CEP inválido.");
    expect(co.shipping).toBeNull();
  });

  it("shows a generic message when the request throws", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network down")));
    const co = mountCheckout();
    await co.fetchQuote("01310100");
    expect(document.querySelector("[data-ship-opts]").textContent).toMatch(/Não foi possível calcular o frete/);
  });
});

describe("selectAddress", () => {
  it("adopts a default address: fills the card, shows the badge, re-quotes its CEP", () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => QUOTE });
    vi.stubGlobal("fetch", fetchMock);
    const co = mountCheckout({ addresses: [DEFAULT_ADDR, OTHER_ADDR] });

    co.selectAddress(document.querySelector('[data-address-id="1"]'));

    expect(document.querySelector("[data-sel-receiver]").textContent).toBe("Cliente");
    expect(document.querySelector("[data-sel-badge]").style.display).toBe("inline-flex");
    expect(document.querySelector("[data-ship-dest]").textContent).toContain("CEP 01310-100");
    expect(document.querySelector('input[value="1"]').checked).toBe(true);
    expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({ cep: "01310100" });
  });

  it("adopts a non-default address: hides the badge", () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => QUOTE }));
    const co = mountCheckout({ addresses: [DEFAULT_ADDR, OTHER_ADDR] });
    co.selectAddress(document.querySelector('[data-address-id="2"]'));
    expect(document.querySelector("[data-sel-badge]").style.display).toBe("none");
  });
});

describe("bindEvents", () => {
  it("the change button opens the saved list, and closing it also closes the add form", () => {
    const co = mountCheckout();
    co.bindEvents();
    const list = document.querySelector("[data-addr-list]");
    const form = document.querySelector("[data-addr-form]");
    const btn = document.querySelector("[data-addr-change-btn]");

    btn.dispatchEvent(new Event("click"));
    expect(list.classList.contains("open")).toBe(true);

    form.classList.add("open");
    btn.dispatchEvent(new Event("click")); // toggles closed → also closes the form
    expect(list.classList.contains("open")).toBe(false);
    expect(form.classList.contains("open")).toBe(false);
  });

  it("the add button opens the form and cancel closes it", () => {
    const co = mountCheckout();
    co.bindEvents();
    const form = document.querySelector("[data-addr-form]");
    document.querySelector("[data-addr-add-btn]").dispatchEvent(new Event("click"));
    expect(form.classList.contains("open")).toBe(true);
    document.querySelector("[data-addr-cancel]").dispatchEvent(new Event("click"));
    expect(form.classList.contains("open")).toBe(false);
  });

  it("clicking a saved option selects that address", () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => QUOTE }));
    const co = mountCheckout({ addresses: [DEFAULT_ADDR, OTHER_ADDR] });
    co.bindEvents();
    document.querySelector('[data-address-id="2"]').dispatchEvent(new Event("click"));
    expect(document.querySelector('input[value="2"]').checked).toBe(true);
  });

  it("submitting with a service shows the overlay and lets the form post", () => {
    const co = mountCheckout();
    co.bindEvents();
    document.querySelector("[data-checkout-service]").value = "pac";
    const ev = new Event("submit", { cancelable: true });
    document.querySelector("[data-checkout-form]").dispatchEvent(ev);
    expect(ev.defaultPrevented).toBe(false);
    expect(document.querySelector("[data-redirect]").classList.contains("show")).toBe(true);
  });

  it("submitting with no service is blocked and flags the shipping step", () => {
    const co = mountCheckout();
    co.bindEvents();
    const ev = new Event("submit", { cancelable: true });
    document.querySelector("[data-checkout-form]").dispatchEvent(ev);
    expect(ev.defaultPrevented).toBe(true);
    expect(document.querySelector("#step-shipping").classList.contains("invalid")).toBe(true);
    expect(document.querySelector("[data-pay-error]").classList.contains("show")).toBe(true);
  });
});

describe("init", () => {
  it("re-quotes the pre-selected address on load", () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => QUOTE });
    vi.stubGlobal("fetch", fetchMock);
    const co = mountCheckout();
    co.init();
    expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({ cep: "01310100" });
  });

  it("just renders the summary when there is no saved address", () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const co = mountCheckout({ addresses: [] });
    co.init();
    expect(fetchMock).not.toHaveBeenCalled();
    expect(document.querySelector("[data-total]").textContent).toMatch(/485,00/);
  });
});
