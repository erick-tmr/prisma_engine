import { createTable } from "backoffice/table";
import { bindConfirm, bindFlashDismiss, initShell } from "backoffice/shell";

const SECOND = 1000;
const MINUTE = 60 * SECOND;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

export function remaining(expiresAt, now) {
  const left = Math.max(0, expiresAt - now);
  return {
    days: Math.floor(left / DAY),
    hours: Math.floor((left % DAY) / HOUR),
    minutes: Math.floor((left % HOUR) / MINUTE),
    seconds: Math.floor((left % MINUTE) / SECOND)
  };
}

export function elapsedPercent(startedAt, expiresAt, now) {
  const span = expiresAt - startedAt;
  if (span <= 0) return 100;

  return Math.min(100, Math.max(2, ((now - startedAt) / span) * 100));
}

export function paintClock(clock, bar, now) {
  const startedAt = Date.parse(clock.dataset.startedAt);
  const expiresAt = Date.parse(clock.dataset.expiresAt);
  const left = remaining(expiresAt, now);

  Object.entries(left).forEach(([ unit, value ]) => {
    const slot = clock.querySelector(`[data-clock-value="${unit}"]`);
    if (slot) slot.textContent = String(value).padStart(2, "0");
  });
  if (bar) bar.style.width = `${elapsedPercent(startedAt, expiresAt, now).toFixed(1)}%`;

  return expiresAt - now > 0;
}

export function startClock(root) {
  const clock = root.querySelector("[data-strike-clock]");
  if (!clock) return null;

  const bar = root.querySelector("[data-strike-bar]");
  let timer = null;
  const stop = () => clearInterval(timer);
  const tick = () => {
    if (!paintClock(clock, bar, Date.now())) stop();
  };

  timer = setInterval(tick, SECOND);
  tick();
  return stop;
}

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const AREA_DIGITS = 2;
const LANDLINE_DIGITS = 10;
const MOBILE_DIGITS = 11;

const digitsOf = (value) => value.replace(/\D/g, "");

export function maskPhone(raw) {
  const digits = digitsOf(raw).slice(0, MOBILE_DIGITS);
  const area = digits.slice(0, AREA_DIGITS);
  const rest = digits.slice(AREA_DIGITS);
  if (!rest) return digits && `(${area}`;

  const split = digits.length === MOBILE_DIGITS ? 5 : 4;
  if (rest.length <= split) return `(${area}) ${rest}`;

  return `(${area}) ${rest.slice(0, split)}-${rest.slice(split)}`;
}

const CONTACT_FIELDS = {
  email: {
    normalize: (value) => value.trim().toLowerCase(),
    valid: (value) => EMAIL.test(value.trim())
  },
  phone: {
    normalize: digitsOf,
    valid: (value) => digitsOf(value).length >= LANDLINE_DIGITS
  }
};

export function bindContactEdit(root) {
  const card = root.querySelector("[data-contact]");
  if (!card) return;

  const form = card.querySelector("[data-contact-form]");
  const view = card.querySelector("[data-contact-view]");
  const edit = card.querySelector("[data-contact-edit]");
  const save = form.querySelector("[data-contact-save]");
  const inputs = [ ...form.querySelectorAll("[data-contact-input]") ];
  const fieldOf = (input) => CONTACT_FIELDS[input.dataset.contactInput];

  const setError = (input, message = "") => {
    input.classList.toggle("bad", Boolean(message));
    form.querySelector(`[data-contact-error="${input.dataset.contactInput}"]`).textContent = message;
  };
  const changed = (input) => fieldOf(input).normalize(input.value) !== fieldOf(input).normalize(input.dataset.original);
  const sync = () => { save.disabled = !inputs.some(changed); };
  const toggle = (editing) => {
    form.hidden = !editing;
    view.hidden = editing;
    edit.hidden = editing;
  };
  const cancel = () => {
    inputs.forEach((input) => {
      input.value = input.dataset.original;
      setError(input);
    });
    toggle(false);
    edit.focus();
  };

  edit.addEventListener("click", () => {
    toggle(true);
    sync();
    inputs[0].focus();
    inputs[0].select();
  });
  form.querySelector("[data-contact-cancel]").addEventListener("click", cancel);
  form.addEventListener("keydown", (event) => {
    if (event.key === "Escape") cancel();
  });
  form.addEventListener("input", (event) => {
    const input = event.target;
    if (input.dataset.contactInput === "phone") input.value = maskPhone(input.value);
    setError(input);
    sync();
  });
  form.addEventListener("submit", (event) => {
    const invalid = inputs.filter((input) => !fieldOf(input).valid(input.value));
    invalid.forEach((input) => setError(input, input.dataset.invalidMessage));
    if (!invalid.length) return;

    event.preventDefault();
    invalid[0].focus();
  });
  sync();
}

export function initClient(root) {
  const table = createTable(root);
  initShell(root);
  bindConfirm(root);
  bindFlashDismiss(root);
  bindContactEdit(root);
  const stopClock = startClock(root);

  root.addEventListener("click", (event) => {
    const row = event.target.closest("tr[data-order]");
    const link = row?.querySelector("a.cell-link");
    if (link && link !== event.target) link.click();
  });

  return {
    table,
    destroy() {
      if (stopClock) stopClock();
      table.destroy();
    }
  };
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector('[data-list="client"]');
  if (root) initClient(root);
}
/* v8 ignore stop */
