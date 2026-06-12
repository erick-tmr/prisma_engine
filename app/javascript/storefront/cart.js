// Cart page behaviour, extracted from the inline view script so it can be unit
// tested (see test/javascript/cart.test.js). Shipped as a self-contained native
// ES module via `javascript_include_tag "storefront/cart", type: "module"` —
// no importmap, no build step. The browser runs the guarded auto-init at the
// bottom; tests import the named functions and drive them against a jsdom
// fixture. Keep this in sync with app/views/cart/show.html.erb's data hooks.

const BRL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

// ── Pure helpers ───────────────────────────────────────────────────────────

export function maskCep(value) {
  const digits = value.replace(/\D/g, "").slice(0, 8);
  return digits.length > 5 ? digits.slice(0, 5) + "-" + digits.slice(5) : digits;
}

export function money(cents) {
  return BRL.format(cents / 100);
}

// ── Cart line interactions (variant pills + quantity stepper) ───────────────

export function bindCartLines(scope) {
  scope.querySelectorAll(".cart-item").forEach(function (item) {
    item.querySelector("[data-edit-toggle]")?.addEventListener("click", function () {
      item.classList.toggle("editing");
    });

    const variantForm = item.querySelector("[data-variant-form]");
    if (variantForm) {
      variantForm.querySelectorAll(".vpill").forEach(function (pill) {
        pill.addEventListener("click", function () {
          const hidden = variantForm.querySelector(
            'input[data-variant-group="' + CSS.escape(pill.dataset.vgroup) + '"]'
          );
          if (hidden) hidden.value = pill.dataset.vopt;
          pill.parentElement.querySelectorAll(".vpill").forEach(function (p) {
            p.classList.toggle("sel", p === pill);
          });
          variantForm.requestSubmit();
        });
      });
    }

    const stepperForm = item.querySelector("[data-stepper-form]");
    if (stepperForm) {
      const input = stepperForm.querySelector("[data-qty]");
      const dec = stepperForm.querySelector("[data-dec]");
      const inc = stepperForm.querySelector("[data-inc]");
      const clamp = function (n) { return Math.max(1, Math.min(99, n)); };
      dec?.addEventListener("click", function () {
        if (dec.disabled) return;
        input.value = clamp(parseInt(input.value, 10) - 1);
        stepperForm.requestSubmit();
      });
      inc?.addEventListener("click", function () {
        input.value = clamp(parseInt(input.value, 10) + 1);
        stepperForm.requestSubmit();
      });
      input.addEventListener("change", function () {
        input.value = clamp(parseInt(input.value, 10) || 1);
        stepperForm.requestSubmit();
      });
    }
  });
}

// ── CEP shipping calculator ─────────────────────────────────────────────────

// Builds the live Correios frete calculator bound to a frete-card `root`
// (which carries data-quote-url). The summary and "Finalizar compra" forms
// live in sibling cards, so they're resolved from the owner document.
export function createCartShipping(root) {
  const doc = root.ownerDocument;
  const cepInput = root.querySelector("[data-cep]");
  const cepErr = root.querySelector("[data-cep-err]");
  const destBox = root.querySelector("[data-dest]");
  const destCity = root.querySelector("[data-dest-city]");
  const shipOpts = root.querySelector("[data-ship-opts]");
  const calcBtn = root.querySelector("[data-calc]");
  const quoteUrl = root.dataset.quoteUrl;
  /* v8 ignore next -- [data-subtotal] is always server-rendered; the "0" guards an impossible nil */
  const subtotal = parseInt(doc.querySelector("[data-subtotal]")?.dataset.subtotalCents || "0", 10);
  let shipping = null;

  function clearCepError() {
    cepInput.classList.remove("err");
    cepErr.classList.remove("show");
  }

  function showCepError(msg) {
    cepInput.classList.add("err");
    cepErr.textContent = msg;
    cepErr.classList.add("show");
    shipOpts.classList.remove("show");
    destBox.classList.remove("show");
  }

  function renderSummary() {
    const total = subtotal + (shipping ? shipping.price : 0);
    const shipEl = doc.querySelector("[data-shipping]");
    const methodEl = doc.querySelector("[data-ship-method]");
    if (shipping) {
      shipEl.textContent = money(shipping.price);
      shipEl.style.color = "var(--pg-ink)";
      shipEl.style.fontWeight = "600";
      methodEl.textContent = "· " + shipping.label;
    } else {
      shipEl.textContent = "a calcular";
      shipEl.style.color = "var(--pg-muted)";
      shipEl.style.fontWeight = "500";
      methodEl.textContent = "";
    }
    doc.querySelector("[data-total]").textContent = money(total);
    const mbTotalEl = doc.querySelector("[data-mb-total]");
    if (mbTotalEl) mbTotalEl.textContent = money(total);
  }

  // Carry the chosen frete into the checkout step: stash the selected service
  // on the "Finalizar compra" forms so cart#finalize remembers it in the
  // session and the checkout screen pre-selects the same option. Passing null
  // removes it (a fresh quote deselects everything first).
  function rememberShipping(serviceKey) {
    doc.querySelectorAll("[data-finalize-form]").forEach(function (form) {
      let input = form.querySelector('input[name="shipping_service"]');
      if (!serviceKey) {
        if (input) input.remove();
        return;
      }
      if (!input) {
        input = doc.createElement("input");
        input.type = "hidden";
        input.name = "shipping_service";
        form.appendChild(input);
      }
      input.value = serviceKey;
    });
  }

  function selectShip(el, services) {
    shipOpts.querySelectorAll(".ship-opt").forEach(function (o) { o.classList.remove("sel"); });
    el.classList.add("sel");
    const s = services.find(function (x) { return String(x.key) === el.dataset.opt; });
    shipping = { method: s.key, label: s.label, price: s.price_cents };
    rememberShipping(s.key);
    renderSummary();
  }

  function renderQuote(data) {
    // A successful quote clears any prior error (e.g. a retry after the
    // Correios API was briefly unavailable) — the input handler only clears it
    // on keystroke, so re-calculating the same CEP wouldn't otherwise.
    clearCepError();
    destCity.textContent = data.destination.city + ", " + data.destination.state;
    destBox.classList.add("show");
    shipOpts.innerHTML = data.services.map(function (s) {
      if (s.eligible) {
        const fast = s.key === "sedex" ? '<span class="tag">Mais rápido</span>' : "";
        return '<label class="ship-opt" data-opt="' + s.key + '">'
          + '<span class="ship-radio"></span>'
          + '<span class="ship-info">'
          +   '<span class="ship-name">' + s.label + fast + "</span>"
          +   '<span class="ship-eta"><i class="bi bi-clock" style="font-size:11px"></i> Entrega em ' + s.business_days + " dias úteis</span>"
          + "</span>"
          + '<span class="ship-price">' + money(s.price_cents) + "</span>"
          + "</label>";
      }
      return '<div class="ship-opt disabled" data-opt-disabled="' + s.key + '">'
        + '<span class="ship-radio"></span>'
        + '<span class="ship-info">'
        +   '<span class="ship-name">' + s.label + "</span>"
        +   '<span class="ship-eta">' + s.message + "</span>"
        + "</span>"
        + "</div>";
    }).join("");
    shipOpts.classList.add("show");
    shipping = null;
    rememberShipping(null);
    shipOpts.querySelectorAll("[data-opt]").forEach(function (el) {
      el.addEventListener("click", function () { selectShip(el, data.services); });
    });
    const def = shipOpts.querySelector('[data-opt="pac"]')
      || shipOpts.querySelector('[data-opt="sedex"]')
      || shipOpts.querySelector("[data-opt]");
    if (def) selectShip(def, data.services);
    else renderSummary();
  }

  async function fetchQuote(digits) {
    const token = doc.querySelector('meta[name="csrf-token"]')?.content;
    calcBtn.disabled = true;
    try {
      const res = await fetch(quoteUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": token || ""
        },
        body: JSON.stringify({ cep: digits })
      });
      const data = await res.json();
      if (!res.ok) {
        showCepError(data.error || "Erro ao calcular frete.");
        return;
      }
      renderQuote(data);
    } catch (e) {
      showCepError("Não foi possível calcular o frete. Tente novamente.");
    } finally {
      calcBtn.disabled = false;
    }
  }

  function bindEvents() {
    cepInput?.addEventListener("input", function (e) {
      e.target.value = maskCep(e.target.value);
      clearCepError();
    });
    calcBtn?.addEventListener("click", function () {
      const digits = (cepInput.value || "").replace(/\D/g, "");
      if (digits.length !== 8) {
        showCepError("CEP inválido. Digite os 8 números.");
        return;
      }
      fetchQuote(digits);
    });
    cepInput?.addEventListener("keydown", function (e) {
      if (e.key === "Enter") calcBtn.click();
    });
    destBox.querySelector("[data-dest-change]")?.addEventListener("click", function (e) {
      e.preventDefault();
      cepInput.focus();
      cepInput.select();
    });
  }

  return {
    clearCepError, showCepError, renderSummary, rememberShipping,
    selectShip, renderQuote, fetchQuote, bindEvents,
    get shipping() { return shipping; }
  };
}

// ── Browser auto-init (inert under a test import: no [data-cart-shipping]) ───
// Bootstrap glue — excluded from coverage (the exported functions above carry
// the logic and are unit-tested directly).

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-cart-shipping]");
  if (root) createCartShipping(root).bindEvents();
  bindCartLines(document);
}
/* v8 ignore stop */
