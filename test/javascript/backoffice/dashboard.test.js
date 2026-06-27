import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  STATUS_COLORS, ACTIONS, AVATAR_TINTS, SITUATION_TAGS, PRESETS, MONTHS_LONG,
  escapeHtml, parseISO, fmtDate, toISO, fmtBRL, formatCpf, formatPhone, initials, tintIndex, plural,
  sameDay, startOfMonth, addMonths, applyPreset, monthCells,
  filterOrders, sortOrders, affectedBy, availableActions, applyAction, productionReportUrl,
  filterClients, sortClients,
  ordersRowsHtml, clientsRowsHtml, bulkChipsHtml, statusOptionsHtml, calendarHtml, dpReadoutHtml, datePopHtml,
  confirmText, toastMessage, initDashboard
} from "../../../app/javascript/backoffice/dashboard.js";

const STATUSES = [
  "awaiting_payment", "payment_confirmed", "awaiting_components", "in_production",
  "production_issue", "label_issued", "shipped", "delivered", "awaiting_refund", "cancelled"
];
const STATUS_LABELS = Object.fromEntries(STATUSES.map((s) => [s, s.replace(/_/g, " ")]));
const ACTION_LABELS = {
  to_production: "Enviar para produção", issue_label: "Emitir etiqueta Correios",
  flag_issue: "Marcar problema", refund_done: "Reembolso processado", cancel: "Cancelar"
};
const SITUATION_LABELS = { active: "Ativo", pending: "Pendente", locked: "Bloqueado" };

function sampleData() {
  return {
    orders: [
      { n: "PG-202606140001", clientName: "Ana Cardoso", city: "São Paulo", uf: "SP", date: "2026-06-14", status: "awaiting_payment", total: 48900, items: 2 },
      { n: "PG-202606130002", clientName: "Bruno Tanaka", city: "Campinas", uf: "SP", date: "2026-06-13", status: "payment_confirmed", total: 127400, items: 3 },
      { n: "PG-202606110003", clientName: "Carla Menezes", city: "Rio de Janeiro", uf: "RJ", date: "2026-06-11", status: "in_production", total: 32900, items: 1 },
      { n: "PG-202605300004", clientName: "Diego Fontes", city: "Belo Horizonte", uf: "MG", date: "2026-05-30", status: "delivered", total: 73200, items: 2 },
      { n: "PG-202604220005", clientName: "Eduarda Lima", city: "Curitiba", uf: "PR", date: "2026-04-22", status: "awaiting_refund", total: 47900, items: 1 }
    ],
    clients: [
      { id: 1, name: "Ana Cardoso", email: "ana@example.com", cpf: "31244577809", phone: "11988765521", city: "São Paulo", uf: "SP", since: "2025-09-03", orders: 2, status: "active" },
      { id: 2, name: "Bruno Tanaka", email: "bruno@example.com", cpf: "40811722055", phone: "", city: null, uf: null, since: "2026-01-15", orders: 1, status: "pending" },
      { id: 3, name: "Carla Menezes", email: "carla@example.com", cpf: "22190345612", phone: "1133224567", city: "Rio de Janeiro", uf: "RJ", since: "2025-06-22", orders: 0, status: "locked" }
    ],
    statuses: STATUSES,
    statusLabels: STATUS_LABELS,
    actionLabels: ACTION_LABELS,
    situationLabels: SITUATION_LABELS
  };
}

const TODAY = new Date(2026, 5, 15); // 15 Jun 2026

// ════════════════════════════════════════════════════════════════════════════
//  Pure helpers
// ════════════════════════════════════════════════════════════════════════════
describe("formatting helpers", () => {
  it("escapeHtml neutralizes markup and handles nullish", () => {
    expect(escapeHtml(`<b>&"'`)).toBe("&lt;b&gt;&amp;&quot;&#39;");
    expect(escapeHtml(null)).toBe("");
  });

  it("parseISO / fmtDate render pt-BR short dates from a string or Date", () => {
    expect(parseISO("2026-06-14").getMonth()).toBe(5);
    expect(fmtDate("2026-06-14")).toBe("14 jun 2026");
    expect(fmtDate(new Date(2026, 0, 5))).toBe("05 jan 2026");
  });

  it("toISO renders a Date as a zero-padded YYYY-MM-DD string", () => {
    expect(toISO(new Date(2026, 0, 5))).toBe("2026-01-05");
    expect(toISO(new Date(2026, 11, 31))).toBe("2026-12-31");
  });

  it("fmtBRL formats cents as Brazilian currency", () => {
    expect(fmtBRL(127400)).toBe("R$ 1.274,00");
    expect(fmtBRL(0)).toBe("R$ 0,00");
  });

  it("formatCpf masks 11 digits and passes anything else (incl. null) through", () => {
    expect(formatCpf("31244577809")).toBe("312.445.778-09");
    expect(formatCpf("123")).toBe("123");
    expect(formatCpf(null)).toBe("");
  });

  it("formatPhone masks 10- and 11-digit numbers and passes others through", () => {
    expect(formatPhone("11988765521")).toBe("(11) 98876-5521");
    expect(formatPhone("1133224567")).toBe("(11) 3322-4567");
    expect(formatPhone(null)).toBe("");
  });

  it("initials takes first+last, a single token, or nothing", () => {
    expect(initials("Ana Beatriz Cardoso")).toBe("AC");
    expect(initials("Madonna")).toBe("M");
    expect(initials(undefined)).toBe("");
  });

  it("tintIndex is deterministic within the palette range", () => {
    expect(tintIndex("Ana Cardoso")).toBe(tintIndex("Ana Cardoso"));
    expect(tintIndex("Ana Cardoso")).toBeLessThan(AVATAR_TINTS.length);
    expect(tintIndex(null)).toBe(0);
  });

  it("plural picks the singular only for 1", () => {
    expect(plural(1, "pedido", "pedidos")).toBe("pedido");
    expect(plural(2, "pedido", "pedidos")).toBe("pedidos");
  });
});

describe("date math", () => {
  it("sameDay compares calendar days and rejects missing dates", () => {
    expect(sameDay(new Date(2026, 5, 15), new Date(2026, 5, 15, 9))).toBe(true);
    expect(sameDay(new Date(2026, 5, 15), new Date(2026, 5, 16))).toBe(false);
    expect(sameDay(null, new Date())).toBe(false);
  });

  it("startOfMonth / addMonths land on the first of the month", () => {
    expect(startOfMonth(new Date(2026, 5, 15)).getDate()).toBe(1);
    expect(addMonths(new Date(2026, 5, 1), -1).getMonth()).toBe(4);
    expect(addMonths(new Date(2026, 5, 1), 1).getMonth()).toBe(6);
  });

  it("applyPreset covers every preset plus the default", () => {
    expect(applyPreset("today", TODAY)).toEqual({ from: TODAY, to: TODAY });
    expect(applyPreset("7", TODAY).from).toEqual(new Date(2026, 5, 9));
    expect(applyPreset("30", TODAY).from).toEqual(new Date(2026, 4, 17));
    expect(applyPreset("month", TODAY).from).toEqual(new Date(2026, 5, 1));
    const prev = applyPreset("prevmonth", TODAY);
    expect(prev.from).toEqual(new Date(2026, 4, 1));
    expect(prev.to).toEqual(new Date(2026, 4, 31));
    expect(applyPreset("ytd", TODAY).from).toEqual(new Date(2026, 0, 1));
    expect(applyPreset("unknown", TODAY)).toEqual({ from: TODAY, to: TODAY });
  });

  it("monthCells emits leading blanks, today, range edges and in-range flags", () => {
    const sel = { from: new Date(2026, 5, 10), to: new Date(2026, 5, 20) };
    const cells = monthCells(new Date(2026, 5, 1), sel, TODAY);
    expect(cells[0]).toEqual({ blank: true }); // Jun 1 2026 is a Monday → 1 blank
    const byDay = (d) => cells.find((c) => c.day === d);
    expect(byDay(15).today).toBe(true);
    expect(byDay(10).start).toBe(true);
    expect(byDay(20).end).toBe(true);
    expect(byDay(15).inRange).toBe(true);
    expect(byDay(9).inRange).toBe(false);
  });

  it("monthCells marks a single picked day as both start and end", () => {
    const cells = monthCells(new Date(2026, 5, 1), { from: new Date(2026, 5, 12), to: null }, TODAY);
    const day12 = cells.find((c) => c.day === 12);
    expect(day12.start).toBe(true);
    expect(day12.end).toBe(true);
  });
});

describe("orders transforms", () => {
  const base = { oName: "", statuses: new Set(), from: null, to: null };

  it("filters by query, status set and date bounds", () => {
    const { orders } = sampleData();
    expect(filterOrders(orders, { ...base, oName: "cardoso" }).map((o) => o.n)).toEqual(["PG-202606140001"]);
    expect(filterOrders(orders, { ...base, oName: "PG-202606130002" })).toHaveLength(1);
    expect(filterOrders(orders, { ...base, oName: "zzz" })).toHaveLength(0);
    expect(filterOrders(orders, { ...base, statuses: new Set(["delivered"]) })).toHaveLength(1);
    expect(filterOrders(orders, { ...base, from: new Date(2026, 5, 1) }).every((o) => o.date >= "2026-06-01")).toBe(true);
    expect(filterOrders(orders, { ...base, to: new Date(2026, 4, 1) }).map((o) => o.n)).toEqual(["PG-202604220005"]);
  });

  it("sorts by client, total, status and date in both directions", () => {
    const { orders } = sampleData();
    expect(sortOrders(orders, { key: "client", dir: "asc" }, STATUSES)[0].clientName).toBe("Ana Cardoso");
    expect(sortOrders(orders, { key: "total", dir: "desc" }, STATUSES)[0].total).toBe(127400);
    expect(sortOrders(orders, { key: "total", dir: "asc" }, STATUSES)[0].total).toBe(32900);
    expect(sortOrders(orders, { key: "status", dir: "asc" }, STATUSES)[0].status).toBe("awaiting_payment");
    expect(sortOrders(orders, { key: "date", dir: "desc" }, STATUSES)[0].date).toBe("2026-06-14");
    expect(sortOrders([], { key: "date", dir: "asc" }, STATUSES)).toEqual([]);
    expect(sortOrders([{ ...orders[0] }, { ...orders[0] }], { key: "total", dir: "asc" }, STATUSES)).toHaveLength(2);
  });

  it("derives state-aware bulk actions and applies a transition", () => {
    const { orders } = sampleData();
    const confirmed = orders.filter((o) => o.status === "payment_confirmed");
    expect(affectedBy(ACTIONS.find((a) => a.id === "to_production"), confirmed)).toHaveLength(1);

    const mixed = orders.filter((o) => ["awaiting_payment", "payment_confirmed", "in_production"].includes(o.status));
    const ids = availableActions(mixed).map((entry) => entry.action.id);
    expect(ids).toContain("to_production");
    expect(ids).toContain("cancel");
    expect(ids).not.toContain("refund_done");

    const action = ACTIONS.find((a) => a.id === "to_production");
    const affected = applyAction(action, confirmed);
    expect(affected).toHaveLength(1);
    expect(confirmed[0].status).toBe("in_production");
  });

  it("productionReportUrl carries the active period or falls back to the base path", () => {
    const base = "/admin/relatorio-producao";
    expect(productionReportUrl({ from: null, to: null }, base)).toBe(base);
    expect(productionReportUrl({ from: new Date(2026, 0, 5), to: null }, base)).toBe(`${base}?de=2026-01-05`);
    expect(productionReportUrl({ from: null, to: new Date(2026, 0, 9) }, base)).toBe(`${base}?ate=2026-01-09`);
    expect(productionReportUrl({ from: new Date(2026, 0, 5), to: new Date(2026, 0, 9) }, base))
      .toBe(`${base}?de=2026-01-05&ate=2026-01-09`);
  });
});

describe("clients transforms", () => {
  it("filters by name, email, cpf or city — and returns all when blank", () => {
    const { clients } = sampleData();
    expect(filterClients(clients, "")).toHaveLength(3);
    expect(filterClients(clients, "bruno")).toHaveLength(1);
    expect(filterClients(clients, "carla@example")).toHaveLength(1);
    expect(filterClients(clients, "31244577809")).toHaveLength(1);
    expect(filterClients(clients, "rio")).toHaveLength(1);
  });

  it("sorts ascending and descending", () => {
    const { clients } = sampleData();
    expect(sortClients(clients, { key: "name", dir: "asc" })[0].name).toBe("Ana Cardoso");
    expect(sortClients(clients, { key: "orders", dir: "desc" })[0].orders).toBe(2);
    expect(sortClients([{ name: "A", orders: 5 }, { name: "B", orders: 5 }], { key: "orders", dir: "asc" })).toHaveLength(2);
  });
});

describe("template builders", () => {
  it("ordersRowsHtml marks selected rows, status pills, pluralization and links to the detail page", () => {
    const { orders } = sampleData();
    const html = ordersRowsHtml(orders, new Set(["PG-202606140001"]), STATUS_LABELS, "/admin/pedidos/");
    expect(html).toContain("sel-row");
    expect(html).toContain("st-awaiting_payment");
    expect(html).toContain("2 itens");
    expect(html).toContain("1 item");
    expect(html).toContain('href="/admin/pedidos/PG-202606140001"');
  });

  it("clientsRowsHtml renders situação tags, masks contact data and dashes a missing city", () => {
    const { clients } = sampleData();
    const html = clientsRowsHtml(clients, SITUATION_LABELS);
    expect(html).toContain("tag-active");
    expect(html).toContain("312.445.778-09");
    expect(html).toContain("(11) 98876-5521");
    expect(html).toContain("Bloqueado");
    expect(html).toContain(">—<"); // Bruno: missing city and phone
  });

  it("bulkChipsHtml shows the empty message, chips and a danger chip", () => {
    expect(bulkChipsHtml([], ACTION_LABELS)).toContain("bulk-none");
    const chips = bulkChipsHtml([
      { action: ACTIONS.find((a) => a.id === "to_production"), count: 2 },
      { action: ACTIONS.find((a) => a.id === "cancel"), count: 1 }
    ], ACTION_LABELS);
    expect(chips).toContain('data-act="to_production"');
    expect(chips).toContain("danger");
    expect(chips).toContain("Enviar para produção");
  });

  it("statusOptionsHtml renders one option per status with a coloured dot and a selection", () => {
    const html = statusOptionsHtml(STATUSES, STATUS_LABELS, new Set(["delivered"]));
    expect(html.match(/class="opt/g)).toHaveLength(STATUSES.length);
    expect(html).toContain("dotc-delivered");
    expect(html).toContain("opt sel");
    expect(html).toContain("status-apply");
  });

  it("calendarHtml hides the right-side prev nav and wires next on the right", () => {
    const sel = { from: null, to: null };
    const left = calendarHtml(new Date(2026, 5, 1), "L", sel, TODAY);
    expect(left).toContain('data-nav="prev"');
    // Each calendar must be wrapped in a .dp-cal column — the CSS lays
    // .dp-cals > .dp-cal out side by side; without the wrapper the grids
    // collapse and overflow the popover (a layout bug jsdom can't see).
    expect(left.startsWith('<div class="dp-cal">')).toBe(true);
    expect(left).toContain('<div class="dp-grid">');
    const right = calendarHtml(new Date(2026, 6, 1), "R", sel, TODAY);
    expect(right).toContain('data-nav="next"');
    expect(right).toContain("dp-nav--hidden");
    expect(right).toContain(`${MONTHS_LONG[6]} 2026`);
  });

  it("dpReadoutHtml covers no selection, partial and full ranges", () => {
    expect(dpReadoutHtml({ from: null, to: null })).toContain("Selecione o período");
    expect(dpReadoutHtml({ from: new Date(2026, 5, 10), to: null })).toContain("fim");
    expect(dpReadoutHtml({ from: null, to: new Date(2026, 5, 20) })).toContain("início");
    expect(dpReadoutHtml({ from: new Date(2026, 5, 10), to: new Date(2026, 5, 20) })).toContain("→");
  });

  it("datePopHtml highlights the active preset", () => {
    const html = datePopHtml(new Date(2026, 4, 1), { from: null, to: null }, TODAY, "30");
    expect(html).toContain('class="dp-preset on" data-p="30"');
    expect(html).toContain('class="dp-preset " data-p="7"');
  });

  it("confirmText and toastMessage pluralize", () => {
    expect(confirmText(1)).toContain("1 pedido?");
    expect(confirmText(3)).toContain("3 pedidos?");
    expect(toastMessage("Cancelar", 1)).toContain("1 pedido atualizado.");
    expect(toastMessage("Cancelar", 2)).toContain("2 pedidos atualizados.");
  });

  it("exposes the expected constant shapes", () => {
    expect(Object.keys(STATUS_COLORS)).toHaveLength(10);
    expect(PRESETS).toHaveLength(6);
    expect(SITUATION_TAGS.locked.cls).toBe("tag-locked");
  });
});

// ════════════════════════════════════════════════════════════════════════════
//  initDashboard (jsdom)
// ════════════════════════════════════════════════════════════════════════════
function mountDashboard() {
  document.body.innerHTML = `
    <div class="app" data-dashboard="{}">
      <aside class="sidebar">
        <nav>
          <a class="sb-link active" data-view="orders" data-title="Pedidos" data-crumb="Histórico de pedidos">x</a>
          <a class="sb-link" data-view="clients" data-title="Clientes" data-crumb="Todos os clientes">x</a>
        </nav>
      </aside>
      <div class="main">
        <header>
          <button class="icon-btn" id="menu-toggle" type="button"></button>
          <h1 id="page-title">Pedidos</h1>
          <span id="page-crumb">Histórico de pedidos</span>
          <input id="gsearch" type="text">
        </header>
        <main>
          <section class="view" data-view="orders">
            <span class="result-count" id="orders-count"></span>
            <a id="gen-production" href="/admin/relatorio-producao" data-base="/admin/relatorio-producao">gerar</a>
            <div class="filters">
              <input id="o-name" type="text">
              <div class="f-trigger" id="date-trigger" data-pop>
                <span class="val placeholder">Qualquer data</span>
                <button id="date-clear" type="button" hidden></button>
              </div>
              <div class="pop dp" id="date-pop"></div>
              <div class="f-trigger" id="status-trigger" data-pop>
                <span class="val placeholder">Todos os status</span>
                <span class="pillnum" hidden>0</span>
              </div>
              <div class="pop" id="status-pop"></div>
              <button id="o-clear" type="button"></button>
            </div>
            <div class="bulkbar" id="bulkbar" hidden>
              <b id="bulk-n">0</b>
              <button id="bulk-clear" type="button"></button>
              <div id="bulk-actions"></div>
            </div>
            <table class="tbl" id="orders-table">
              <thead>
                <tr>
                  <th class="checkcol"><span class="rowcheck" id="o-checkall" role="checkbox" tabindex="0"></span></th>
                  <th>Pedido</th>
                  <th class="sortable" data-key="client">Cliente <span class="sortarrow"></span></th>
                  <th class="sortable sorted" data-key="date">Data <span class="sortarrow">▼</span></th>
                  <th class="sortable" data-key="status">Status <span class="sortarrow"></span></th>
                  <th class="num sortable" data-key="total">Total <span class="sortarrow"></span></th>
                  <th class="num"></th>
                </tr>
              </thead>
              <tbody id="orders-body"></tbody>
            </table>
            <div class="empty" id="orders-empty"></div>
          </section>
          <section class="view" data-view="clients" hidden>
            <span class="result-count" id="clients-count"></span>
            <input id="c-q" type="text">
            <table class="tbl" id="clients-table">
              <thead>
                <tr>
                  <th class="sortable" data-key="name">Cliente <span class="sortarrow"></span></th>
                  <th class="sortable" data-key="cpf">CPF <span class="sortarrow"></span></th>
                  <th>Telefone</th>
                  <th class="sortable" data-key="city">Cidade <span class="sortarrow"></span></th>
                  <th class="sortable" data-key="since">Cadastro <span class="sortarrow"></span></th>
                  <th class="num sortable" data-key="orders">Pedidos <span class="sortarrow"></span></th>
                  <th class="sortable" data-key="status">Situação <span class="sortarrow"></span></th>
                  <th class="num"></th>
                </tr>
              </thead>
              <tbody id="clients-body"></tbody>
            </table>
            <div class="empty" id="clients-empty"></div>
          </section>
        </main>
      </div>
    </div>
    <div class="toasts" id="toasts" aria-live="polite"></div>`;
  return document.querySelector(".app");
}

const $ = (sel) => document.querySelector(sel);
const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
function input(el, value) {
  el.value = value;
  el.dispatchEvent(new window.Event("input", { bubbles: true }));
}

describe("initDashboard", () => {
  let root;
  let destroy;

  beforeEach(() => {
    root = mountDashboard();
    destroy = initDashboard(root, sampleData(), TODAY);
  });

  afterEach(() => {
    destroy();
    vi.restoreAllMocks();
  });

  it("renders both tables, the default sort arrow and counts", () => {
    expect($("#orders-body").querySelectorAll("tr")).toHaveLength(5);
    expect($("#clients-body").querySelectorAll("tr")).toHaveLength(3);
    expect($("#orders-count").textContent).toContain("5 pedidos");
    expect($("#clients-count").textContent).toBe("3 clientes");
    const dateTh = $('#orders-table th[data-key="date"]');
    expect(dateTh.classList.contains("sorted")).toBe(true);
    expect(dateTh.querySelector(".sortarrow").textContent).toBe("▼");
  });

  it("switches views from the sidebar and the menu toggle", () => {
    click($('.sb-link[data-view="clients"]'));
    expect($('.view[data-view="clients"]').hidden).toBe(false);
    expect($('.view[data-view="orders"]').hidden).toBe(true);
    expect($("#page-title").textContent).toBe("Clientes");
    expect($('.sb-link[data-view="clients"]').classList.contains("active")).toBe(true);

    click($("#menu-toggle"));
    expect(root.querySelector(".sidebar").classList.contains("show")).toBe(true);
    click($('.sb-link[data-view="orders"]')); // switchView clears the drawer
    expect(root.querySelector(".sidebar").classList.contains("show")).toBe(false);
  });

  it("filters orders by the name box and shows the empty state for no matches", () => {
    input($("#o-name"), "cardoso");
    expect($("#orders-body").querySelectorAll("tr")).toHaveLength(1);

    input($("#o-name"), "zzz");
    expect($("#orders-body").querySelectorAll("tr")).toHaveLength(0);
    expect($("#orders-empty").classList.contains("show")).toBe(true);
    expect($("#orders-table").hidden).toBe(true);
    expect($("#orders-count").textContent).toBe("0 pedidos · R$ 0,00");
  });

  it("drives the status multi-select: open, single, multiple, clear, apply", () => {
    click($("#status-trigger"));
    expect($("#status-pop").classList.contains("open")).toBe(true);
    expect($("#status-pop").querySelectorAll(".opt")).toHaveLength(10);

    click($("#status-trigger")); // clicking the trigger again closes it
    expect($("#status-pop").classList.contains("open")).toBe(false);
    click($("#status-trigger")); // reopen to continue

    click($('#status-pop .opt[data-st="in_production"]'));
    expect($("#status-trigger .val").textContent).toBe(STATUS_LABELS.in_production);
    expect($("#orders-body").querySelectorAll("tr")).toHaveLength(1);

    click($('#status-pop .opt[data-st="delivered"]'));
    expect($("#status-trigger .val").textContent).toBe("status selecionados");
    expect($("#status-trigger .pillnum").hidden).toBe(false);
    expect($("#status-trigger .pillnum").textContent).toBe("2");

    click($('#status-pop .opt[data-st="in_production"]')); // toggle one back off
    expect($("#status-trigger .val").textContent).toBe(STATUS_LABELS.delivered);

    click($("#status-clear"));
    expect($("#status-trigger .val").textContent).toBe("Todos os status");
    expect($("#status-trigger .pillnum").hidden).toBe(true);

    click($("#status-apply"));
    expect($("#status-pop").classList.contains("open")).toBe(false);
  });

  it("drives the date picker: manual range, nav, preset, apply, clear", () => {
    click($("#date-trigger"));
    expect($("#date-pop").classList.contains("open")).toBe(true);
    // Structural contract the dual-calendar CSS layout depends on.
    expect($("#date-pop").querySelectorAll(".dp-cals > .dp-cal")).toHaveLength(2);
    expect($("#date-pop").querySelectorAll(".dp-cal > .dp-grid")).toHaveLength(2);

    // Build a manual range with `from` starting null, exercising each branch:
    const days = () => $("#date-pop").querySelectorAll(".dp-day[data-d]");
    click(days()[15]); // !from → start
    expect($("#date-pop").classList.contains("open")).toBe(true); // re-render must not close it
    click(days()[20]); // later than from → end (else)
    click(days()[10]); // from && to set → resets to a fresh start
    click(days()[5]); // earlier than from → date < from (else if)
    expect($("#date-pop .dp-readout").textContent).not.toContain("Selecione");

    // navigate both calendars
    click($('#date-pop .dp-nav[data-nav="prev"]'));
    click($('#date-pop .dp-nav[data-nav="next"]'));
    expect($("#date-pop").classList.contains("open")).toBe(true); // nav must not close it

    click($('#date-pop .dp-preset[data-p="30"]'));
    expect($("#date-pop .dp-preset.on").dataset.p).toBe("30");
    expect($("#date-pop").classList.contains("open")).toBe(true); // preset must not close it
    expect($("#date-pop .dp-readout").textContent).toContain("→");

    click($("#dp-apply"));
    expect($("#date-trigger .val").classList.contains("placeholder")).toBe(false);
    expect($("#date-clear").hidden).toBe(false);
    // "Últimos 30 dias" → 17 May–15 Jun 2026 keeps several orders in range
    expect($("#orders-body").querySelectorAll("tr").length).toBeGreaterThan(0);

    click($("#date-trigger")); // reopen
    click($("#dp-clear"));
    expect($("#date-pop .dp-readout").textContent).toContain("Selecione o período");
  });

  it("closes the open picker when the trigger is clicked again, and clears via the inline x", () => {
    click($("#date-trigger"));
    click($('#date-pop .dp-preset[data-p="today"]'));
    click($("#dp-apply"));
    expect($("#date-clear").hidden).toBe(false);

    click($("#date-trigger")); // open
    click($("#date-trigger")); // same trigger → close
    expect($("#date-pop").classList.contains("open")).toBe(false);

    click($("#date-clear")); // inline clear commits "any date"
    expect($("#date-clear").hidden).toBe(true);
    expect($("#date-trigger .val").textContent).toBe("Qualquer data");
  });

  it("applies a single picked day as a one-day range", () => {
    click($("#date-trigger"));
    click($("#date-pop").querySelectorAll(".dp-day[data-d]")[14]); // one day → from set, to null
    click($("#dp-apply"));
    expect($("#date-clear").hidden).toBe(false);
    expect($("#date-trigger .val").textContent).not.toContain("–"); // single day, no range dash
  });

  it("sorts orders and clients columns, toggling direction both ways", () => {
    const dateTh = $('#orders-table th[data-key="date"]'); // default key, desc
    click(dateTh); // same key: desc → asc
    expect(dateTh.querySelector(".sortarrow").textContent).toBe("▲");
    click(dateTh); // same key: asc → desc
    expect(dateTh.querySelector(".sortarrow").textContent).toBe("▼");
    click($('#orders-table th[data-key="client"]')); // new key → asc (client special-case)
    click($('#orders-table th[data-key="total"]')); // new non-client key → desc
    click($('#orders-table th[data-key="status"]')); // new key → desc

    click($('.sb-link[data-view="clients"]'));
    const nameTh = $('#clients-table th[data-key="name"]'); // default key, asc
    click(nameTh); // same key: asc → desc
    expect(nameTh.querySelector(".sortarrow").textContent).toBe("▼");
    click(nameTh); // same key: desc → asc
    expect(nameTh.querySelector(".sortarrow").textContent).toBe("▲");
    click($('#clients-table th[data-key="orders"]')); // new key → asc
    expect($('#clients-table th[data-key="orders"]').querySelector(".sortarrow").textContent).toBe("▲");
  });

  it("mirrors the global search into whichever view is active", () => {
    input($("#gsearch"), "bruno");
    expect($("#o-name").value).toBe("bruno");
    expect($("#orders-body").querySelectorAll("tr")).toHaveLength(1);

    click($('.sb-link[data-view="clients"]'));
    input($("#gsearch"), "carla");
    expect($("#c-q").value).toBe("carla");
    expect($("#clients-body").querySelectorAll("tr")).toHaveLength(1);
  });

  it("clears every order filter at once", () => {
    input($("#o-name"), "ana");
    click($("#status-trigger"));
    click($('#status-pop .opt[data-st="awaiting_payment"]'));
    click($("#o-clear"));
    expect($("#o-name").value).toBe("");
    expect($("#status-trigger .val").textContent).toBe("Todos os status");
    expect($("#orders-body").querySelectorAll("tr")).toHaveLength(5);
  });

  it("selects rows and shows state-aware bulk chips, including the empty message", () => {
    click($('[data-check="PG-202605300004"]')); // delivered → no manual action
    expect($("#bulkbar").hidden).toBe(false);
    expect($("#bulk-actions").textContent).toContain("Nenhuma ação");
    expect($("#o-checkall").classList.contains("ind")).toBe(true);

    click($('[data-check="PG-202606130002"]')); // + payment_confirmed → to_production appears
    expect($("#bulk-actions").querySelector('[data-act="to_production"]')).not.toBeNull();
    expect($("#bulk-n").textContent).toBe("2");

    click($('[data-check="PG-202606130002"]')); // click again → deselects that row
    expect($("#bulk-n").textContent).toBe("1");
  });

  it("applies a non-destructive bulk transition with a toast", () => {
    click($('[data-check="PG-202606130002"]')); // payment_confirmed
    click($('[data-check="PG-202606110003"]')); // in_production → production target stays valid
    click($("#bulk-actions").querySelector('[data-act="to_production"]'));
    expect($("#toasts").querySelector(".toast-ok")).not.toBeNull();
    expect($("#toasts").textContent).toContain("atualizado");
  });

  it("confirms before cancelling and respects a declined confirm", () => {
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false);
    click($('[data-check="PG-202606140001"]')); // awaiting_payment → cancel available
    click($("#bulk-actions").querySelector('[data-act="cancel"]'));
    expect(confirmSpy).toHaveBeenCalledOnce();
    expect($("#toasts").querySelector(".toast")).toBeNull(); // declined → nothing happened

    confirmSpy.mockReturnValue(true);
    click($("#bulk-actions").querySelector('[data-act="cancel"]'));
    expect($("#toasts").querySelector(".toast-warn")).not.toBeNull();
  });

  it("ignores clicks on the bulk bar background and clears the selection", () => {
    click($('[data-check="PG-202606140001"]'));
    click($("#bulk-actions")); // not a chip → no-op
    expect($("#bulkbar").hidden).toBe(false);
    click($("#bulk-clear"));
    expect($("#bulkbar").hidden).toBe(true);
  });

  it("select-all toggles the whole filtered set on and off", () => {
    click($("#o-checkall"));
    expect($("#orders-body").querySelectorAll("tr.sel-row")).toHaveLength(5);
    expect($("#o-checkall").classList.contains("on")).toBe(true);
    click($("#o-checkall"));
    expect($("#orders-body").querySelectorAll("tr.sel-row")).toHaveLength(0);
  });

  it("opens an order by forwarding a row click to its detail link", () => {
    const open = vi.spyOn(window.HTMLElement.prototype, "click").mockImplementation(() => {});
    click($("#orders-body tr td:nth-child(2)"));
    expect(open).toHaveBeenCalledTimes(1);
    open.mockRestore();
  });

  it("does not double-open when the order number link itself is clicked", () => {
    const open = vi.spyOn(window.HTMLElement.prototype, "click").mockImplementation(() => {});
    click($("#orders-body tr a.cell-link"));
    expect(open).not.toHaveBeenCalled();
    open.mockRestore();
  });

  it("ignores order-table clicks that land outside a row", () => {
    const open = vi.spyOn(window.HTMLElement.prototype, "click").mockImplementation(() => {});
    click($("#orders-body"));
    expect(open).not.toHaveBeenCalled();
    open.mockRestore();
  });

  it("flashes a client row on click", () => {
    const animate = vi.spyOn(window.HTMLElement.prototype, "animate");
    click($("#clients-body tr"));
    expect(animate).toHaveBeenCalled();
  });

  it("closes popovers on an outside click and on Escape", () => {
    click($("#status-trigger"));
    expect($("#status-pop").classList.contains("open")).toBe(true);
    document.body.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    expect($("#status-pop").classList.contains("open")).toBe(false);

    click($("#status-trigger"));
    document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape" }));
    expect($("#status-pop").classList.contains("open")).toBe(false);
    document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter" })); // non-Escape → ignored
  });

  it("rewrites the production report link with the active period on click", () => {
    const link = $("#gen-production");
    // Cancelable so preventDefault actually suppresses jsdom's link navigation.
    const followLink = () => link.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
    link.addEventListener("click", (e) => e.preventDefault());

    followLink(); // no period applied yet → base path
    expect(link.getAttribute("href")).toBe("/admin/relatorio-producao");

    click($("#date-trigger"));
    click($('#date-pop .dp-preset[data-p="today"]'));
    click($("#dp-apply"));
    followLink();
    expect(link.getAttribute("href")).toContain("de=");
    expect(link.getAttribute("href")).toContain("ate=");
  });

  it("auto-dismisses a toast after its timeout", () => {
    vi.useFakeTimers();
    try {
      click($('[data-check="PG-202606130002"]'));
      click($("#bulk-actions").querySelector('[data-act="to_production"]'));
      expect($("#toasts").querySelector(".toast")).not.toBeNull();
      vi.advanceTimersByTime(3400);
      expect($("#toasts .toast").classList.contains("toast-leaving")).toBe(true);
      vi.advanceTimersByTime(320);
      expect($("#toasts").querySelector(".toast")).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });
});
