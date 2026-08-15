import { createTable } from "backoffice/table";
import { bindFilters, syncFilters } from "backoffice/filters";
import { initShell } from "backoffice/shell";
import { applyBusyRows, applyProgress, applyRowStatus, createLabelFeedback, inFlight } from "backoffice/label_feedback";
import { addMonths, anchorMonth, applyPreset, datePopHtml, nextSelection, parseISO, toISO } from "backoffice/date_picker";

export const CANCELLABLE_STATUSES = [
  "awaiting_payment", "payment_confirmed", "awaiting_components",
  "in_production", "production_issue", "label_issued", "returned"
];

export const ACTIONS = [
  { id: "to_components", icon: "bi-box-seam", from: [ "payment_confirmed" ] },
  { id: "issue_label", icon: "bi-upc-scan", from: [ "in_production" ] },
  { id: "flag_issue", icon: "bi-exclamation-triangle", from: [ "in_production" ] },
  { id: "cancel", icon: "bi-x-circle", danger: true, from: CANCELLABLE_STATUSES }
];

export const ACTION_LABELS = {
  to_components: "Aguardar componentes", issue_label: "Emitir etiqueta Correios",
  flag_issue: "Marcar problema", cancel: "Cancelar"
};

export const PRINTABLE_LABEL_STATUSES = new Set([ "label_issued" ]);

export const BULK_THROTTLE_MS = 60_000;

export const BATCH_KEY = "pg_label_batch_v1";
// How long "Lote concluído" stays up after the last label settles.
export const BATCH_HOLD_MS = 120_000;
// A batch older than this is abandoned, not in progress. Comfortably past the
// poller's own 20-minute ceiling, so it only catches batches nothing finished.
export const BATCH_TTL_MS = 30 * 60_000;
export const RETRY_FAILED = "Não foi possível reenviar para os Correios. Tente novamente.";

export function readBatch(storage, now = Date.now()) {
  try {
    const stored = JSON.parse(storage.getItem(BATCH_KEY));
    if (!stored || now - stored.at > BATCH_TTL_MS) return new Set();

    return new Set(stored.numbers);
  } catch (e) {
    return new Set();
  }
}

export function writeBatch(storage, batch, now = Date.now()) {
  try {
    storage.setItem(BATCH_KEY, JSON.stringify({ numbers: [ ...batch ], at: now }));
  } catch (e) {
    /* a full or unavailable sessionStorage only costs the batch strip */
  }
}

export function readSettledAt(storage) {
  try {
    return JSON.parse(storage.getItem(BATCH_KEY))?.settledAt ?? null;
  } catch (e) {
    return null;
  }
}

export function stampSettled(storage, at) {
  try {
    const stored = JSON.parse(storage.getItem(BATCH_KEY));
    if (stored && stored.settledAt !== at) {
      storage.setItem(BATCH_KEY, JSON.stringify({ ...stored, settledAt: at }));
    }
  } catch (e) {
    /* a full or unavailable sessionStorage only costs the batch strip */
  }
  return at;
}

export function batchInFlight(root) {
  const procbar = root.querySelector('[data-part="procbar"]');
  return Number(procbar?.dataset.inFlight) > 0;
}

export function batchProgress(root) {
  if (!batchInFlight(root)) return null;

  const procbar = root.querySelector('[data-part="procbar"]');
  return { settled: Number(procbar.dataset.settled), total: Number(procbar.dataset.total) };
}

export function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
}

export function plural(n, one, many) {
  return n === 1 ? one : many;
}

export function availableActions(statuses) {
  return ACTIONS
    .map((action) => ({ action, count: statuses.filter((s) => action.from.includes(s)).length }))
    .filter((entry) => entry.count > 0);
}

export function bulkChipsHtml(available, busy = null) {
  if (available.length === 0) return `<span class="bulk-none">Nenhuma ação disponível para esta seleção</span>`;
  return available.map(({ action, count }) => {
    if (action.id === "issue_label" && busy) {
      return `<button type="button" class="bulk-chip" data-act="${action.id}" disabled><span class="spin"></span> ${escapeHtml(busy.label)} <span class="cnt">${busy.settled}/${busy.total}</span></button>`;
    }
    return `<button type="button" class="bulk-chip ${action.danger ? "danger" : ""}" data-act="${action.id}"><i class="bi ${action.icon}"></i> ${escapeHtml(ACTION_LABELS[action.id])} <span class="cnt">${count}</span></button>`;
  }).join("");
}

export function confirmText(count) {
  return `Cancelar ${count} ${plural(count, "pedido", "pedidos")}? Esta ação não pode ser desfeita.`;
}

export function bulkFormBody(event, numbers) {
  const body = new URLSearchParams();
  body.set("event", event);
  numbers.forEach((n) => body.append("order_numbers[]", n));
  return body;
}

export function csrfHeader(doc) {
  const token = doc.querySelector('meta[name="csrf-token"]');
  return { "X-CSRF-Token": token ? token.content : "" };
}

export function bulkToastMessage(counts, label) {
  const parts = [];
  if (counts.done) parts.push(`${counts.done} ${plural(counts.done, "atualizado", "atualizados")}`);
  if (counts.queued) parts.push(`${counts.queued} ${plural(counts.queued, "enfileirado", "enfileirados")}`);
  if (counts.skipped) parts.push(`${counts.skipped} ${plural(counts.skipped, "ignorado", "ignorados")}`);
  return `<b>${escapeHtml(label)}</b>: ${parts.join(", ")}.`;
}

export function skippedLabelsMessage(count) {
  return `${count} ${plural(count, "etiqueta ignorada", "etiquetas ignoradas")} (sem etiqueta pronta).`;
}

export function tallyOutcomes(results) {
  const counts = { done: 0, queued: 0, skipped: 0 };
  results.forEach((result) => { counts[result.outcome] += 1; });
  return counts;
}

export function throttleKey(actionId, number) {
  return `${actionId}:${number}`;
}

export function partitionThrottled(numbers, actionId, sentAt, now) {
  const fresh = [];
  const throttled = [];
  numbers.forEach((number) => {
    const at = sentAt.get(throttleKey(actionId, number));
    if (at !== undefined && now - at < BULK_THROTTLE_MS) throttled.push(number);
    else fresh.push(number);
  });
  return { fresh, throttled };
}

export function throttledMessage(count) {
  const label = plural(count, "pedido já enviado", "pedidos já enviados");
  return `${count} ${label} nos últimos ${BULK_THROTTLE_MS / 1000}s. A fila ainda está processando, aguarde.`;
}

export function initOrders(root, today = new Date(), storage = window.sessionStorage) {
  const $ = (sel) => root.querySelector(sel);
  const table = createTable(root, {
    onRender: () => afterRender(),
    onRestore: (params) => syncFilters(root, params)
  });
  initShell(root);
  bindFilters(root, table);

  const selected = new Map();
  const sentAt = new Map();
  const batch = readBatch(storage);
  let holdTimer = null;
  let batchFlying = batchInFlight(root);
  const feedback = createLabelFeedback(root, {
    path: root.dataset.feedbackUrl,
    params: () => ({ ...table.params, lote: [ ...batch ] }),
    onSwap: () => { syncSelection(); reloadOnBatchSettled(); holdBatch(); }
  });
  const bulkbar = $("#bulkbar");
  const bulkPrint = $("#bulk-print");
  const datePop = $("#date-pop");
  const toasts = document.getElementById("toasts");

  const statusPop = () => $("#status-pop");
  const statusTrigger = () => $("#status-trigger");
  const dateTrigger = () => $("#date-trigger");

  const dp = { left: anchorMonth({ from: null, to: null }, today), sel: { from: null, to: null }, preset: null };
  let openPopEl = null;
  let openTriggerEl = null;

  function closePop() {
    if (openPopEl) openPopEl.classList.remove("open");
    if (openTriggerEl) openTriggerEl.classList.remove("open");
    openPopEl = null;
    openTriggerEl = null;
  }
  function positionPop() {
    if (!openPopEl || !openTriggerEl) return;
    const rect = openTriggerEl.getBoundingClientRect();
    openPopEl.style.top = `${rect.bottom + 8}px`;
    openPopEl.style.left = `${rect.left}px`;
  }
  function openPop(trigger, pop) {
    closePop();
    pop.classList.add("open");
    trigger.classList.add("open");
    openPopEl = pop;
    openTriggerEl = trigger;
    positionPop();
  }

  function selectedStatuses() {
    return [ ...selected.values() ];
  }

  function renderBulk() {
    bulkbar.hidden = selected.size === 0;
    if (selected.size === 0) return;

    $("#bulk-n").textContent = selected.size;
    const wrap = $("#bulk-actions");
    const progress = batchProgress(root);
    wrap.innerHTML = bulkChipsHtml(
      availableActions(selectedStatuses()),
      progress && { ...progress, label: wrap.dataset.issuingLabel }
    );
    bulkPrint.hidden = !selectedStatuses().some((s) => PRINTABLE_LABEL_STATUSES.has(s));
  }

  function afterRender() {
    applyRowStatus(root);
    applyBusyRows(root);
    applyProgress(root);
    syncSelection();
    if (inFlight(root)) feedback.start();
  }

  function reloadOnBatchSettled() {
    const flying = batchInFlight(root);
    if (batchFlying && !flying) {
      batch.forEach((number) => selected.delete(number));
      table.reload({ push: false });
    }
    batchFlying = flying;
  }

  function holdBatch() {
    if (batch.size === 0 || batchInFlight(root)) {
      clearTimeout(holdTimer);
      holdTimer = null;
      stampSettled(storage, null);
      return;
    }
    if (holdTimer !== null) return;

    const settledAt = readSettledAt(storage) ?? stampSettled(storage, Date.now());
    holdTimer = setTimeout(() => {
      holdTimer = null;
      batch.clear();
      writeBatch(storage, batch);
      const procbar = root.querySelector('[data-part="procbar"]');
      if (procbar) procbar.hidden = true;
      renderBulk();
    }, Math.max(0, BATCH_HOLD_MS - (Date.now() - settledAt)));
  }

  function syncSelection() {
    const rows = Array.from(root.querySelectorAll("#orders-body tr[data-order]"));
    rows.forEach((row) => {
      const on = selected.has(row.dataset.order);
      if (on) selected.set(row.dataset.order, row.dataset.status);
      row.classList.toggle("sel-row", on);
      const box = row.querySelector("[data-check]");
      if (box) {
        box.classList.toggle("on", on);
        box.setAttribute("aria-checked", String(on));
      }
    });

    const selectable = rows.filter((row) => selectableRow(row));
    const selN = selectable.filter((row) => selected.has(row.dataset.order)).length;
    const checkall = $("#o-checkall");
    if (checkall) {
      checkall.classList.toggle("on", selN > 0 && selN === selectable.length);
      checkall.classList.toggle("ind", selN > 0 && selN < selectable.length);
    }
    renderBulk();
  }

  function selectableRow(row) {
    return !!row.querySelector("[data-check]") && !row.classList.contains("is-busy");
  }

  function toggleRow(number, status, row) {
    if (!selectableRow(row)) return;

    if (selected.has(number)) selected.delete(number); else selected.set(number, status);
    syncSelection();
  }

  function toggleAll() {
    const rows = Array.from(root.querySelectorAll("#orders-body tr[data-order]"))
      .filter((row) => selectableRow(row));
    const allSel = rows.length > 0 && rows.every((row) => selected.has(row.dataset.order));
    rows.forEach((row) => {
      if (allSel) selected.delete(row.dataset.order);
      else selected.set(row.dataset.order, row.dataset.status);
    });
    syncSelection();
  }

  function toast(kind, html) {
    const el = document.createElement("div");
    el.className = `toast ${kind === "warn" ? "toast-warn" : "toast-ok"}`;
    el.innerHTML = `<i class="bi ${kind === "warn" ? "bi-exclamation-circle-fill" : "bi-check-circle-fill"}"></i><div class="tx">${html}</div>`;
    toasts.appendChild(el);
    setTimeout(() => {
      el.classList.add("toast-leaving");
      setTimeout(() => el.remove(), 320);
    }, 3400);
  }

  async function applyBulk(actionId) {
    const action = ACTIONS.find((a) => a.id === actionId);
    const numbers = [ ...selected.entries() ].filter(([ , status ]) => action.from.includes(status)).map(([ n ]) => n);
    if (action.id === "cancel" && !window.confirm(confirmText(numbers.length))) return;

    const { fresh, throttled } = partitionThrottled(numbers, actionId, sentAt, Date.now());
    if (throttled.length > 0) toast("warn", throttledMessage(throttled.length));
    if (fresh.length === 0) return;

    const sentNow = Date.now();
    fresh.forEach((number) => sentAt.set(throttleKey(actionId, number), sentNow));

    try {
      const res = await fetch(root.dataset.bulkUrl, {
        method: "POST",
        headers: { ...csrfHeader(document), "Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded" },
        body: bulkFormBody(actionId, fresh)
      });
      const data = await res.json();
      if (!batchInFlight(root)) batch.clear();
      data.results.forEach((result) => {
        if (selected.has(result.number)) selected.set(result.number, result.status);
        if (result.outcome === "queued") batch.add(result.number);
      });
      writeBatch(storage, batch);
      await table.reload({ push: false });
      feedback.start();
      toast(action.danger ? "warn" : "ok", bulkToastMessage(tallyOutcomes(data.results), ACTION_LABELS[action.id]));
    } catch (e) {
      fresh.forEach((number) => sentAt.delete(throttleKey(actionId, number)));
      toast("warn", "Não foi possível aplicar a ação. Tente novamente.");
    }
  }

  async function retryLabel(url, number) {
    const { fresh } = partitionThrottled([ number ], "issue_label", sentAt, Date.now());
    if (fresh.length === 0) { toast("warn", throttledMessage(1)); return; }

    sentAt.set(throttleKey("issue_label", number), Date.now());
    try {
      const res = await fetch(url, { method: "POST", headers: { ...csrfHeader(document), "Accept": "application/json" } });
      if (!res.ok) throw new Error(String(res.status));

      batch.add(number);
      writeBatch(storage, batch);
      feedback.start();
    } catch (e) {
      sentAt.delete(throttleKey("issue_label", number));
      toast("warn", RETRY_FAILED);
    }
  }

  async function printLabels() {
    const numbers = [ ...selected.entries() ]
      .filter(([ , status ]) => PRINTABLE_LABEL_STATUSES.has(status)).map(([ n ]) => n);
    if (numbers.length === 0) return;

    try {
      const res = await fetch(root.dataset.printUrl, {
        method: "POST",
        headers: { ...csrfHeader(document), "Accept": "application/pdf", "Content-Type": "application/x-www-form-urlencoded" },
        body: bulkFormBody("print", numbers)
      });
      if (!res.ok) { toast("warn", "Nenhuma etiqueta pronta para impressão."); return; }

      const blob = await res.blob();
      window.open(URL.createObjectURL(blob), "_blank");
      const skipped = Number(res.headers.get("X-Skipped-Count"));
      if (skipped > 0) toast("ok", skippedLabelsMessage(skipped));
    } catch (e) {
      toast("warn", "Não foi possível gerar as etiquetas. Tente novamente.");
    }
  }

  function currentStatuses() {
    return Array.from(statusPop().querySelectorAll(".opt.sel")).map((opt) => opt.dataset.st);
  }

  function renderDatePop() {
    datePop.innerHTML = datePopHtml(dp.left, dp.sel, today, dp.preset);
  }

  function committedRange() {
    const { de, ate } = dateTrigger().dataset;
    return { from: de ? parseISO(de) : null, to: ate ? parseISO(ate) : null };
  }

  root.addEventListener("click", (event) => {
    const retry = event.target.closest("[data-retry-url]");
    if (retry) {
      event.stopPropagation();
      retryLabel(retry.dataset.retryUrl, retry.dataset.retry);
      return;
    }
    if (event.target.closest("#o-checkall")) {
      toggleAll();
      return;
    }
    const check = event.target.closest("[data-check]");
    if (check) {
      event.stopPropagation();
      const row = check.closest("tr[data-order]");
      toggleRow(check.dataset.check, row.dataset.status, row);
      return;
    }
    const row = event.target.closest("#orders-body tr[data-order]");
    if (row && !event.target.closest("a")) {
      const link = row.querySelector("a.cell-link");
      if (link) link.click();
    }
  });

  $("#bulk-clear").addEventListener("click", () => { selected.clear(); syncSelection(); });
  $("#bulk-actions").addEventListener("click", (event) => {
    const chip = event.target.closest("[data-act]");
    if (chip) applyBulk(chip.dataset.act);
  });
  bulkPrint.addEventListener("click", printLabels);

  root.addEventListener("click", (event) => {
    if (event.target.closest("#status-pop")) {
      event.stopPropagation();
      const opt = event.target.closest(".opt");
      if (opt) {
        opt.classList.toggle("sel");
        table.set({ status: currentStatuses() });
      } else if (event.target.closest("#status-clear")) {
        statusPop().querySelectorAll(".opt").forEach((o) => o.classList.remove("sel"));
        table.set({ status: [] });
      } else if (event.target.closest("#status-apply")) {
        closePop();
      }
      return;
    }

    if (event.target.closest("#status-trigger")) {
      event.stopPropagation();
      if (statusPop().classList.contains("open")) closePop(); else openPop(statusTrigger(), statusPop());
      return;
    }

    if (event.target.closest("#date-clear")) {
      event.stopPropagation();
      table.set({ de: null, ate: null });
      return;
    }

    if (event.target.closest("#date-trigger")) {
      event.stopPropagation();
      if (datePop.classList.contains("open")) { closePop(); return; }

      dp.sel = committedRange();
      dp.left = anchorMonth(dp.sel, today);
      dp.preset = null;
      renderDatePop();
      openPop(dateTrigger(), datePop);
    }
  });

  datePop.addEventListener("click", (event) => {
    event.stopPropagation();
    const preset = event.target.closest(".dp-preset");
    if (preset) {
      dp.sel = applyPreset(preset.dataset.p, today);
      dp.preset = preset.dataset.p;
      dp.left = anchorMonth(dp.sel, today);
      renderDatePop();
      return;
    }
    const nav = event.target.closest(".dp-nav[data-nav]");
    if (nav) {
      dp.left = addMonths(dp.left, nav.dataset.nav === "prev" ? -1 : 1);
      renderDatePop();
      return;
    }
    const day = event.target.closest(".dp-day[data-d]");
    if (day) {
      dp.sel = nextSelection(dp.sel, parseISO(day.dataset.d));
      dp.preset = null;
      renderDatePop();
      return;
    }
    if (event.target.closest("#dp-clear")) {
      dp.sel = { from: null, to: null };
      dp.preset = null;
      renderDatePop();
      return;
    }
    if (event.target.closest("#dp-apply")) {
      closePop();
      table.set({ de: dp.sel.from ? toISO(dp.sel.from) : null, ate: dp.sel.to ? toISO(dp.sel.to) : null });
    }
  });

  const onDocClick = (event) => {
    if (!event.target.closest(".pop") && !event.target.closest("[data-pop]")) closePop();
  };
  const onDocKeydown = (event) => { if (event.key === "Escape") closePop(); };
  document.addEventListener("click", onDocClick);
  document.addEventListener("keydown", onDocKeydown);
  window.addEventListener("scroll", positionPop, true);
  window.addEventListener("resize", positionPop);

  applyProgress(root);
  syncSelection();
  if (inFlight(root) || batch.size > 0) feedback.start();

  return {
    table,
    selected,
    feedback,
    destroy() {
      document.removeEventListener("click", onDocClick);
      document.removeEventListener("keydown", onDocKeydown);
      window.removeEventListener("scroll", positionPop, true);
      window.removeEventListener("resize", positionPop);
      clearTimeout(holdTimer);
      feedback.destroy();
      table.destroy();
    }
  };
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector('[data-list="orders"]');
  if (root) initOrders(root);
}
/* v8 ignore stop */
