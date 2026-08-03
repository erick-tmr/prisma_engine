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

export function initClient(root) {
  const table = createTable(root);
  initShell(root);
  bindConfirm(root);
  bindFlashDismiss(root);
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
