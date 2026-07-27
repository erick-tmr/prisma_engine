export function formatPriceCents(cents) {
  return "R$ " + (cents / 100).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export function computeUnitPriceCents(form) {
  return parseInt(form.dataset.baseCents, 10) || 0;
}

export function clampQty(value) {
  const n = parseInt(value, 10);
  if (!n || n < 1) return 1;
  return n > 99 ? 99 : n;
}

export function updatePrice(form) {
  const priceEl = form.ownerDocument.querySelector("[data-price]");
  if (!priceEl) return;
  const qtyEl = form.querySelector("[data-qty]");
  const qty = qtyEl ? clampQty(qtyEl.value) : 1;
  priceEl.textContent = formatPriceCents(computeUnitPriceCents(form) * qty);
}

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
    });
  });
}

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

export function bindPedido(scope) {
  scope.querySelectorAll("[data-pdp-form]").forEach(function (form) {
    const box = form.querySelector("[data-pedido-box]");
    if (!box) return;
    const game = box.querySelector("[data-pedido-game]");
    form.addEventListener("submit", function (event) {
      if (game.value.trim() === "") {
        event.preventDefault();
        box.classList.add("is-invalid");
        game.focus();
      }
    });
    game.addEventListener("input", function () { box.classList.remove("is-invalid"); });
  });
}

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
      if (zoom) zoom.setAttribute("href", thumb.dataset.full || src);
    });
  });
}

export function countdownText(ms) {
  if (ms <= 0) return "edição encerrada";
  const days = Math.floor(ms / 86400000);
  const hours = Math.floor((ms - days * 86400000) / 3600000);
  if (days > 0) return "termina em " + days + (days === 1 ? " dia" : " dias") + " e " + hours + "h";
  return "termina em " + hours + "h";
}

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
  bindPedido(scope);
  bindGallery(scope);
  bindCountdown(scope, now);
  scope.querySelectorAll("[data-pdp-form]").forEach(updatePrice);
}

/* v8 ignore start -- browser bootstrap */
if (typeof document !== "undefined") initPdp(document, new Date());
/* v8 ignore stop */
