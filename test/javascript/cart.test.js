import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { maskCep, money, createCartShipping } from "../../app/javascript/storefront/cart.js";

// Mirrors the data hooks in app/views/cart/show.html.erb: the frete card
// (the [data-cart-shipping] root), the summary card, and the two "Finalizar
// compra" forms ([data-finalize-form]).
function mountCart({ subtotalCents = 48500, finalizeForms = 2 } = {}) {
  const forms = Array.from({ length: finalizeForms }, () =>
    '<form data-finalize-form><button type="submit">Finalizar</button></form>'
  ).join("");

  document.head.innerHTML = '<meta name="csrf-token" content="test-token">';
  document.body.innerHTML = `
    <section data-cart-shipping data-quote-url="/carrinho/frete">
      <input data-cep>
      <button data-calc>Calcular</button>
      <div class="cep-err" data-cep-err>CEP inválido.</div>
      <div class="frete-dest" data-dest>
        Entrega para <strong data-dest-city></strong>
        <a href="#" data-dest-change>alterar</a>
      </div>
      <div class="ship-opts" data-ship-opts></div>
    </section>
    <div class="sum-body">
      <span data-subtotal data-subtotal-cents="${subtotalCents}">R$ 485,00</span>
      <span data-ship-method></span>
      <span data-shipping>a calcular</span>
      <span data-total>R$ 485,00</span>
    </div>
    <span data-mb-total>R$ 485,00</span>
    ${forms}
  `;
  return document.querySelector("[data-cart-shipping]");
}

const QUOTE = {
  destination: { city: "São Paulo", state: "SP" },
  services: [
    { key: "sedex", label: "SEDEX", eligible: true, price_cents: 3840, business_days: 2 },
    { key: "pac", label: "PAC", eligible: true, price_cents: 2500, business_days: 7 },
    { key: "mini_envios", label: "Mini Envios", eligible: false, message: "Não disponível para este pedido." },
  ],
};

describe("pure helpers", () => {
  it("maskCep keeps ≤5 digits unmasked and hyphenates after the 5th", () => {
    expect(maskCep("123")).toBe("123");
    expect(maskCep("12345")).toBe("12345");
    expect(maskCep("123456")).toBe("12345-6");
    expect(maskCep("01310100")).toBe("01310-100");
  });

  it("maskCep strips non-digits and caps at 8 digits", () => {
    expect(maskCep("01310-100999")).toBe("01310-100");
    expect(maskCep("ab12cd34")).toBe("1234");
  });

  it("money formats integer cents as pt-BR BRL", () => {
    expect(money(2500)).toMatch(/^R\$\s25,00$/);
    expect(money(0)).toMatch(/^R\$\s0,00$/);
  });
});

describe("createCartShipping", () => {
  let root;
  let cart;

  beforeEach(() => {
    root = mountCart();
    cart = createCartShipping(root);
  });

  it("clearCepError / showCepError toggle the error classes", () => {
    cart.showCepError("Correios indisponível.");
    const input = root.querySelector("[data-cep]");
    const err = root.querySelector("[data-cep-err]");
    expect(input.classList.contains("err")).toBe(true);
    expect(err.classList.contains("show")).toBe(true);
    expect(err.textContent).toBe("Correios indisponível.");

    cart.clearCepError();
    expect(input.classList.contains("err")).toBe(false);
    expect(err.classList.contains("show")).toBe(false);
  });

  it("renderSummary shows 'a calcular' with no selection and adds frete once selected", () => {
    cart.renderSummary();
    expect(document.querySelector("[data-shipping]").textContent).toBe("a calcular");
    expect(document.querySelector("[data-total]").textContent).toMatch(/485,00/);

    cart.renderQuote(QUOTE); // auto-selects PAC (2500) → 48500 + 2500 = 51000
    expect(document.querySelector("[data-ship-method]").textContent).toBe("· PAC");
    expect(document.querySelector("[data-total]").textContent).toMatch(/510,00/);
    expect(document.querySelector("[data-mb-total]").textContent).toMatch(/510,00/);
  });

  it("renderQuote renders eligible + ineligible options, the destination, and auto-selects PAC", () => {
    cart.renderQuote(QUOTE);
    const opts = root.querySelector("[data-ship-opts]");
    expect(root.querySelector("[data-dest-city]").textContent).toBe("São Paulo, SP");
    expect(opts.querySelectorAll("label.ship-opt[data-opt]").length).toBe(2);
    expect(opts.querySelector('[data-opt-disabled="mini_envios"]')).not.toBeNull();
    expect(opts.querySelector('[data-opt="pac"]').classList.contains("sel")).toBe(true);
    expect(cart.shipping.method).toBe("pac");
  });

  // Regression for the cart fix: a successful quote must clear a stale error.
  it("renderQuote clears a stale CEP error on a successful retry", () => {
    cart.showCepError("Correios indisponível. Tente novamente em instantes.");
    cart.renderQuote(QUOTE);
    expect(root.querySelector("[data-cep]").classList.contains("err")).toBe(false);
    expect(root.querySelector("[data-cep-err]").classList.contains("show")).toBe(false);
  });

  // Regression for the checkout carry-over: the chosen service is stashed on
  // every Finalizar form so cart#finalize can persist it.
  it("selecting a service stashes shipping_service into every finalize form", () => {
    cart.renderQuote(QUOTE); // auto-selects PAC
    const stash = () =>
      Array.from(document.querySelectorAll('[data-finalize-form] input[name="shipping_service"]'))
        .map((i) => i.value);
    expect(stash()).toEqual(["pac", "pac"]);

    root.querySelector('[data-opt="sedex"]').click();
    expect(stash()).toEqual(["sedex", "sedex"]);
  });

  it("rememberShipping reuses the hidden input and removes it on null", () => {
    cart.rememberShipping("sedex");
    cart.rememberShipping("pac");
    const forms = document.querySelectorAll("[data-finalize-form]");
    forms.forEach((form) => {
      expect(form.querySelectorAll('input[name="shipping_service"]').length).toBe(1);
      expect(form.querySelector('input[name="shipping_service"]').value).toBe("pac");
    });

    cart.rememberShipping(null);
    expect(document.querySelectorAll('[data-finalize-form] input[name="shipping_service"]').length).toBe(0);
  });

  describe("fetchQuote", () => {
    afterEach(() => { vi.restoreAllMocks(); });

    it("posts to data-quote-url with the CSRF token and renders the quote", async () => {
      const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => QUOTE });
      vi.stubGlobal("fetch", fetchMock);

      await cart.fetchQuote("01310100");

      expect(fetchMock).toHaveBeenCalledOnce();
      const [url, opts] = fetchMock.mock.calls[0];
      expect(url).toBe("/carrinho/frete");
      expect(opts.headers["X-CSRF-Token"]).toBe("test-token");
      expect(JSON.parse(opts.body)).toEqual({ cep: "01310100" });
      expect(root.querySelector("[data-ship-opts]").querySelectorAll("[data-opt]").length).toBe(2);
    });

    it("shows the server error message on a non-ok response", async () => {
      const fetchMock = vi.fn().mockResolvedValue({
        ok: false,
        json: async () => ({ error: "Correios indisponível. Tente novamente em instantes." }),
      });
      vi.stubGlobal("fetch", fetchMock);

      await cart.fetchQuote("01310100");

      const err = root.querySelector("[data-cep-err]");
      expect(err.classList.contains("show")).toBe(true);
      expect(err.textContent).toBe("Correios indisponível. Tente novamente em instantes.");
    });
  });
});
