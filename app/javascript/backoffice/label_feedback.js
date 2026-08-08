import { buildUrl, swapParts } from "backoffice/table";

export const POLL_STEPS = [ 3_000, 3_000, 5_000, 5_000, 8_000, 10_000 ];
export const POLL_MAX_MS = 20 * 60_000;

export function nextDelay(tick) {
  return POLL_STEPS[Math.min(tick, POLL_STEPS.length - 1)];
}

export function cellStates(root) {
  return Array.from(root.querySelectorAll("[data-cor-state]")).map((cell) => cell.dataset.corState);
}

export function inFlight(root) {
  if (cellStates(root).some((state) => state === "queued" || state === "running")) return true;
  const procbar = root.querySelector('[data-part="procbar"]');
  return Number(procbar?.dataset.inFlight) > 0;
}

export function applyBusyRows(root) {
  root.querySelectorAll("[data-cor-state]").forEach((cell) => {
    const row = cell.closest("tr");
    if (!row) return;

    const busy = cell.dataset.corState === "queued" || cell.dataset.corState === "running";
    row.classList.toggle("is-busy", busy);
    const box = row.querySelector("[data-check]");
    if (box) box.setAttribute("aria-disabled", String(busy));
  });
}

// The status pill swaps as its own part, but the `data-status` the bulk bar
// reads lives on the <tr>, which no swap ever replaces. Carry it up.
export function applyRowStatus(root) {
  root.querySelectorAll("[data-row-status]").forEach((cell) => {
    const row = cell.closest("tr");
    if (row) row.dataset.status = cell.dataset.rowStatus;
  });
}

export function applyProgress(root) {
  const procbar = root.querySelector('[data-part="procbar"]');
  const fill = procbar?.querySelector(".pb-fill");
  if (fill) fill.style.width = `${Number(procbar.dataset.percent) || 0}%`;
}

export function createLabelFeedback(root, { path, params = () => ({}), onSwap, now = () => Date.now() } = {}) {
  let timer = null;
  let tick = 0;
  let startedAt = null;

  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(poll, nextDelay(tick));
  }

  async function poll() {
    if (startedAt === null) return;
    if (now() - startedAt > POLL_MAX_MS) return stop();
    if (root.classList.contains("is-loading")) return schedule();

    try {
      const response = await fetch(buildUrl(path, params()), { headers: { "X-Requested-With": "fetch" } });
      swapParts(root, await response.text());
    } catch (e) {
      /* a dropped tick is harmless: the next one re-reads the same state */
    } finally {
      applyRowStatus(root);
      applyBusyRows(root);
      applyProgress(root);
      if (onSwap) onSwap();
      tick += 1;
      if (startedAt !== null && inFlight(root)) schedule();
      else if (startedAt !== null) stop();
    }
  }

  function start() {
    tick = 0;
    if (startedAt === null) startedAt = now();
    schedule();
  }

  function stop() {
    clearTimeout(timer);
    timer = null;
    startedAt = null;
  }

  const onVisibility = () => {
    if (document.visibilityState === "hidden") clearTimeout(timer);
    else if (startedAt !== null) schedule();
  };
  document.addEventListener("visibilitychange", onVisibility);

  return {
    start,
    stop,
    poll,
    get running() { return startedAt !== null; },
    destroy() {
      stop();
      document.removeEventListener("visibilitychange", onVisibility);
    }
  };
}
