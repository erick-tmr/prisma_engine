import { createTable } from "backoffice/table";
import { bindFilters, syncFilters } from "backoffice/filters";
import { initShell } from "backoffice/shell";
import { addMonths, applyPreset, datePopHtml, nextSelection, parseISO, startOfMonth, toISO } from "backoffice/date_picker";

export const ACTIONS = [
  { id: "to_components", icon: "bi-box-seam", from: [ "payment_confirmed" ] },
  { id: "issue_label", icon: "bi-upc-scan", from: [ "in_production" ] },
  { id: "flag_issue", icon: "bi-exclamation-triangle", from: [ "in_production" ] },
  { id: "refund_done", icon: "bi-cash-coin", from: [ "awaiting_refund" ] },
  { id: "cancel", icon: "bi-x-circle", danger: true, from: [ "awaiting_payment" ] }
];

export const ACTION_LABELS = {
  to_components: "Aguardar componentes", issue_label: "Emitir etiqueta Correios",
  flag_issue: "Marcar problema", refund_done: "Reembolso processado", cancel: "Cancelar"
};

export const PRINTABLE_LABEL_STATUSES = new Set([ "label_issued" ]);

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

export function bulkChipsHtml(available) {
  if (available.length === 0) return `<span class="bulk-none">Nenhuma ação disponível para esta seleção</span>`;
  return available.map(({ action, count }) =>
    `<button type="button" class="bulk-chip ${action.danger ? "danger" : ""}" data-act="${action.id}"><i class="bi ${action.icon}"></i> ${escapeHtml(ACTION_LABELS[action.id])} <span class="cnt">${count}</span></button>`
  ).join("");
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

export function initOrders(root, today = new Date()) {
  const $ = (sel) => root.querySelector(sel);
  const table = createTable(root, {
    onRender: () => syncSelection(),
    onRestore: (params) => syncFilters(root, params)
  });
  initShell(root);
  bindFilters(root, table);

  const selected = new Map();
  const bulkbar = $("#bulkbar");
  const bulkPrint = $("#bulk-print");
  const datePop = $("#date-pop");
  const toasts = document.getElementById("toasts");

  const statusPop = () => $("#status-pop");
  const statusTrigger = () => $("#status-trigger");
  const dateTrigger = () => $("#date-trigger");

  const dp = { left: startOfMonth(today), sel: { from: null, to: null }, preset: null };
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
    $("#bulk-actions").innerHTML = bulkChipsHtml(availableActions(selectedStatuses()));
    bulkPrint.hidden = !selectedStatuses().some((s) => PRINTABLE_LABEL_STATUSES.has(s));
  }

  function syncSelection() {
    const rows = Array.from(root.querySelectorAll("#orders-body tr[data-order]"));
    rows.forEach((row) => {
      const on = selected.has(row.dataset.order);
      row.classList.toggle("sel-row", on);
      const box = row.querySelector("[data-check]");
      if (box) {
        box.classList.toggle("on", on);
        box.setAttribute("aria-checked", String(on));
      }
    });

    const selectable = rows.filter((row) => row.querySelector("[data-check]"));
    const selN = selectable.filter((row) => selected.has(row.dataset.order)).length;
    const checkall = $("#o-checkall");
    if (checkall) {
      checkall.classList.toggle("on", selN > 0 && selN === selectable.length);
      checkall.classList.toggle("ind", selN > 0 && selN < selectable.length);
    }
    renderBulk();
  }

  function toggleRow(number, status) {
    if (selected.has(number)) selected.delete(number); else selected.set(number, status);
    syncSelection();
  }

  function toggleAll() {
    const rows = Array.from(root.querySelectorAll("#orders-body tr[data-order]"))
      .filter((row) => row.querySelector("[data-check]"));
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

    try {
      const res = await fetch(root.dataset.bulkUrl, {
        method: "POST",
        headers: { ...csrfHeader(document), "Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded" },
        body: bulkFormBody(actionId, numbers)
      });
      const data = await res.json();
      data.results.forEach((result) => {
        if (selected.has(result.number)) selected.set(result.number, result.status);
      });
      await table.reload({ push: false });
      toast(action.danger ? "warn" : "ok", bulkToastMessage(tallyOutcomes(data.results), ACTION_LABELS[action.id]));
    } catch (e) {
      toast("warn", "Não foi possível aplicar a ação. Tente novamente.");
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
    if (event.target.closest("#o-checkall")) {
      toggleAll();
      return;
    }
    const check = event.target.closest("[data-check]");
    if (check) {
      event.stopPropagation();
      toggleRow(check.dataset.check, check.closest("tr[data-order]").dataset.status);
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
      dp.left = addMonths(startOfMonth(dp.sel.to || today), -1);
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
      dp.left = addMonths(startOfMonth(dp.sel.to), -1);
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

  syncSelection();

  return {
    table,
    selected,
    destroy() {
      document.removeEventListener("click", onDocClick);
      document.removeEventListener("keydown", onDocKeydown);
      window.removeEventListener("scroll", positionPop, true);
      window.removeEventListener("resize", positionPop);
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
