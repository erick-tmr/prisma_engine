// Product detail page (PDP) behaviour, extracted from the inline view script so
// it can be unit tested (see test/javascript/pdp.test.js). Self-contained native
// ES module loaded via `javascript_include_tag "storefront/pdp", type: "module"`
// — no importmap, no build step. Keep in sync with app/views/products/show.html.erb.

// Money is rendered the same way the server's HasMoney concern does ("R$ 0.00"),
// so the live-updated price matches every other price on the page.
export function formatPriceCents(cents) {
  return "R$ " + (cents / 100).toFixed(2);
}

// Unit price = the form's data-base-cents plus every selected pill's data-delta.
export function computeUnitPriceCents(form) {
  let cents = parseInt(form.dataset.baseCents, 10) || 0;
  form.querySelectorAll(".variant-pill.is-selected[data-delta]").forEach(function (pill) {
    cents += parseInt(pill.dataset.delta, 10) || 0;
  });
  return cents;
}

// Clamp a quantity into the 1..99 range the input declares.
export function clampQty(value) {
  const n = parseInt(value, 10);
  if (!n || n < 1) return 1;
  return n > 99 ? 99 : n;
}

// Re-render the page's [data-price] from the current selection × quantity.
export function updatePrice(form) {
  const priceEl = form.ownerDocument.querySelector("[data-price]");
  if (!priceEl) return;
  const qtyEl = form.querySelector("[data-qty]");
  const qty = qtyEl ? clampQty(qtyEl.value) : 1;
  priceEl.textContent = formatPriceCents(computeUnitPriceCents(form) * qty);
}

// Variant pill selection: clicking a pill sets the matching hidden
// `option_ids[]` field (keyed by data-variant-group), marks the pill selected
// within its group, updates the group's selected-value label, and re-prices.
export function bindVariantPills(scope) {
  scope.querySelectorAll("[data-pdp-form] [data-vpill]").forEach(function (pill) {
    pill.addEventListener("click", function () {
      const form = pill.closest("form");
      const group = CSS.escape(pill.dataset.vgroup);
      const hidden = form.querySelector('input[data-variant-group="' + group + '"]');
      if (hidden) hidden.value = pill.dataset.vopt;
      pill.parentElement.querySelectorAll("[data-vpill]").forEach(function (other) {
        other.classList.toggle("is-selected", other === pill);
      });
      const label = form.querySelector('[data-vsel="' + group + '"]');
      if (label) label.textContent = pill.dataset.vname;
      updatePrice(form);
    });
  });
}

// Quantity stepper: − / + buttons and direct edits, clamped to 1..99, with the
// − button disabled at the floor and the price kept in sync.
export function bindStepper(scope) {
  scope.querySelectorAll("[data-pdp-form]").forEach(function (form) {
    const input = form.querySelector("[data-qty]");
    if (!input) return;
    const dec = form.querySelector("[data-dec]");
    const inc = form.querySelector("[data-inc]");

    function setQty(value) {
      const qty = clampQty(value);
      input.value = qty;
      if (dec) dec.disabled = qty <= 1;
      updatePrice(form);
    }

    if (inc) inc.addEventListener("click", function () { setQty(parseInt(input.value, 10) + 1); });
    if (dec) dec.addEventListener("click", function () { setQty(parseInt(input.value, 10) - 1); });
    input.addEventListener("change", function () { setQty(input.value); });
  });
}

// Gallery thumbnails: clicking a thumb swaps the main image (and its zoom link).
export function bindGallery(scope) {
  const thumbs = scope.querySelectorAll("[data-thumb]");
  thumbs.forEach(function (thumb) {
    thumb.addEventListener("click", function () {
      const src = thumb.dataset.src;
      if (!src) return;
      thumbs.forEach(function (other) { other.classList.toggle("is-selected", other === thumb); });
      const img = scope.querySelector("[data-main-img]");
      if (img) img.setAttribute("src", src);
      const zoom = scope.querySelector("[data-main-zoom]");
      if (zoom) zoom.setAttribute("href", src);
    });
  });
}

// "termina em N dias e Hh" for the Jogo do Mês deadline, from milliseconds left.
export function countdownText(ms) {
  if (ms <= 0) return "edição encerrada";
  const days = Math.floor(ms / 86400000);
  const hours = Math.floor((ms - days * 86400000) / 3600000);
  if (days > 0) return "termina em " + days + (days === 1 ? " dia" : " dias") + " e " + hours + "h";
  return "termina em " + hours + "h";
}

// Fill the GotM countdown text. The deadline is the last moment of the edition's
// month (data-gotm-year / data-gotm-month, 1-indexed). `now` is injected so the
// computation is deterministic under test.
export function bindCountdown(scope, now) {
  scope.querySelectorAll("[data-gotm-countdown]").forEach(function (el) {
    const out = el.querySelector("[data-countdown-text]");
    if (!out) return;
    const year = parseInt(el.dataset.gotmYear, 10);
    const month = parseInt(el.dataset.gotmMonth, 10);
    const end = new Date(year, month, 0, 23, 59, 59);
    out.textContent = countdownText(end - now);
  });
}

export function initPdp(scope, now) {
  bindVariantPills(scope);
  bindStepper(scope);
  bindGallery(scope);
  bindCountdown(scope, now);
  scope.querySelectorAll("[data-pdp-form]").forEach(updatePrice);
}

/* v8 ignore start -- browser bootstrap */
if (typeof document !== "undefined") initPdp(document, new Date());
/* v8 ignore stop */
