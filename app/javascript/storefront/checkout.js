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
  const agreeModal = doc.querySelector("[data-agree-modal]");
  const agreeBtn = doc.querySelector("[data-agree-confirm]");
  const obsInput = doc.querySelector("[data-obs-input]");
  const obsCount = doc.querySelector("[data-obs-count]");
  const obsNone = doc.querySelector("[data-obs-none]");
  const obsStep = doc.querySelector("#step-observation");
  const obsFlag = doc.querySelector("[data-obs-flag]");
  /* v8 ignore next */
  const subtotal = parseInt(doc.querySelector("[data-subtotal]")?.dataset.subtotalCents || "0", 10);
  const mergeCard = doc.querySelector("[data-merge]");
  const mergeCheck = doc.querySelector("[data-merge-check]");
  const mergeSummary = doc.querySelector("[data-merge-summary]");
  let shipping = null;
  let merge = null;
  let mergeData = null;
  let submitting = false;

  function renderSummary() {
    const shipEl = doc.querySelector("[data-shipping]");
    const methodEl = doc.querySelector("[data-ship-method]");
    let total;
    if (merge) {
      total = merge.amount_cents;
      shipEl.textContent = money(merge.delta_cents);
      shipEl.classList.remove("is-pending");
      methodEl.textContent = "· " + merge.service_label;
    } else if (shipping) {
      total = subtotal + shipping.price;
      shipEl.textContent = money(shipping.price);
      shipEl.classList.remove("is-pending");
      methodEl.textContent = "· " + shipping.label;
    } else {
      total = subtotal;
      shipEl.textContent = "Selecione o envio";
      shipEl.classList.add("is-pending");
      methodEl.textContent = "";
    }
    doc.querySelector("[data-total]").textContent = money(total);
    doc.querySelector("[data-mb-total]").textContent = money(total);
    doc.querySelector("[data-installment]").textContent = money(Math.round(total / INSTALLMENTS));
  }

  function selectShip(el, services) {
    shipOpts.querySelectorAll("[data-ship-opt]").forEach(function (o) { o.classList.remove("is-selected"); });
    el.classList.add("is-selected");
    const s = services.find(function (x) { return String(x.key) === el.dataset.opt; });
    shipping = { method: s.key, label: s.label, price: s.price_cents };
    serviceInput.value = s.key;
    shipStep.classList.remove("is-invalid");
    shipStep.classList.add("is-done");
    shipFlag.classList.add("is-visible");
    payError.classList.remove("is-visible");
    renderSummary();
  }

  function renderQuote(data) {
    shipOpts.innerHTML = data.services.map(function (s) {
      if (s.eligible) {
        const fast = s.key === "sedex" ? '<span class="checkout__ship-tag">Mais rápido</span>' : "";
        return '<label class="checkout__ship-opt" data-ship-opt data-opt="' + s.key + '">'
          + '<span class="checkout__ship-radio"></span>'
          + '<span class="checkout__ship-info">'
          +   '<span class="checkout__ship-name">' + s.label + fast + "</span>"
          +   '<span class="checkout__ship-eta"><i class="bi bi-clock"></i> Entrega em ' + s.business_days + " dias úteis</span>"
          + "</span>"
          + '<span class="checkout__ship-price">' + money(s.price_cents) + "</span>"
          + "</label>";
      }
      return '<div class="checkout__ship-opt is-disabled" data-ship-opt data-opt-disabled="' + s.key + '">'
        + '<span class="checkout__ship-radio"></span>'
        + '<span class="checkout__ship-info">'
        +   '<span class="checkout__ship-name">' + s.label + "</span>"
        +   '<span class="checkout__ship-eta">' + s.message + "</span>"
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
    shipOpts.innerHTML = '<p class="checkout__ship-error"><i class="bi bi-exclamation-circle-fill"></i> ' + msg + "</p>";
    shipping = null;
    serviceInput.value = "";
    renderSummary();
  }

  function showMergeSavings(data) {
    doc.querySelectorAll("[data-merge-savings]").forEach(function (el) { el.textContent = money(data.savings_cents); });
    doc.querySelector("[data-merge-savings-line]").hidden = data.savings_cents <= 0;
  }

  function applyMerge(data) {
    merge = data;
    mergeCard.classList.add("is-merged");
    if (mergeSummary) mergeSummary.hidden = false;
    shipStep.classList.add("is-hidden");
    payError.classList.remove("is-visible");
    renderSummary();
  }

  function clearMerge() {
    merge = null;
    if (mergeCard) mergeCard.classList.remove("is-merged");
    if (mergeSummary) mergeSummary.hidden = true;
    shipStep.classList.remove("is-hidden");
    renderSummary();
  }

  function failMerge(message) {
    mergeCheck.checked = false;
    clearMerge();
    doc.querySelector("[data-pay-error-msg]").textContent = message;
    payError.classList.add("is-visible");
  }

  async function fetchMergeQuote() {
    const token = doc.querySelector('meta[name="csrf-token"]').content;
    try {
      const res = await fetch(mergeCard.dataset.quoteUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": token },
        body: "{}"
      });
      const data = await res.json();
      if (res.ok) {
        mergeData = data;
        showMergeSavings(data);
        if (mergeCheck.checked) applyMerge(data);
      } else if (mergeCheck.checked) {
        failMerge(data.error);
      }
    } catch (e) {
      if (mergeCheck.checked) failMerge("Não foi possível juntar os pedidos agora. Tente novamente.");
    }
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
    doc.querySelector("[data-sel-badge]").classList.toggle("is-hidden", opt.dataset.default !== "1");
    shipDest.textContent = opt.dataset.city + " · CEP " + opt.dataset.cep.replace(/(\d{5})(\d{3})/, "$1-$2");
  }

  function selectAddress(opt) {
    doc.querySelectorAll("[data-addr-opt]").forEach(function (o) { o.classList.remove("is-selected"); });
    opt.classList.add("is-selected");
    opt.querySelector('input[name="address_id"]').checked = true;
    fillSelected(opt);
    doc.querySelector("[data-addr-list]").classList.remove("is-open");
    doc.querySelector("[data-addr-form]").classList.remove("is-open");
    doc.querySelector("#step-address").classList.add("is-done");
    fetchQuote(opt.dataset.cep);
  }

  function failPayment(payTab, message) {
    if (payTab) payTab.close();
    submitting = false;
    overlay.classList.remove("is-visible");
    doc.querySelector("[data-pay-error-msg]").textContent = message;
    payError.classList.add("is-visible");
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

  function obsSatisfied() {
    return obsNone.checked || obsInput.value.trim().length > 0;
  }

  function validate() {
    if (!merge && !serviceInput.value) {
      shipStep.classList.add("is-invalid");
      shipStep.classList.remove("is-done");
      doc.querySelector("[data-pay-error-msg]").textContent = "Escolha uma forma de envio antes de pagar.";
      payError.classList.add("is-visible");
      shipStep.scrollIntoView({ block: "center", behavior: "smooth" });
      return false;
    }
    if (!obsSatisfied()) {
      obsStep.classList.add("is-invalid");
      obsStep.classList.remove("is-done");
      doc.querySelector("[data-pay-error-msg]").textContent = "Escreva uma observação ou marque que não tem nenhuma.";
      payError.classList.add("is-visible");
      obsStep.scrollIntoView({ block: "center", behavior: "smooth" });
      return false;
    }
    return true;
  }

  function openAgreement() {
    agreeModal.classList.add("is-open");
    agreeModal.setAttribute("aria-hidden", "false");
    doc.body.style.overflow = "hidden";
    agreeBtn.focus();
  }

  function closeAgreement() {
    agreeModal.classList.remove("is-open");
    agreeModal.setAttribute("aria-hidden", "true");
    doc.body.style.overflow = "";
  }

  function beginPayment() {
    if (submitting) return;
    submitting = true;
    closeAgreement();
    const payTab = openTab();
    overlay.classList.add("is-visible");
    startPayment(payTab);
  }

  function refreshObs() {
    obsInput.disabled = obsNone.checked;
    const n = obsInput.value.length;
    const max = obsInput.maxLength;
    obsCount.textContent = n + "/" + max;
    obsCount.classList.toggle("is-warn", n >= max - 20);
    if (obsSatisfied()) {
      obsStep.classList.remove("is-invalid");
      obsStep.classList.add("is-done");
      obsFlag.classList.add("is-visible");
      payError.classList.remove("is-visible");
    } else {
      obsStep.classList.remove("is-done");
      obsFlag.classList.remove("is-visible");
    }
  }

  function bindEvents() {
    const addrList = doc.querySelector("[data-addr-list]");
    const addrForm = doc.querySelector("[data-addr-form]");

    doc.querySelector("[data-addr-change-btn]").addEventListener("click", function () {
      if (!addrList.classList.toggle("is-open")) addrForm.classList.remove("is-open");
    });
    doc.querySelectorAll("[data-addr-opt]").forEach(function (opt) {
      opt.addEventListener("click", function () { selectAddress(opt); });
    });
    doc.querySelector("[data-addr-add-btn]").addEventListener("click", function () {
      addrForm.classList.toggle("is-open");
    });
    doc.querySelector("[data-addr-cancel]").addEventListener("click", function () {
      addrForm.classList.remove("is-open");
    });

    obsInput.addEventListener("input", refreshObs);
    obsNone.addEventListener("change", function () {
      if (obsNone.checked) obsInput.value = "";
      refreshObs();
    });

    checkoutForm.addEventListener("submit", function (e) {
      e.preventDefault();
      if (submitting) return;
      if (validate()) openAgreement();
    });

    agreeBtn.addEventListener("click", beginPayment);
    agreeModal.addEventListener("click", function (e) {
      if (e.target === agreeModal) closeAgreement();
    });
    doc.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && agreeModal.classList.contains("is-open")) closeAgreement();
    });
    if (mergeCheck) {
      mergeCheck.addEventListener("change", function () {
        if (!mergeCheck.checked) clearMerge();
        else if (mergeData) applyMerge(mergeData);
        else fetchMergeQuote();
      });
    }
  }

  function init() {
    bindEvents();
    refreshObs();
    if (mergeCheck) fetchMergeQuote();
    const selected = doc.querySelector("[data-addr-opt].is-selected") || doc.querySelector("[data-addr-opt]");
    if (selected) fetchQuote(selected.dataset.cep);
    else renderSummary();
  }

  return {
    renderSummary, selectShip, renderQuote, showShipError, fetchQuote,
    fillSelected, selectAddress, obsSatisfied, refreshObs,
    validate, openAgreement, closeAgreement, beginPayment, bindEvents, init,
    applyMerge, clearMerge, failMerge, fetchMergeQuote, showMergeSavings,
    get shipping() { return shipping; },
    get merge() { return merge; },
    get mergeData() { return mergeData; }
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
