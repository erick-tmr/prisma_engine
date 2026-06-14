const BRL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const INSTALLMENTS = 12;

export function money(cents) {
  return BRL.format(cents / 100);
}

export function createCheckout(doc, openTab, navigate) {
  const shipOpts = doc.querySelector("[data-ship-opts]");
  const quoteUrl = shipOpts.dataset.quoteUrl;
  const preselected = shipOpts.dataset.preselected;
  const serviceInput = doc.querySelector("[data-checkout-service]");
  const checkoutForm = doc.querySelector("[data-checkout-form]");
  const payError = doc.querySelector("[data-pay-error]");
  const shipStep = doc.querySelector("#step-shipping");
  const shipFlag = doc.querySelector("[data-ship-flag]");
  const shipDest = doc.querySelector("[data-ship-dest]");
  const overlay = doc.querySelector("[data-redirect]");
  /* v8 ignore next */
  const subtotal = parseInt(doc.querySelector("[data-subtotal]")?.dataset.subtotalCents || "0", 10);
  let shipping = null;
  let submitting = false;

  function renderSummary() {
    const total = subtotal + (shipping ? shipping.price : 0);
    const shipEl = doc.querySelector("[data-shipping]");
    const methodEl = doc.querySelector("[data-ship-method]");
    if (shipping) {
      shipEl.textContent = money(shipping.price);
      shipEl.classList.remove("pending");
      methodEl.textContent = "· " + shipping.label;
    } else {
      shipEl.textContent = "Selecione o envio";
      shipEl.classList.add("pending");
      methodEl.textContent = "";
    }
    doc.querySelector("[data-total]").textContent = money(total);
    doc.querySelector("[data-mb-total]").textContent = money(total);
    doc.querySelector("[data-installment]").textContent = money(Math.round(total / INSTALLMENTS));
  }

  function selectShip(el, services) {
    shipOpts.querySelectorAll(".ship-opt").forEach(function (o) { o.classList.remove("sel"); });
    el.classList.add("sel");
    const s = services.find(function (x) { return String(x.key) === el.dataset.opt; });
    shipping = { method: s.key, label: s.label, price: s.price_cents };
    serviceInput.value = s.key;
    shipStep.classList.remove("invalid");
    shipStep.classList.add("step-done");
    shipFlag.style.display = "inline-flex";
    payError.classList.remove("show");
    renderSummary();
  }

  function renderQuote(data) {
    shipOpts.innerHTML = data.services.map(function (s) {
      if (s.eligible) {
        const fast = s.key === "sedex" ? '<span class="tag">Mais rápido</span>' : "";
        return '<label class="ship-opt" data-opt="' + s.key + '">'
          + '<span class="ship-radio"></span>'
          + '<span class="ship-info">'
          +   '<span class="ship-name">' + s.label + fast + "</span>"
          +   '<span class="ship-eta"><i class="bi bi-clock"></i> Entrega em ' + s.business_days + " dias úteis</span>"
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
    shipping = null;
    serviceInput.value = "";
    shipOpts.querySelectorAll("[data-opt]").forEach(function (el) {
      el.addEventListener("click", function () { selectShip(el, data.services); });
    });
    const def = shipOpts.querySelector('[data-opt="' + preselected + '"]') || shipOpts.querySelector("[data-opt]");
    if (def) selectShip(def, data.services);
    else renderSummary();
  }

  function showShipError(msg) {
    shipOpts.innerHTML = '<p class="ship-error"><i class="bi bi-exclamation-circle-fill"></i> ' + msg + "</p>";
    shipping = null;
    serviceInput.value = "";
    renderSummary();
  }

  async function fetchQuote(digits) {
    const token = doc.querySelector('meta[name="csrf-token"]').content;
    try {
      const res = await fetch(quoteUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": token },
        body: JSON.stringify({ cep: digits })
      });
      const data = await res.json();
      if (res.ok) renderQuote(data);
      else showShipError(data.error);
    } catch (e) {
      showShipError("Não foi possível calcular o frete. Tente novamente.");
    }
  }

  function fillSelected(opt) {
    const set = function (sel, val) { doc.querySelector(sel).textContent = val; };
    set("[data-sel-receiver]", opt.dataset.receiver);
    set("[data-sel-cpf]", opt.dataset.cpf);
    set("[data-sel-street]", opt.dataset.street);
    set("[data-sel-line1]", opt.dataset.line1);
    set("[data-sel-line2]", opt.dataset.line2);
    doc.querySelector("[data-sel-badge]").style.display = opt.dataset.default === "1" ? "inline-flex" : "none";
    shipDest.textContent = opt.dataset.city + " · CEP " + opt.dataset.cep.replace(/(\d{5})(\d{3})/, "$1-$2");
  }

  function selectAddress(opt) {
    doc.querySelectorAll("[data-addr-opt]").forEach(function (o) { o.classList.remove("sel"); });
    opt.classList.add("sel");
    opt.querySelector('input[name="address_id"]').checked = true;
    fillSelected(opt);
    doc.querySelector("[data-addr-list]").classList.remove("open");
    doc.querySelector("[data-addr-form]").classList.remove("open");
    doc.querySelector("#step-address").classList.add("step-done");
    fetchQuote(opt.dataset.cep);
  }

  function failPayment(payTab, message) {
    if (payTab) payTab.close();
    submitting = false;
    overlay.classList.remove("show");
    doc.querySelector("[data-pay-error-msg]").textContent = message;
    payError.classList.add("show");
  }

  async function startPayment(payTab) {
    const token = doc.querySelector('meta[name="csrf-token"]').content;
    try {
      const res = await fetch(checkoutForm.action, {
        method: "POST",
        headers: { "Accept": "application/json", "X-CSRF-Token": token },
        body: new FormData(checkoutForm)
      });
      const data = await res.json();
      if (!res.ok) {
        failPayment(payTab, data.error);
        return;
      }
      if (payTab) {
        payTab.location.href = data.payment_url;
        navigate(data.return_url);
      } else {
        navigate(data.payment_url);
      }
    } catch (e) {
      failPayment(payTab, "Não foi possível iniciar o pagamento. Tente novamente.");
    }
  }

  function bindEvents() {
    const addrList = doc.querySelector("[data-addr-list]");
    const addrForm = doc.querySelector("[data-addr-form]");

    doc.querySelector("[data-addr-change-btn]").addEventListener("click", function () {
      if (!addrList.classList.toggle("open")) addrForm.classList.remove("open");
    });
    doc.querySelectorAll("[data-addr-opt]").forEach(function (opt) {
      opt.addEventListener("click", function () { selectAddress(opt); });
    });
    doc.querySelector("[data-addr-add-btn]").addEventListener("click", function () {
      addrForm.classList.toggle("open");
    });
    doc.querySelector("[data-addr-cancel]").addEventListener("click", function () {
      addrForm.classList.remove("open");
    });

    checkoutForm.addEventListener("submit", function (e) {
      e.preventDefault();
      if (submitting) return;
      if (!serviceInput.value) {
        shipStep.classList.add("invalid");
        shipStep.classList.remove("step-done");
        payError.classList.add("show");
        shipStep.scrollIntoView({ block: "center", behavior: "smooth" });
        return;
      }
      submitting = true;
      const payTab = openTab();
      overlay.classList.add("show");
      startPayment(payTab);
    });
  }

  function init() {
    bindEvents();
    const selected = doc.querySelector("[data-addr-opt].sel") || doc.querySelector("[data-addr-opt]");
    if (selected) fetchQuote(selected.dataset.cep);
    else renderSummary();
  }

  return {
    renderSummary, selectShip, renderQuote, showShipError, fetchQuote,
    fillSelected, selectAddress, bindEvents, init,
    get shipping() { return shipping; }
  };
}

/* v8 ignore start */
if (typeof document !== "undefined" && document.querySelector("[data-ship-opts]")) {
  createCheckout(
    document,
    () => window.open("", "_blank"),
    (url) => { window.location.href = url; }
  ).init();
}
/* v8 ignore stop */
