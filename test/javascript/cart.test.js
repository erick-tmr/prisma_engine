import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { maskCep, money, createCartShipping, bindCartLines } from "../../app/javascript/storefront/cart.js";

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

  it("renderQuote with no eligible option selects nothing and leaves the summary uncalculated", () => {
    cart.renderQuote({
      destination: { city: "Itajubá", state: "MG" },
      services: [
        { key: "sedex", label: "SEDEX", eligible: false, message: "Não atendido." },
        { key: "pac", label: "PAC", eligible: false, message: "Não atendido." },
      ],
    });
    expect(root.querySelectorAll("[data-opt]").length).toBe(0);
    expect(cart.shipping).toBeNull();
    expect(document.querySelector("[data-shipping]").textContent).toBe("a calcular");
  });

  describe("bindEvents", () => {
    beforeEach(() => { cart.bindEvents(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it("masks the CEP and clears any error as you type", () => {
      const input = root.querySelector("[data-cep]");
      cart.showCepError("CEP inválido.");
      input.value = "01310100";
      input.dispatchEvent(new window.Event("input", { bubbles: true }));
      expect(input.value).toBe("01310-100");
      expect(root.querySelector("[data-cep-err]").classList.contains("show")).toBe(false);
    });

    it("rejects a short CEP on Calcular without calling the server", () => {
      const fetchMock = vi.fn();
      vi.stubGlobal("fetch", fetchMock);
      root.querySelector("[data-cep]").value = "123";
      root.querySelector("[data-calc]").dispatchEvent(new window.Event("click", { bubbles: true }));
      expect(fetchMock).not.toHaveBeenCalled();
      expect(root.querySelector("[data-cep-err]").textContent).toBe("CEP inválido. Digite os 8 números.");
    });

    it("rejects an empty CEP on Calcular", () => {
      const fetchMock = vi.fn();
      vi.stubGlobal("fetch", fetchMock);
      root.querySelector("[data-cep]").value = "";
      root.querySelector("[data-calc]").dispatchEvent(new window.Event("click", { bubbles: true }));
      expect(fetchMock).not.toHaveBeenCalled();
    });

    it("quotes a valid CEP on Calcular", () => {
      const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => QUOTE });
      vi.stubGlobal("fetch", fetchMock);
      root.querySelector("[data-cep]").value = "01310-100";
      root.querySelector("[data-calc]").dispatchEvent(new window.Event("click", { bubbles: true }));
      expect(fetchMock).toHaveBeenCalledOnce();
    });

    it("Enter on the CEP field fires Calcular", () => {
      const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => QUOTE });
      vi.stubGlobal("fetch", fetchMock);
      const input = root.querySelector("[data-cep]");
      input.value = "01310-100";
      input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
      expect(fetchMock).toHaveBeenCalledOnce();
    });

    it("focuses the CEP field when 'alterar' is clicked", () => {
      const input = root.querySelector("[data-cep]");
      root.querySelector("[data-dest-change]").dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
      expect(document.activeElement).toBe(input);
    });
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

    it("shows a generic error when the request throws", async () => {
      vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network down")));
      await cart.fetchQuote("01310100");
      expect(root.querySelector("[data-cep-err]").textContent).toBe(
        "Não foi possível calcular o frete. Tente novamente."
      );
    });

    it("falls back to a generic message when the error response carries none", async () => {
      vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, json: async () => ({}) }));
      await cart.fetchQuote("01310100");
      expect(root.querySelector("[data-cep-err]").textContent).toBe("Erro ao calcular frete.");
    });

    it("sends an empty CSRF header when no token meta is present", async () => {
      document.head.innerHTML = "";
      const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => QUOTE });
      vi.stubGlobal("fetch", fetchMock);
      await cart.fetchQuote("01310100");
      expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("");
    });
  });

  describe("restore", () => {
    it("renders a cached quote and re-selects the remembered service", () => {
      cart.restore(QUOTE, "sedex");
      expect(root.querySelector('[data-opt="sedex"]').classList.contains("sel")).toBe(true);
      expect(cart.shipping.method).toBe("sedex");
    });

    it("keeps the default selection when the remembered service is no longer offered", () => {
      cart.restore(QUOTE, "mini_envios");
      expect(cart.shipping.method).toBe("pac");
    });

    it("renders without forcing a selection when no service is remembered", () => {
      cart.restore(QUOTE, "");
      expect(cart.shipping.method).toBe("pac");
    });
  });
});

describe("bindCartLines", () => {
  let submit;

  beforeEach(() => {
    submit = vi.spyOn(window.HTMLFormElement.prototype, "requestSubmit").mockImplementation(() => {});
    document.body.innerHTML = `
      <div class="cart-item">
        <button data-edit-toggle></button>
        <form data-variant-form>
          <input type="hidden" data-variant-group="lang" value="">
          <button class="vpill" data-vgroup="lang" data-vopt="pt"></button>
          <button class="vpill sel" data-vgroup="lang" data-vopt="en"></button>
        </form>
        <form data-stepper-form>
          <input data-qty value="2">
          <button data-dec></button>
          <button data-inc></button>
        </form>
      </div>`;
    bindCartLines(document);
  });

  afterEach(() => { vi.restoreAllMocks(); });

  it("toggles the edit state", () => {
    const item = document.querySelector(".cart-item");
    document.querySelector("[data-edit-toggle]").dispatchEvent(new window.Event("click", { bubbles: true }));
    expect(item.classList.contains("editing")).toBe(true);
  });

  it("selecting a variant pill updates the hidden input and submits", () => {
    document.querySelector('.vpill[data-vopt="pt"]').dispatchEvent(new window.Event("click", { bubbles: true }));
    expect(document.querySelector('input[data-variant-group="lang"]').value).toBe("pt");
    expect(document.querySelector('.vpill[data-vopt="pt"]').classList.contains("sel")).toBe(true);
    expect(document.querySelector('.vpill[data-vopt="en"]').classList.contains("sel")).toBe(false);
    expect(submit).toHaveBeenCalled();
  });

  it("the stepper clamps to 1..99 and submits on each change", () => {
    const qty = document.querySelector("[data-qty]");
    document.querySelector("[data-inc]").dispatchEvent(new window.Event("click", { bubbles: true }));
    expect(qty.value).toBe("3");
    qty.value = "1";
    document.querySelector("[data-dec]").dispatchEvent(new window.Event("click", { bubbles: true }));
    expect(qty.value).toBe("1"); // clamped, not 0
    qty.value = "500";
    qty.dispatchEvent(new window.Event("change", { bubbles: true }));
    expect(qty.value).toBe("99"); // clamped down
    expect(submit).toHaveBeenCalled();
  });

  it("a disabled decrement button does nothing", () => {
    const qty = document.querySelector("[data-qty]");
    const dec = document.querySelector("[data-dec]");
    dec.disabled = true;
    qty.value = "5";
    dec.dispatchEvent(new window.Event("click", { bubbles: true }));
    expect(qty.value).toBe("5");
  });

  it("a non-numeric quantity falls back to 1", () => {
    const qty = document.querySelector("[data-qty]");
    qty.value = "abc";
    qty.dispatchEvent(new window.Event("change", { bubbles: true }));
    expect(qty.value).toBe("1");
  });
});
