import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { money, createCheckout } from "../../app/javascript/storefront/checkout.js";

const DEFAULT_ADDR = {
  id: 1, default: true, selected: true, cep: "01310100", city: "São Paulo, SP",
  receiver: "Cliente", cpf: "529.982.247-25", street: "Av. Paulista, 1578",
  line1: "Bela Vista", line2: "São Paulo · SP · CEP 01310-100"
};
const OTHER_ADDR = {
  id: 2, default: false, selected: false, cep: "37500100", city: "Itajubá, MG",
  receiver: "Maria", cpf: "390.533.447-05", street: "Rua das Acácias, 45",
  line1: "Centro", line2: "Itajubá · MG · CEP 37500-100"
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
  return `<label class="checkout__addr-opt${a.selected ? " is-selected" : ""}" data-addr-opt
    data-address-id="${a.id}" data-receiver="${a.receiver}" data-cpf="${a.cpf}"
    data-street="${a.street}" data-line1="${a.line1}" data-line2="${a.line2}"
    data-default="${a.default ? "1" : "0"}" data-city="${a.city}" data-cep="${a.cep}">
    <input type="radio" name="address_id" value="${a.id}" form="checkout-form"${a.selected ? " checked" : ""}>
  </label>`;
}

let payTab, openTab, navigate;

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function submit() {
  const ev = new Event("submit", { cancelable: true });
  document.querySelector("[data-checkout-form]").dispatchEvent(ev);
  return ev;
}
function agree() {
  document.querySelector("[data-agree-confirm]").dispatchEvent(new Event("click"));
}

const MERGE_HTML = `
    <section class="checkout__merge" data-merge data-quote-url="/checkout/consolidacao">
      <label><input type="checkbox" data-merge-check></label>
      <span data-merge-savings-line hidden> Você economiza <strong data-merge-savings>–</strong> em frete.</span>
    </section>
    <div class="checkout__merge-summary" data-merge-summary hidden>
      <strong data-merge-savings>–</strong>
    </div>`;

const MERGE_QUOTE = {
  master_number: "PG-00042", service: "sedex", service_label: "SEDEX",
  combined_cents: 3500, paid_fretes_cents: 1200, delta_cents: 2300,
  subtotal_cents: 48500, amount_cents: 50800, savings_cents: 900, order_count: 2
};

function mountCheckout({ preselected = "", addresses = [DEFAULT_ADDR], popup = true, merge = false } = {}) {
  document.head.innerHTML = '<meta name="csrf-token" content="test-token">';
  document.body.innerHTML = `
    ${merge ? MERGE_HTML : ""}
    <section id="step-address">
      <div class="checkout__addr-selected">
        <span data-sel-receiver></span><span data-sel-cpf></span><span data-sel-street></span>
        <span data-sel-line1></span><span data-sel-line2></span><span data-sel-badge></span>
      </div>
      <button data-addr-change-btn type="button">Alterar</button>
      <div class="checkout__addr-note" data-addr-note>
        <textarea data-correios-obs maxlength="100"></textarea>
        <span data-note-count></span>
      </div>
      <div class="checkout__addr-list" data-addr-list>
        ${addresses.map(addrOpt).join("")}
        <button data-addr-add-btn type="button">Adicionar</button>
      </div>
      <form data-addr-form id="addr-form"><button data-addr-cancel type="button">Cancelar</button></form>
    </section>
    <section id="step-shipping">
      <span class="checkout__step-flag" data-ship-flag></span>
      <strong data-ship-dest></strong>
      <div class="checkout__ship-opts" data-ship-opts data-preselected="${preselected}" data-quote-url="/carrinho/frete"></div>
    </section>
    <section id="step-observation">
      <span class="checkout__step-flag" data-obs-flag></span>
      <textarea name="observation" form="checkout-form" data-obs-input maxlength="280"></textarea>
      <span data-obs-count></span>
      <label><input type="checkbox" data-obs-none></label>
    </section>
    <form id="checkout-form" action="/checkout" data-checkout-form>
      <input type="hidden" name="shipping_service" data-checkout-service>
      <div class="checkout__pay-error" data-pay-error><span data-pay-error-msg></span></div>
      <button type="submit" data-pay-btn>Confirmar e pagar</button>
    </form>
    <span data-subtotal data-subtotal-cents="48500"></span>
    <span class="is-pending" data-shipping>Selecione o envio</span>
    <span data-ship-method></span>
    <span data-total></span>
    <span data-mb-total></span>
    <div data-redirect></div>
    <div class="checkout__agree" data-agree-modal aria-hidden="true">
      <div class="checkout__agree-card"><button data-agree-confirm>Ir para o pagamento</button></div>
    </div>
  `;
  payTab = { location: { href: "" }, close: vi.fn() };
  openTab = vi.fn(() => (popup ? payTab : null));
  navigate = vi.fn();
  return createCheckout(document, openTab, navigate);
}

afterEach(() => { vi.restoreAllMocks(); document.body.style.overflow = ""; });

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
    expect(document.querySelector("[data-shipping]").classList.contains("is-pending")).toBe(true);
    expect(document.querySelector("[data-total]").textContent).toMatch(/485,00/);

    co.renderQuote(QUOTE);
    expect(document.querySelector("[data-shipping]").classList.contains("is-pending")).toBe(false);
    expect(document.querySelector("[data-ship-method]").textContent).toBe("· SEDEX");
    expect(document.querySelector("[data-total]").textContent).toMatch(/523,40/);
    expect(document.querySelector("[data-mb-total]").textContent).toMatch(/523,40/);
  });
});

describe("renderQuote", () => {
  it("renders eligible options (SEDEX tagged) and ineligible ones disabled with a reason", () => {
    const co = mountCheckout();
    co.renderQuote(QUOTE);
    const opts = document.querySelector("[data-ship-opts]");
    expect(opts.querySelector('[data-opt="sedex"]')).not.toBeNull();
    expect(opts.innerHTML).toContain("Mais rápido");
    expect(opts.querySelector('[data-opt="pac"]')).not.toBeNull();
    expect(opts.querySelector('[data-opt-disabled="mini_envios"]')).not.toBeNull();
    expect(opts.innerHTML).toContain("Não disponível.");
  });

  it("renders each option with its mapped Correios icon", () => {
    const co = mountCheckout();
    co.renderQuote({
      destination: { city: "São Paulo", state: "SP" },
      services: [
        { key: "sedex", label: "SEDEX", eligible: true, price_cents: 3840, business_days: 2 },
        { key: "pac", label: "PAC", eligible: true, price_cents: 2500, business_days: 7 },
        { key: "mini_envios", label: "Mini Envios", eligible: false, message: "Não disponível." },
        { key: "drone", label: "Drone", eligible: true, price_cents: 9900, business_days: 1 }
      ]
    });
    const html = document.querySelector('[data-opt="sedex"]').outerHTML;
    expect(html).toContain("checkout__ship-ic");
    expect(html).toContain("bi-lightning-charge-fill");
    expect(document.querySelector('[data-opt="pac"]').outerHTML).toContain("bi-truck");
    expect(document.querySelector('[data-opt-disabled="mini_envios"]').outerHTML).toContain("bi-envelope");
    expect(document.querySelector('[data-opt="drone"]').outerHTML).toContain("bi-box-seam");
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
    expect(document.querySelector("#step-shipping").classList.contains("is-done")).toBe(true);
    expect(document.querySelector("[data-ship-flag]").classList.contains("is-visible")).toBe(true);
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
    expect(document.querySelector("[data-sel-badge]").classList.contains("is-hidden")).toBe(false);
    expect(document.querySelector("[data-ship-dest]").textContent).toContain("CEP 01310-100");
    expect(document.querySelector('input[value="1"]').checked).toBe(true);
    expect(JSON.parse(fetchMock.mock.calls[0][1].body)).toEqual({ cep: "01310100" });
  });

  it("adopts a non-default address: hides the badge", () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => QUOTE }));
    const co = mountCheckout({ addresses: [DEFAULT_ADDR, OTHER_ADDR] });
    co.selectAddress(document.querySelector('[data-address-id="2"]'));
    expect(document.querySelector("[data-sel-badge]").classList.contains("is-hidden")).toBe(true);
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
    expect(list.classList.contains("is-open")).toBe(true);

    form.classList.add("is-open");
    btn.dispatchEvent(new Event("click"));
    expect(list.classList.contains("is-open")).toBe(false);
    expect(form.classList.contains("is-open")).toBe(false);
  });

  it("the add button opens the form and cancel closes it", () => {
    const co = mountCheckout();
    co.bindEvents();
    const form = document.querySelector("[data-addr-form]");
    document.querySelector("[data-addr-add-btn]").dispatchEvent(new Event("click"));
    expect(form.classList.contains("is-open")).toBe(true);
    document.querySelector("[data-addr-cancel]").dispatchEvent(new Event("click"));
    expect(form.classList.contains("is-open")).toBe(false);
  });

  it("clicking a saved option selects that address", () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => QUOTE }));
    const co = mountCheckout({ addresses: [DEFAULT_ADDR, OTHER_ADDR] });
    co.bindEvents();
    document.querySelector('[data-address-id="2"]').dispatchEvent(new Event("click"));
    expect(document.querySelector('input[value="2"]').checked).toBe(true);
  });

  it("agreeing after submit opens a pay tab, posts the form, and sends this tab to the return page", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ payment_url: "https://pay.example/abc", return_url: "/checkout/retorno?order_nsu=PG-1" })
    });
    vi.stubGlobal("fetch", fetchMock);
    const co = mountCheckout();
    co.bindEvents();
    document.querySelector("[data-checkout-service]").value = "pac";
    document.querySelector("[data-obs-none]").checked = true;

    const ev = submit();
    expect(ev.defaultPrevented).toBe(true);
    expect(document.querySelector("[data-agree-modal]").classList.contains("is-open")).toBe(true);
    expect(openTab).not.toHaveBeenCalled();

    agree();
    expect(openTab).toHaveBeenCalledOnce();
    expect(document.querySelector("[data-agree-modal]").classList.contains("is-open")).toBe(false);
    expect(document.querySelector("[data-redirect]").classList.contains("is-visible")).toBe(true);

    await flush();

    const [url, opts] = fetchMock.mock.calls[0];
    expect(url).toMatch(/\/checkout$/);
    expect(opts.method).toBe("POST");
    expect(opts.headers["X-CSRF-Token"]).toBe("test-token");
    expect(payTab.location.href).toBe("https://pay.example/abc");
    expect(navigate).toHaveBeenCalledWith("/checkout/retorno?order_nsu=PG-1");
  });

  it("falls back to a same-tab redirect when the pay tab is blocked", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ payment_url: "https://pay.example/abc", return_url: "/checkout/retorno?order_nsu=PG-1" })
    }));
    const co = mountCheckout({ popup: false });
    co.bindEvents();
    document.querySelector("[data-checkout-service]").value = "pac";
    document.querySelector("[data-obs-none]").checked = true;
    submit();
    agree();

    await flush();
    expect(navigate).toHaveBeenCalledWith("https://pay.example/abc");
  });

  it("shows the server error and closes the pay tab when the order is rejected", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: false,
      json: async () => ({ error: "Não foi possível iniciar o pagamento agora. Tente novamente em instantes." })
    }));
    const co = mountCheckout();
    co.bindEvents();
    document.querySelector("[data-checkout-service]").value = "pac";
    document.querySelector("[data-obs-none]").checked = true;
    submit();
    agree();

    await flush();
    expect(payTab.close).toHaveBeenCalledOnce();
    expect(document.querySelector("[data-redirect]").classList.contains("is-visible")).toBe(false);
    expect(document.querySelector("[data-pay-error]").classList.contains("is-visible")).toBe(true);
    expect(document.querySelector("[data-pay-error-msg]").textContent).toMatch(/Não foi possível iniciar o pagamento/);
    expect(navigate).not.toHaveBeenCalled();
  });

  it("shows a generic error when the request itself fails", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network down")));
    const co = mountCheckout({ popup: false });
    co.bindEvents();
    document.querySelector("[data-checkout-service]").value = "pac";
    document.querySelector("[data-obs-none]").checked = true;
    submit();
    agree();

    await flush();
    expect(payTab.close).not.toHaveBeenCalled();
    expect(document.querySelector("[data-pay-error]").classList.contains("is-visible")).toBe(true);
    expect(document.querySelector("[data-pay-error-msg]").textContent).toMatch(/Não foi possível iniciar o pagamento/);
  });

  it("ignores a second agree click while a payment is already in flight", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ payment_url: "https://pay.example/abc", return_url: "/checkout/retorno?order_nsu=PG-1" })
    });
    vi.stubGlobal("fetch", fetchMock);
    const co = mountCheckout();
    co.bindEvents();
    document.querySelector("[data-checkout-service]").value = "pac";
    document.querySelector("[data-obs-none]").checked = true;

    submit();
    agree();
    agree();

    await flush();
    expect(openTab).toHaveBeenCalledOnce();
    expect(fetchMock).toHaveBeenCalledOnce();
  });

  it("ignores a re-submit while a payment is already in flight", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ payment_url: "https://pay.example/abc", return_url: "/checkout/retorno?order_nsu=PG-1" })
    });
    vi.stubGlobal("fetch", fetchMock);
    const co = mountCheckout();
    co.bindEvents();
    document.querySelector("[data-checkout-service]").value = "pac";
    document.querySelector("[data-obs-none]").checked = true;

    submit();
    agree();
    const ev = submit();

    await flush();
    expect(ev.defaultPrevented).toBe(true);
    expect(document.querySelector("[data-agree-modal]").classList.contains("is-open")).toBe(false);
    expect(openTab).toHaveBeenCalledOnce();
    expect(fetchMock).toHaveBeenCalledOnce();
  });

  it("submitting with no service is blocked, flags the shipping step, and does not open the modal", () => {
    const co = mountCheckout();
    co.bindEvents();
    const ev = submit();
    expect(ev.defaultPrevented).toBe(true);
    expect(document.querySelector("#step-shipping").classList.contains("is-invalid")).toBe(true);
    expect(document.querySelector("[data-pay-error]").classList.contains("is-visible")).toBe(true);
    expect(document.querySelector("[data-agree-modal]").classList.contains("is-open")).toBe(false);
    expect(openTab).not.toHaveBeenCalled();
  });
});

describe("payment agreement modal", () => {
  function mountValid() {
    const co = mountCheckout();
    co.bindEvents();
    document.querySelector("[data-checkout-service]").value = "pac";
    document.querySelector("[data-obs-none]").checked = true;
    return co;
  }

  it("a valid submit opens the modal and locks the page without starting payment", () => {
    mountValid();
    submit();
    const modal = document.querySelector("[data-agree-modal]");
    expect(modal.classList.contains("is-open")).toBe(true);
    expect(modal.getAttribute("aria-hidden")).toBe("false");
    expect(document.body.style.overflow).toBe("hidden");
    expect(openTab).not.toHaveBeenCalled();
    expect(document.querySelector("[data-redirect]").classList.contains("is-visible")).toBe(false);
  });

  it("clicking the backdrop dismisses the modal and unlocks the page", () => {
    mountValid();
    submit();
    const modal = document.querySelector("[data-agree-modal]");
    modal.dispatchEvent(new Event("click"));
    expect(modal.classList.contains("is-open")).toBe(false);
    expect(modal.getAttribute("aria-hidden")).toBe("true");
    expect(document.body.style.overflow).toBe("");
  });

  it("clicking inside the card does not dismiss the modal", () => {
    mountValid();
    submit();
    const modal = document.querySelector("[data-agree-modal]");
    modal.querySelector(".checkout__agree-card").dispatchEvent(new Event("click", { bubbles: true }));
    expect(modal.classList.contains("is-open")).toBe(true);
  });

  it("Escape closes the modal when open", () => {
    mountValid();
    submit();
    const modal = document.querySelector("[data-agree-modal]");
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    expect(modal.classList.contains("is-open")).toBe(false);
  });

  it("Escape is a no-op when the modal is closed, and other keys are ignored while open", () => {
    const co = mountValid();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    expect(document.querySelector("[data-agree-modal]").classList.contains("is-open")).toBe(false);

    submit();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" }));
    expect(document.querySelector("[data-agree-modal]").classList.contains("is-open")).toBe(true);
    expect(co).toBeTruthy();
  });
});

describe("observation", () => {
  it("updates the char counter and warns near the 280 limit", () => {
    const co = mountCheckout();
    co.bindEvents();
    const input = document.querySelector("[data-obs-input]");
    input.value = "deixar na portaria";
    input.dispatchEvent(new Event("input"));
    expect(document.querySelector("[data-obs-count]").textContent).toBe("18/280");
    expect(document.querySelector("[data-obs-count]").classList.contains("is-warn")).toBe(false);

    input.value = "x".repeat(265);
    input.dispatchEvent(new Event("input"));
    expect(document.querySelector("[data-obs-count]").textContent).toBe("265/280");
    expect(document.querySelector("[data-obs-count]").classList.contains("is-warn")).toBe(true);
  });

  it("ticking 'no observation' disables + clears the textarea and confirms the step", () => {
    const co = mountCheckout();
    co.bindEvents();
    const input = document.querySelector("[data-obs-input]");
    const none = document.querySelector("[data-obs-none]");
    input.value = "algo aqui";

    none.checked = true;
    none.dispatchEvent(new Event("change"));
    expect(input.disabled).toBe(true);
    expect(input.value).toBe("");
    expect(document.querySelector("#step-observation").classList.contains("is-done")).toBe(true);
    expect(document.querySelector("[data-obs-flag]").classList.contains("is-visible")).toBe(true);

    none.checked = false;
    none.dispatchEvent(new Event("change"));
    expect(input.disabled).toBe(false);
    expect(document.querySelector("#step-observation").classList.contains("is-done")).toBe(false);
  });

  it("typing a note confirms the step without the checkbox", () => {
    const co = mountCheckout();
    co.bindEvents();
    const input = document.querySelector("[data-obs-input]");
    input.value = "entregar após as 18h";
    input.dispatchEvent(new Event("input"));
    expect(co.obsSatisfied()).toBe(true);
    expect(document.querySelector("#step-observation").classList.contains("is-done")).toBe(true);
  });

  it("blocks pay when the observation is neither written nor waived", () => {
    const co = mountCheckout();
    co.bindEvents();
    document.querySelector("[data-checkout-service]").value = "pac";
    const ev = new Event("submit", { cancelable: true });
    document.querySelector("[data-checkout-form]").dispatchEvent(ev);
    expect(ev.defaultPrevented).toBe(true);
    expect(document.querySelector("#step-observation").classList.contains("is-invalid")).toBe(true);
    expect(document.querySelector("[data-pay-error]").classList.contains("is-visible")).toBe(true);
    expect(document.querySelector("[data-pay-error-msg]").textContent).toMatch(/Escreva uma observação/);
    expect(document.querySelector("[data-agree-modal]").classList.contains("is-open")).toBe(false);
    expect(openTab).not.toHaveBeenCalled();
  });
});

describe("correios note", () => {
  it("updates the counter as the note is typed", () => {
    const co = mountCheckout();
    co.bindEvents();
    const input = document.querySelector("[data-correios-obs]");
    input.value = "entregar na portaria";
    input.dispatchEvent(new Event("input"));
    expect(document.querySelector("[data-note-count]").textContent).toBe("20/100");
    expect(document.querySelector("[data-addr-note]").classList.contains("is-invalid")).toBe(false);
  });

  it("flags the note as invalid once it passes the limit", () => {
    const co = mountCheckout();
    const input = document.querySelector("[data-correios-obs]");
    input.value = "x".repeat(101);
    co.refreshNote();
    expect(document.querySelector("[data-note-count]").textContent).toBe("101/100");
    expect(document.querySelector("[data-addr-note]").classList.contains("is-invalid")).toBe(true);
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

describe("merge orders", () => {
  const okFetch = () => vi.fn().mockResolvedValue({ ok: true, json: async () => MERGE_QUOTE });

  it("shows the savings on load without applying the merge", async () => {
    vi.stubGlobal("fetch", okFetch());
    const co = mountCheckout({ merge: true });

    await co.fetchMergeQuote();

    expect(co.mergeData).toEqual(MERGE_QUOTE);
    expect(co.merge).toBeNull();
    expect(document.querySelector("[data-merge]").classList.contains("is-merged")).toBe(false);
    expect(document.querySelector("[data-merge-savings-line]").hidden).toBe(false);
    expect(document.querySelectorAll("[data-merge-savings]")[0].textContent).toMatch(/9,00/);
  });

  it("hides the savings line when there is nothing to save", () => {
    const co = mountCheckout({ merge: true });
    co.showMergeSavings({ ...MERGE_QUOTE, savings_cents: 0 });
    expect(document.querySelector("[data-merge-savings-line]").hidden).toBe(true);
  });

  it("init fetches the quote so the savings show before checking", async () => {
    vi.stubGlobal("fetch", okFetch());
    const co = mountCheckout({ merge: true });
    co.init();
    await flush();
    expect(co.mergeData).toEqual(MERGE_QUOTE);
    expect(document.querySelector("[data-merge-savings-line]").hidden).toBe(false);
  });

  it("applyMerge overrides the total, reveals the summary, and hides shipping", () => {
    const co = mountCheckout({ merge: true, preselected: "sedex" });
    co.renderQuote(QUOTE);

    co.applyMerge(MERGE_QUOTE);

    expect(co.merge).toEqual(MERGE_QUOTE);
    expect(document.querySelector("[data-merge]").classList.contains("is-merged")).toBe(true);
    expect(document.querySelector("[data-merge-summary]").hidden).toBe(false);
    expect(document.querySelector("#step-shipping").classList.contains("is-hidden")).toBe(true);
    expect(document.querySelector("[data-shipping]").textContent).toMatch(/23,00/);
    expect(document.querySelector("[data-ship-method]").textContent).toBe("· SEDEX");
    expect(document.querySelector("[data-total]").textContent).toMatch(/508,00/);
  });

  it("clearMerge reverts to the cart-only total and re-shows shipping", () => {
    const co = mountCheckout({ merge: true });
    co.renderQuote(QUOTE);
    co.applyMerge(MERGE_QUOTE);

    co.clearMerge();

    expect(co.merge).toBeNull();
    expect(document.querySelector("[data-merge]").classList.contains("is-merged")).toBe(false);
    expect(document.querySelector("[data-merge-summary]").hidden).toBe(true);
    expect(document.querySelector("#step-shipping").classList.contains("is-hidden")).toBe(false);
    expect(document.querySelector("[data-total]").textContent).toMatch(/523,40/);
  });

  it("checking the box applies the already-fetched quote without a second request", async () => {
    const fetchMock = okFetch();
    vi.stubGlobal("fetch", fetchMock);
    const co = mountCheckout({ merge: true });
    co.bindEvents();
    await co.fetchMergeQuote();
    const afterLoad = fetchMock.mock.calls.length;

    const box = document.querySelector("[data-merge-check]");
    box.checked = true;
    box.dispatchEvent(new Event("change"));
    await flush();

    expect(co.merge).toEqual(MERGE_QUOTE);
    expect(fetchMock.mock.calls.length).toBe(afterLoad);
  });

  it("checking before the quote loads fetches then applies it", async () => {
    const fetchMock = okFetch();
    vi.stubGlobal("fetch", fetchMock);
    const co = mountCheckout({ merge: true });
    co.bindEvents();

    const box = document.querySelector("[data-merge-check]");
    box.checked = true;
    box.dispatchEvent(new Event("change"));
    await flush();

    expect(fetchMock.mock.calls[0][0]).toBe("/checkout/consolidacao");
    expect(co.merge).toEqual(MERGE_QUOTE);
  });

  it("unchecking the box clears the merge", async () => {
    vi.stubGlobal("fetch", okFetch());
    const co = mountCheckout({ merge: true });
    co.bindEvents();
    const box = document.querySelector("[data-merge-check]");

    box.checked = true; box.dispatchEvent(new Event("change")); await flush();
    box.checked = false; box.dispatchEvent(new Event("change"));

    expect(co.merge).toBeNull();
  });

  it("a failed merge quote while checked unchecks the box and shows the error", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, json: async () => ({ error: "Deu ruim." }) }));
    const co = mountCheckout({ merge: true });
    document.querySelector("[data-merge-check]").checked = true;

    await co.fetchMergeQuote();

    expect(co.merge).toBeNull();
    expect(document.querySelector("[data-merge-check]").checked).toBe(false);
    expect(document.querySelector("[data-pay-error-msg]").textContent).toBe("Deu ruim.");
  });

  it("a network error while checked surfaces a friendly message", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));
    const co = mountCheckout({ merge: true });
    document.querySelector("[data-merge-check]").checked = true;

    await co.fetchMergeQuote();

    expect(co.merge).toBeNull();
    expect(document.querySelector("[data-pay-error-msg]").textContent).toMatch(/Não foi possível juntar/);
  });

  it("validate skips the shipping requirement when merging", () => {
    const co = mountCheckout({ merge: true });
    co.applyMerge(MERGE_QUOTE);
    document.querySelector("[data-obs-none]").checked = true;
    expect(co.validate()).toBe(true);
  });
});
