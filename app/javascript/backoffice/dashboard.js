// Backoffice dashboard: order history + client list, with a date-range picker,
// status multi-select, column sorting and a state-aware bulk action bar. Real
// data is handed in through the [data-dashboard] JSON island the server renders
// (app/views/admin/dashboard/index.html.erb); the rich filtering/sorting/bulk
// UX runs entirely client-side. Bulk transitions POST the affected order numbers
// to Admin::BulkTransitionsController and reconcile each row from the JSON
// response. Shipped as a self-contained native ES
// module via `javascript_include_tag "backoffice/dashboard", type: "module"`:
// no importmap, no build step. The browser runs the guarded bootstrap at the
// bottom; tests import the named functions and drive them against jsdom.

// ── Constants ────────────────────────────────────────────────────────────────
export const MONTHS_SHORT = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];
export const MONTHS_LONG = ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho", "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"];
export const DOW = ["D", "S", "T", "Q", "Q", "S", "S"];
export const AVATAR_TINTS = ["#e4322b", "#f0851f", "#caa106", "#2aa564", "#2f7fd1", "#6b4fb0", "#00938a", "#b80a41"];

// Saturated dot colours for the status multi-select (the pill tints are lighter).
export const STATUS_COLORS = {
  awaiting_payment: "#6b7280", payment_confirmed: "#00736c", awaiting_components: "#9a7400",
  in_production: "#2a5db0", production_issue: "#c0392b", label_issued: "#6b4fb0",
  shipped: "#2f7fd1", delivered: "#1f8a5b", awaiting_refund: "#b9650a",
  delivery_issue: "#c2410c", cancelled: "#9aa0a8", merged: "#64748b"
};

// Manual bulk transitions only, mirroring Order::TRANSITIONS. System/customer
// transitions (payment webhook, Correios tracking, a customer's refund request)
// are intentionally absent. "Cancelar" only touches unpaid orders; a paid order
// is closed by processing its refund ("Reembolso processado") once awaiting_refund.
export const ACTIONS = [
  { id: "to_components", icon: "bi-box-seam", from: ["payment_confirmed"], to: "awaiting_components" },
  { id: "issue_label", icon: "bi-upc-scan", from: ["in_production"], to: "label_issued" },
  { id: "flag_issue", icon: "bi-exclamation-triangle", from: ["in_production"], to: "production_issue" },
  { id: "refund_done", icon: "bi-cash-coin", from: ["awaiting_refund"], to: "cancelled" },
  { id: "cancel", icon: "bi-x-circle", danger: true, from: ["awaiting_payment"], to: "cancelled" }
];

export const PRINTABLE_LABEL_STATUSES = new Set(["label_issued", "shipped", "delivered", "delivery_issue"]);

export const SITUATION_TAGS = {
  active: { cls: "tag-active", icon: "bi-check-circle-fill" },
  pending: { cls: "tag-pending", icon: "bi-hourglass-split" },
  locked: { cls: "tag-locked", icon: "bi-lock-fill" }
};

export const PRESETS = [
  { id: "today", label: "Hoje" },
  { id: "7", label: "Últimos 7 dias" },
  { id: "30", label: "Últimos 30 dias" },
  { id: "month", label: "Este mês" },
  { id: "prevmonth", label: "Mês passado" },
  { id: "ytd", label: "Este ano" }
];

// ── Formatting ───────────────────────────────────────────────────────────────
export function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
}

const pad2 = (n) => String(n).padStart(2, "0");

export function parseISO(iso) {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function fmtDate(value) {
  const dt = typeof value === "string" ? parseISO(value) : value;
  return `${pad2(dt.getDate())} ${MONTHS_SHORT[dt.getMonth()]} ${dt.getFullYear()}`;
}

export function toISO(date) {
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

export function fmtBRL(cents) {
  return `R$ ${(cents / 100).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export function formatCpf(digits) {
  const value = String(digits ?? "");
  if (!/^\d{11}$/.test(value)) return value;
  return `${value.slice(0, 3)}.${value.slice(3, 6)}.${value.slice(6, 9)}-${value.slice(9, 11)}`;
}

export function formatPhone(digits) {
  const value = String(digits ?? "");
  if (/^\d{11}$/.test(value)) return `(${value.slice(0, 2)}) ${value.slice(2, 7)}-${value.slice(7, 11)}`;
  if (/^\d{10}$/.test(value)) return `(${value.slice(0, 2)}) ${value.slice(2, 6)}-${value.slice(6, 10)}`;
  return value;
}

export function initials(name) {
  const tokens = String(name ?? "").trim().split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return "";
  const first = tokens[0][0];
  const last = tokens.length > 1 ? tokens[tokens.length - 1][0] : "";
  return (first + last).toUpperCase();
}

export function tintIndex(name) {
  let hash = 0;
  const value = String(name ?? "");
  for (let i = 0; i < value.length; i += 1) hash = (hash * 31 + value.charCodeAt(i)) >>> 0;
  return hash % AVATAR_TINTS.length;
}

export function plural(n, one, many) {
  return n === 1 ? one : many;
}

// Each sidebar tab has its own dedicated path; map the current path back to its
// view so landing on (or navigating back to) a path opens the right tab.
export function viewForPath(pathname, byPath) {
  return byPath.get(pathname) || "orders";
}

// ── Date math ────────────────────────────────────────────────────────────────
export function sameDay(a, b) {
  return Boolean(a) && Boolean(b) &&
    a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

export function startOfMonth(d) {
  return new Date(d.getFullYear(), d.getMonth(), 1);
}

export function addMonths(d, n) {
  return new Date(d.getFullYear(), d.getMonth() + n, 1);
}

export function applyPreset(preset, today) {
  const end = new Date(today);
  let start = new Date(today);
  if (preset === "7") start.setDate(start.getDate() - 6);
  else if (preset === "30") start.setDate(start.getDate() - 29);
  else if (preset === "month") start = new Date(today.getFullYear(), today.getMonth(), 1);
  else if (preset === "prevmonth") {
    start = new Date(today.getFullYear(), today.getMonth() - 1, 1);
    end.setTime(new Date(today.getFullYear(), today.getMonth(), 0).getTime());
  } else if (preset === "ytd") start = new Date(today.getFullYear(), 0, 1);
  return { from: start, to: end };
}

// Cells for one month: leading blanks ({ blank: true }) then day cells with the
// in-range / start / end / today flags the calendar paints.
export function monthCells(monthDate, sel, today) {
  const y = monthDate.getFullYear();
  const m = monthDate.getMonth();
  const startDow = new Date(y, m, 1).getDay();
  const days = new Date(y, m + 1, 0).getDate();
  const cells = [];
  for (let i = 0; i < startDow; i += 1) cells.push({ blank: true });
  for (let d = 1; d <= days; d += 1) {
    const date = new Date(y, m, d);
    const { from, to } = sel;
    cells.push({
      day: d,
      iso: `${y}-${pad2(m + 1)}-${pad2(d)}`,
      today: sameDay(date, today),
      inRange: Boolean(from && to && date > from && date < to),
      start: Boolean(from && sameDay(date, from)),
      end: Boolean((to && sameDay(date, to)) || (from && !to && sameDay(date, from)))
    });
  }
  return cells;
}

// ── Orders: filter / sort / bulk ─────────────────────────────────────────────
export function filterOrders(orders, state) {
  const query = state.oName.trim().toLowerCase();
  return orders.filter((o) => {
    if (query && !(o.clientName.toLowerCase().includes(query) || o.n.toLowerCase().includes(query))) return false;
    if (state.statuses.size) {
      if (!state.statuses.has(o.status)) return false;
    } else if (o.status === "merged") {
      return false;
    }
    const date = parseISO(o.date);
    if (state.from && date < state.from) return false;
    if (state.to && date > state.to) return false;
    return true;
  });
}

export function sortOrders(rows, sort, statusOrder) {
  const sign = sort.dir === "asc" ? 1 : -1;
  const value = (o) => {
    if (sort.key === "client") return o.clientName.toLowerCase();
    if (sort.key === "total") return o.total;
    if (sort.key === "status") return statusOrder.indexOf(o.status);
    return o.date;
  };
  return [...rows].sort((a, b) => {
    const va = value(a);
    const vb = value(b);
    if (va < vb) return -1 * sign;
    if (va > vb) return 1 * sign;
    return 0;
  });
}

export function affectedBy(action, orders) {
  return orders.filter((o) => action.from.includes(o.status));
}

export function availableActions(orders) {
  return ACTIONS
    .map((action) => ({ action, count: affectedBy(action, orders).length }))
    .filter((entry) => entry.count > 0);
}

export function reconcileOrders(orders, results) {
  const counts = { done: 0, queued: 0, skipped: 0 };
  results.forEach((result) => {
    counts[result.outcome] += 1;
    const order = orders.find((o) => o.n === result.number);
    if (order) order.status = result.status;
  });
  return counts;
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

export function productionReportUrl(state, base) {
  const params = new URLSearchParams();
  if (state.from) params.set("de", toISO(state.from));
  if (state.to) params.set("ate", toISO(state.to));
  const query = params.toString();
  return query ? `${base}?${query}` : base;
}

// ── Clients: filter / sort ───────────────────────────────────────────────────
export function filterClients(clients, query) {
  const q = query.trim().toLowerCase();
  if (!q) return [...clients];
  return clients.filter((c) =>
    c.name.toLowerCase().includes(q) ||
    c.email.toLowerCase().includes(q) ||
    String(c.cpf).includes(q) ||
    `${c.city ?? ""}/${c.uf ?? ""}`.toLowerCase().includes(q));
}

export function sortClients(rows, sort) {
  const sign = sort.dir === "asc" ? 1 : -1;
  return [...rows].sort((a, b) => {
    const va = a[sort.key];
    const vb = b[sort.key];
    if (va < vb) return -1 * sign;
    if (va > vb) return 1 * sign;
    return 0;
  });
}

// ── Templates (pure HTML builders) ───────────────────────────────────────────
export function ordersRowsHtml(rows, selected, statusLabels, orderBase) {
  return rows.map((o) => {
    const on = selected.has(o.n);
    const check = o.status === "merged"
      ? `<td class="checkcol"></td>`
      : `<td class="checkcol"><span class="rowcheck ${on ? "on" : ""}" data-check="${escapeHtml(o.n)}" role="checkbox" aria-checked="${on}" tabindex="0"></span></td>`;
    const place = o.city ? `${escapeHtml(o.city)}/${escapeHtml(o.uf)}` : "–";
    return `<tr data-order="${escapeHtml(o.n)}" class="${on ? "sel-row" : ""}">
      ${check}
      <td><a class="cell-mono cell-link" href="${escapeHtml(orderBase)}${encodeURIComponent(o.n)}">${escapeHtml(o.n)}</a></td>
      <td>
        <div class="who">
          <div class="who-av who-av--${tintIndex(o.clientName)}">${escapeHtml(initials(o.clientName))}</div>
          <div class="who-meta"><div class="nm">${escapeHtml(o.clientName)}</div><div class="em">${place}</div></div>
        </div>
      </td>
      <td class="cell-num">${fmtDate(o.date)}<div class="cell-sub">${o.items} ${plural(o.items, "item", "itens")}</div></td>
      <td><span class="pill st-${o.status}">${escapeHtml(statusLabels[o.status])}</span></td>
      <td class="num"><span class="amount">${fmtBRL(o.total)}</span></td>
      <td class="num"><i class="bi bi-chevron-right row-chev"></i></td>
    </tr>`;
  }).join("");
}

export function clientsRowsHtml(rows, situationLabels) {
  return rows.map((c) => {
    const tag = SITUATION_TAGS[c.status];
    const place = c.city ? `${escapeHtml(c.city)}<span class="cell-muted">/${escapeHtml(c.uf)}</span>` : "–";
    return `<tr data-client="${c.id}">
      <td>
        <div class="who">
          <div class="who-av who-av--${tintIndex(c.name)}">${escapeHtml(initials(c.name))}</div>
          <div class="who-meta"><div class="nm">${escapeHtml(c.name)}</div><div class="em">${escapeHtml(c.email)}</div></div>
        </div>
      </td>
      <td class="cell-num">${escapeHtml(formatCpf(c.cpf))}</td>
      <td>${escapeHtml(formatPhone(c.phone)) || "–"}</td>
      <td>${place}</td>
      <td class="cell-num">${fmtDate(c.since)}</td>
      <td class="num cell-num">${c.orders}</td>
      <td><span class="tag ${tag.cls}"><i class="bi ${tag.icon}"></i> ${escapeHtml(situationLabels[c.status])}</span></td>
      <td class="num"><i class="bi bi-chevron-right row-chev"></i></td>
    </tr>`;
  }).join("");
}

export function reportsRowsHtml(rows) {
  return rows.map((r) =>
    `<tr data-report="${escapeHtml(r.id)}">
      <td class="cell-num"><a class="cell-link" href="${escapeHtml(r.url)}">${escapeHtml(r.generatedAt)}</a></td>
      <td>${escapeHtml(r.operator)}</td>
      <td>${escapeHtml(r.period)}</td>
      <td class="num cell-num">${r.orders} ${plural(r.orders, "pedido", "pedidos")}</td>
      <td class="num"><i class="bi bi-chevron-right row-chev"></i></td>
    </tr>`
  ).join("");
}

export function bulkChipsHtml(available, actionLabels) {
  if (available.length === 0) return `<span class="bulk-none">Nenhuma ação disponível para esta seleção</span>`;
  return available.map(({ action, count }) =>
    `<button class="bulk-chip ${action.danger ? "danger" : ""}" data-act="${action.id}"><i class="bi ${action.icon}"></i> ${escapeHtml(actionLabels[action.id])} <span class="cnt">${count}</span></button>`
  ).join("");
}

export function statusOptionsHtml(statusOrder, statusLabels, selected) {
  return statusOrder.map((k) =>
    `<div class="opt ${selected.has(k) ? "sel" : ""}" data-st="${k}"><span class="cbox"></span><span class="dotc dotc-${k}"></span><span class="lbl">${escapeHtml(statusLabels[k])}</span></div>`
  ).join("") +
    `<div class="pop-foot"><button class="pf-clear" id="status-clear">Limpar</button><button class="pf-apply" id="status-apply">Aplicar</button></div>`;
}

export function calendarHtml(monthDate, side, sel, today) {
  const cells = monthCells(monthDate, sel, today).map((cell) => {
    if (cell.blank) return `<div class="dp-day muted"></div>`;
    const cls = ["dp-day"];
    if (cell.today) cls.push("today");
    if (cell.inRange) cls.push("in-range");
    if (cell.start) cls.push("range-start");
    if (cell.end) cls.push("range-end");
    return `<button class="${cls.join(" ")}" data-d="${cell.iso}">${cell.day}</button>`;
  }).join("");
  const prev = `<button class="dp-nav ${side === "R" ? "dp-nav--hidden" : ""}" ${side === "L" ? 'data-nav="prev"' : ""}><i class="bi bi-chevron-left"></i></button>`;
  const next = `<button class="dp-nav ${side === "L" ? "dp-nav--hidden" : ""}" ${side === "R" ? 'data-nav="next"' : ""}><i class="bi bi-chevron-right"></i></button>`;
  const head = `<div class="dp-cal-head">${prev}<span class="mname">${MONTHS_LONG[monthDate.getMonth()]} ${monthDate.getFullYear()}</span>${next}</div>`;
  const dow = DOW.map((x) => `<div class="dp-dow">${x}</div>`).join("");
  return `<div class="dp-cal">${head}<div class="dp-grid">${dow}${cells}</div></div>`;
}

export function dpReadoutHtml(sel) {
  const { from, to } = sel;
  if (!from && !to) return `<span class="ph">Selecione o período</span>`;
  const start = from ? fmtDate(from) : `<span class="ph">início</span>`;
  const end = to ? fmtDate(to) : `<span class="ph">fim</span>`;
  return `${start} &nbsp;→&nbsp; ${end}`;
}

export function datePopHtml(left, sel, today, activePreset) {
  const presets = PRESETS.map((p) =>
    `<button class="dp-preset ${p.id === activePreset ? "on" : ""}" data-p="${p.id}">${p.label}</button>`
  ).join("");
  return `<div class="dp-body">
      <div class="dp-presets">${presets}</div>
      <div class="dp-cals">${calendarHtml(left, "L", sel, today)}${calendarHtml(addMonths(left, 1), "R", sel, today)}</div>
    </div>
    <div class="dp-foot">
      <span class="dp-readout">${dpReadoutHtml(sel)}</span>
      <span class="sp"></span>
      <button class="btn-clear" id="dp-clear"><i class="bi bi-x-lg"></i> Limpar</button>
      <button class="btn-dark" id="dp-apply">Aplicar período</button>
    </div>`;
}

export function confirmText(count) {
  return `Cancelar ${count} ${plural(count, "pedido", "pedidos")}? Esta ação não pode ser desfeita.`;
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

// ── Orchestrator ─────────────────────────────────────────────────────────────
export function initDashboard(root, data, today) {
  const { orders, clients, reports, statuses, statusLabels, actionLabels, situationLabels } = data;
  const toasts = document.getElementById("toasts");

  const state = {
    view: "orders",
    oName: "", statuses: new Set(), from: null, to: null,
    oSort: { key: "date", dir: "desc" },
    selected: new Set(),
    cQ: "", cSort: { key: "name", dir: "asc" }
  };
  const dp = { left: startOfMonth(today), sel: { from: null, to: null }, preset: null };

  const $ = (sel) => root.querySelector(sel);
  const orderBase = root.dataset.orderBase;
  const bulkUrl = root.dataset.bulkUrl;
  const printUrl = root.dataset.printUrl;
  const ordersBody = $("#orders-body");
  const ordersTable = $("#orders-table");
  const ordersEmpty = $("#orders-empty");
  const ordersCount = $("#orders-count");
  const clientsBody = $("#clients-body");
  const clientsTable = $("#clients-table");
  const clientsEmpty = $("#clients-empty");
  const clientsCount = $("#clients-count");
  const reportsBody = $("#reports-body");
  const reportsTable = $("#reports-table");
  const reportsEmpty = $("#reports-empty");
  const reportsCount = $("#reports-count");
  const statusPop = $("#status-pop");
  const statusTrigger = $("#status-trigger");
  const datePop = $("#date-pop");
  const dateTrigger = $("#date-trigger");
  const dateClear = $("#date-clear");
  const bulkbar = $("#bulkbar");
  const bulkPrint = $("#bulk-print");
  const sidebar = root.querySelector(".sidebar");

  const anyDateLabel = $("#date-trigger .val").textContent;
  const statusAllLabel = $("#status-trigger .val").textContent;

  // ── Popover machinery ──
  let openPopEl = null;
  let openTriggerEl = null;
  function openPop(trigger, pop) {
    closePop();
    pop.classList.add("open");
    trigger.classList.add("open");
    openPopEl = pop;
    openTriggerEl = trigger;
    positionPop();
  }
  function positionPop() {
    if (!openPopEl || !openTriggerEl) return;
    const rect = openTriggerEl.getBoundingClientRect();
    openPopEl.style.top = `${rect.bottom + 8}px`;
    openPopEl.style.left = `${rect.left}px`;
  }
  window.addEventListener("scroll", positionPop, true);
  window.addEventListener("resize", positionPop);
  function closePop() {
    if (openPopEl) openPopEl.classList.remove("open");
    if (openTriggerEl) openTriggerEl.classList.remove("open");
    openPopEl = null;
    openTriggerEl = null;
  }

  // ── Orders rendering ──
  function updateSortArrows(table, sort) {
    table.querySelectorAll("thead th.sortable").forEach((th) => {
      const on = th.dataset.key === sort.key;
      th.classList.toggle("sorted", on);
      th.querySelector(".sortarrow").textContent = on ? (sort.dir === "asc" ? "▲" : "▼") : "";
    });
  }
  function syncCheckAll(rows) {
    const selectable = rows.filter((o) => o.status !== "merged");
    const selN = selectable.filter((o) => state.selected.has(o.n)).length;
    const checkall = $("#o-checkall");
    checkall.classList.toggle("on", selN > 0 && selN === selectable.length);
    checkall.classList.toggle("ind", selN > 0 && selN < selectable.length);
  }
  function renderBulk() {
    const n = state.selected.size;
    bulkbar.hidden = n === 0;
    if (n === 0) return;
    $("#bulk-n").textContent = n;
    const selectedOrders = orders.filter((o) => state.selected.has(o.n));
    $("#bulk-actions").innerHTML = bulkChipsHtml(availableActions(selectedOrders), actionLabels);
    bulkPrint.hidden = !selectedOrders.some((o) => PRINTABLE_LABEL_STATUSES.has(o.status));
  }
  function renderOrders() {
    const rows = sortOrders(filterOrders(orders, state), state.oSort, statuses);
    ordersBody.innerHTML = ordersRowsHtml(rows, state.selected, statusLabels, orderBase);
    ordersEmpty.classList.toggle("show", rows.length === 0);
    ordersTable.hidden = rows.length === 0;
    const total = rows.reduce((sum, o) => sum + o.total, 0);
    ordersCount.textContent = `${rows.length} ${plural(rows.length, "pedido", "pedidos")} · ${fmtBRL(total)}`;
    updateSortArrows(ordersTable, state.oSort);
    syncCheckAll(rows);
    renderBulk();
  }
  function renderClients() {
    const rows = sortClients(filterClients(clients, state.cQ), state.cSort);
    clientsBody.innerHTML = clientsRowsHtml(rows, situationLabels);
    clientsEmpty.classList.toggle("show", rows.length === 0);
    clientsTable.hidden = rows.length === 0;
    clientsCount.textContent = `${rows.length} ${plural(rows.length, "cliente", "clientes")}`;
    updateSortArrows(clientsTable, state.cSort);
  }
  function renderReports() {
    reportsBody.innerHTML = reportsRowsHtml(reports);
    reportsEmpty.classList.toggle("show", reports.length === 0);
    reportsTable.hidden = reports.length === 0;
    reportsCount.textContent = `${reports.length} ${plural(reports.length, "relatório", "relatórios")}`;
  }

  // ── Toasts ──
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

  // ── Selection + bulk actions ──
  function toggleSel(n) {
    if (state.selected.has(n)) state.selected.delete(n); else state.selected.add(n);
    renderOrders();
  }
  function toggleAll() {
    const rows = filterOrders(orders, state).filter((o) => o.status !== "merged");
    const allSel = rows.length > 0 && rows.every((o) => state.selected.has(o.n));
    rows.forEach((o) => (allSel ? state.selected.delete(o.n) : state.selected.add(o.n)));
    renderOrders();
  }
  async function applyBulk(actionId) {
    const action = ACTIONS.find((a) => a.id === actionId);
    const affected = affectedBy(action, orders.filter((o) => state.selected.has(o.n)));
    if (action.id === "cancel" && !window.confirm(confirmText(affected.length))) return;
    try {
      const res = await fetch(bulkUrl, {
        method: "POST",
        headers: { ...csrfHeader(document), "Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded" },
        body: bulkFormBody(actionId, affected.map((o) => o.n))
      });
      const data = await res.json();
      const counts = reconcileOrders(orders, data.results);
      renderOrders();
      toast(action.danger ? "warn" : "ok", bulkToastMessage(counts, actionLabels[action.id]));
    } catch (e) {
      toast("warn", "Não foi possível aplicar a ação. Tente novamente.");
    }
  }
  async function printLabels() {
    const numbers = orders
      .filter((o) => state.selected.has(o.n) && PRINTABLE_LABEL_STATUSES.has(o.status))
      .map((o) => o.n);
    if (numbers.length === 0) return;
    try {
      const res = await fetch(printUrl, {
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

  // ── Filter triggers ──
  function syncStatusTrigger() {
    const n = state.statuses.size;
    const val = $("#status-trigger .val");
    const num = $("#status-trigger .pillnum");
    if (n === 0) {
      val.textContent = statusAllLabel;
      val.classList.add("placeholder");
      num.hidden = true;
    } else if (n === 1) {
      val.textContent = statusLabels[[...state.statuses][0]];
      val.classList.remove("placeholder");
      num.hidden = true;
    } else {
      val.textContent = "status selecionados";
      val.classList.remove("placeholder");
      num.textContent = n;
      num.hidden = false;
    }
  }
  function syncDateTrigger() {
    const val = $("#date-trigger .val");
    if (state.from) {
      val.textContent = state.to ? `${fmtDate(state.from)} – ${fmtDate(state.to)}` : fmtDate(state.from);
      val.classList.remove("placeholder");
      dateClear.hidden = false;
    } else {
      val.textContent = anyDateLabel;
      val.classList.add("placeholder");
      dateClear.hidden = true;
    }
  }

  // ── Date picker ──
  function renderDatePop() {
    datePop.innerHTML = datePopHtml(dp.left, dp.sel, today, dp.preset);
  }
  function openDatePicker() {
    dp.sel = { from: state.from, to: state.to };
    dp.left = addMonths(startOfMonth(dp.sel.to || today), -1);
    dp.preset = null;
    renderDatePop();
  }

  // ── View switching ──
  function switchView(view) {
    state.view = view;
    root.querySelectorAll(".sb-link[data-view]").forEach((l) => l.classList.toggle("active", l.dataset.view === view));
    root.querySelectorAll(".view").forEach((section) => { section.hidden = section.dataset.view !== view; });
    const link = root.querySelector(`.sb-link[data-view="${view}"]`);
    $("#page-title").textContent = link.dataset.title;
    $("#page-crumb").textContent = link.dataset.crumb;
    closePop();
    sidebar.classList.remove("show");
  }

  function clearOrderFilters() {
    state.oName = "";
    $("#o-name").value = "";
    state.statuses.clear();
    statusPop.querySelectorAll(".opt").forEach((o) => o.classList.remove("sel"));
    syncStatusTrigger();
    state.from = null;
    state.to = null;
    syncDateTrigger();
    renderOrders();
  }

  function row(target) {
    const tr = target.closest("tr");
    if (tr) tr.animate([{ background: "#eef0f3" }, { background: "transparent" }], { duration: 380, easing: "ease-out" });
  }

  // ── Wiring ──
  statusPop.innerHTML = statusOptionsHtml(statuses, statusLabels, state.statuses);
  syncStatusTrigger();
  syncDateTrigger();

  const navLinks = [...root.querySelectorAll(".sb-link[data-view]")];
  const viewByPath = new Map(navLinks.map((l) => [new URL(l.href).pathname, l.dataset.view]));
  navLinks.forEach((l) =>
    l.addEventListener("click", (e) => {
      e.preventDefault();
      switchView(l.dataset.view);
      window.history.pushState({}, "", l.getAttribute("href"));
    }));
  $("#menu-toggle").addEventListener("click", () => sidebar.classList.toggle("show"));

  $("#o-name").addEventListener("input", (e) => { state.oName = e.target.value; renderOrders(); });

  statusTrigger.addEventListener("click", (e) => {
    e.stopPropagation();
    if (statusPop.classList.contains("open")) closePop(); else openPop(statusTrigger, statusPop);
  });
  statusPop.addEventListener("click", (e) => {
    // Keep clicks inside the popover from reaching the document outside-click
    // handler, because re-renders detach the target, which would otherwise read as
    // an outside click and close the popover.
    e.stopPropagation();
    const opt = e.target.closest(".opt");
    if (opt) {
      const k = opt.dataset.st;
      if (state.statuses.has(k)) state.statuses.delete(k); else state.statuses.add(k);
      opt.classList.toggle("sel", state.statuses.has(k));
      syncStatusTrigger();
      renderOrders();
      return;
    }
    if (e.target.closest("#status-clear")) {
      state.statuses.clear();
      statusPop.querySelectorAll(".opt").forEach((o) => o.classList.remove("sel"));
      syncStatusTrigger();
      renderOrders();
      return;
    }
    if (e.target.closest("#status-apply")) closePop();
  });

  dateTrigger.addEventListener("click", (e) => {
    // #date-clear lives inside the trigger but stops propagation, so it never
    // reaches here; clicking the trigger body just toggles the picker.
    e.stopPropagation();
    if (datePop.classList.contains("open")) { closePop(); return; }
    openDatePicker();
    openPop(dateTrigger, datePop);
  });
  dateClear.addEventListener("click", (e) => {
    e.stopPropagation();
    state.from = null;
    state.to = null;
    syncDateTrigger();
    renderOrders();
  });
  datePop.addEventListener("click", (e) => {
    e.stopPropagation(); // see the status popover handler: re-renders detach the target
    const preset = e.target.closest(".dp-preset");
    if (preset) {
      dp.sel = applyPreset(preset.dataset.p, today); // always yields a `to`
      dp.preset = preset.dataset.p;
      dp.left = addMonths(startOfMonth(dp.sel.to), -1);
      renderDatePop();
      return;
    }
    const nav = e.target.closest(".dp-nav[data-nav]");
    if (nav) {
      dp.left = addMonths(dp.left, nav.dataset.nav === "prev" ? -1 : 1);
      renderDatePop();
      return;
    }
    const day = e.target.closest(".dp-day[data-d]");
    if (day) {
      const date = parseISO(day.dataset.d);
      const { from, to } = dp.sel;
      if (!from || (from && to)) dp.sel = { from: date, to: null };
      else if (date < from) dp.sel = { from: date, to: from };
      else dp.sel = { from, to: date };
      dp.preset = null;
      renderDatePop();
      return;
    }
    if (e.target.closest("#dp-clear")) {
      dp.sel = { from: null, to: null };
      dp.preset = null;
      renderDatePop();
      return;
    }
    if (e.target.closest("#dp-apply")) {
      state.from = dp.sel.from;
      state.to = dp.sel.to;
      syncDateTrigger();
      renderOrders();
      closePop();
    }
  });

  $("#o-clear").addEventListener("click", clearOrderFilters);

  const genReport = $("#gen-production");
  genReport.addEventListener("click", () => {
    genReport.setAttribute("href", productionReportUrl(state, genReport.dataset.base));
  });

  ordersTable.querySelectorAll("thead th.sortable").forEach((th) =>
    th.addEventListener("click", () => {
      const k = th.dataset.key;
      if (state.oSort.key === k) state.oSort.dir = state.oSort.dir === "asc" ? "desc" : "asc";
      else state.oSort = { key: k, dir: k === "client" ? "asc" : "desc" };
      renderOrders();
    }));
  clientsTable.querySelectorAll("thead th.sortable").forEach((th) =>
    th.addEventListener("click", () => {
      const k = th.dataset.key;
      if (state.cSort.key === k) state.cSort.dir = state.cSort.dir === "asc" ? "desc" : "asc";
      else state.cSort = { key: k, dir: "asc" };
      renderClients();
    }));

  $("#c-q").addEventListener("input", (e) => { state.cQ = e.target.value; renderClients(); });

  $("#gsearch").addEventListener("input", (e) => {
    const v = e.target.value;
    if (state.view === "orders") { state.oName = v; $("#o-name").value = v; renderOrders(); }
    else { state.cQ = v; $("#c-q").value = v; renderClients(); }
  });

  ordersBody.addEventListener("click", (e) => {
    const cb = e.target.closest("[data-check]");
    if (cb) { e.stopPropagation(); toggleSel(cb.dataset.check); return; }
    // The whole row opens the order: forward the click to its detail link
    // (the link still handles direct clicks and middle-click-to-new-tab).
    const link = e.target.closest("tr[data-order]")?.querySelector("a.cell-link");
    if (link && link !== e.target) link.click();
  });
  $("#o-checkall").addEventListener("click", toggleAll);
  $("#bulk-clear").addEventListener("click", () => { state.selected.clear(); renderOrders(); });
  $("#bulk-actions").addEventListener("click", (e) => {
    const chip = e.target.closest("[data-act]");
    if (chip) applyBulk(chip.dataset.act);
  });
  bulkPrint.addEventListener("click", printLabels);
  clientsBody.addEventListener("click", (e) => row(e.target));
  reportsBody.addEventListener("click", (e) => {
    const link = e.target.closest("tr[data-report]")?.querySelector("a.cell-link");
    if (link && link !== e.target) link.click();
  });

  const onDocClick = (e) => {
    if (!e.target.closest(".pop") && !e.target.closest("[data-pop]")) closePop();
  };
  const onDocKeydown = (e) => { if (e.key === "Escape") closePop(); };
  const onPopState = () => switchView(viewForPath(window.location.pathname, viewByPath));
  document.addEventListener("click", onDocClick);
  document.addEventListener("keydown", onDocKeydown);
  window.addEventListener("popstate", onPopState);

  renderOrders();
  renderClients();
  renderReports();
  switchView(viewForPath(window.location.pathname, viewByPath));

  return function destroy() {
    document.removeEventListener("click", onDocClick);
    document.removeEventListener("keydown", onDocKeydown);
    window.removeEventListener("popstate", onPopState);
    window.removeEventListener("scroll", positionPop, true);
    window.removeEventListener("resize", positionPop);
  };
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector(".app[data-dashboard]");
  if (root) initDashboard(root, JSON.parse(root.dataset.dashboard), new Date());
}
/* v8 ignore stop */
