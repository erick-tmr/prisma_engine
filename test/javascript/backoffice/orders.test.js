import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  ACTIONS, availableActions, bulkChipsHtml, bulkFormBody, bulkToastMessage, confirmText,
  csrfHeader, escapeHtml, initOrders, plural, skippedLabelsMessage, tallyOutcomes
} from "../../../app/javascript/backoffice/orders.js";

const TODAY = new Date(2026, 5, 15);
const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
const type = (el, value) => {
  el.value = value;
  el.dispatchEvent(new window.Event("input", { bubbles: true }));
};

const row = (number, status) => `
  <tr data-order="${number}" data-status="${status}">
    ${status === "merged" ? '<td class="checkcol"></td>'
      : `<td class="checkcol"><span class="rowcheck" data-check="${number}" role="checkbox"></span></td>`}
    <td><a class="cell-link" href="/admin/pedidos/${number}">${number}</a></td>
    <td class="client">cliente</td>
  </tr>`;

const markup = (rows) => `
  <div class="app" data-list="orders" data-bulk-url="/admin/pedidos/lote" data-print-url="/admin/etiquetas/impressao">
    <aside data-sidebar></aside>
    <button id="menu-toggle" type="button"></button>
    <input id="o-name" name="q" data-filter="q" type="text">
    <div class="f-trigger" id="date-trigger" data-pop data-de="" data-ate="">
      <button id="date-clear" type="button" hidden></button>
    </div>
    <div class="pop dp" id="date-pop"></div>
    <div class="f-trigger" id="status-trigger" data-pop></div>
    <div class="pop" id="status-pop">
      <div class="opt" data-st="shipped"></div>
      <div class="opt" data-st="delivered"></div>
      <div class="pop-foot">
        <button id="status-clear" type="button"></button>
        <button id="status-apply" type="button"></button>
      </div>
    </div>
    <div class="bulkbar" id="bulkbar" hidden>
      <b id="bulk-n">0</b>
      <button id="bulk-clear" type="button"></button>
      <div id="bulk-actions"></div>
      <button id="bulk-print" type="button" hidden></button>
    </div>
    <span data-part="count">count</span>
    <div data-part="table">
      <table><thead><tr><th><span class="rowcheck" id="o-checkall" role="checkbox"></span></th></tr></thead>
        <tbody id="orders-body">${rows}</tbody>
      </table>
    </div>
  </div>
  <div class="toasts" id="toasts"></div>`;

let app;

const start = (rows = "") => {
  document.body.innerHTML = markup(rows);
  document.head.innerHTML = `<meta name="csrf-token" content="test-token">`;
  app = initOrders(document.querySelector(".app"), TODAY);
  return app;
};

beforeEach(() => {
  window.history.pushState({}, "", "/admin");
  vi.spyOn(window, "fetch").mockResolvedValue({
    ok: true,
    text: async () => `<span data-part="count">count</span><div data-part="table"><tbody id="orders-body"></tbody></div>`,
    json: async () => ({ results: [] })
  });
});

afterEach(() => {
  app?.destroy();
  app = null;
  document.body.innerHTML = "";
  vi.restoreAllMocks();
  vi.useRealTimers();
  window.history.pushState({}, "", "/");
});

describe("pure helpers", () => {
  it("escapes markup and handles nullish", () => {
    expect(escapeHtml(`<b>&"'`)).toBe("&lt;b&gt;&amp;&quot;&#39;");
    expect(escapeHtml(null)).toBe("");
  });

  it("agrees the noun with the count", () => {
    expect(plural(1, "pedido", "pedidos")).toBe("pedido");
    expect(plural(2, "pedido", "pedidos")).toBe("pedidos");
  });

  it("offers only the actions the selection can actually take", () => {
    expect(availableActions([ "payment_confirmed", "payment_confirmed", "delivered" ]))
      .toEqual([ { action: ACTIONS[0], count: 2 } ]);
    expect(availableActions([ "delivered" ])).toEqual([]);
  });

  it("renders chips, or says there is nothing to do", () => {
    expect(bulkChipsHtml([])).toContain("Nenhuma ação disponível");

    const html = bulkChipsHtml(availableActions([ "awaiting_payment" ]));
    expect(html).toContain('data-act="cancel"');
    expect(html).toContain("danger");
    expect(html).toContain('<span class="cnt">1</span>');
  });

  it("pluralizes the cancel confirmation", () => {
    expect(confirmText(1)).toContain("1 pedido?");
    expect(confirmText(3)).toContain("3 pedidos?");
  });

  it("builds the bulk form body and reads the csrf token", () => {
    expect(bulkFormBody("issue_label", [ "PG-1", "PG-2" ]).toString())
      .toBe("event=issue_label&order_numbers%5B%5D=PG-1&order_numbers%5B%5D=PG-2");

    expect(csrfHeader(document)).toEqual({ "X-CSRF-Token": "" });
    document.head.innerHTML = `<meta name="csrf-token" content="abc">`;
    expect(csrfHeader(document)).toEqual({ "X-CSRF-Token": "abc" });
  });

  it("summarizes the outcomes of a bulk run", () => {
    const counts = tallyOutcomes([ { outcome: "done" }, { outcome: "done" }, { outcome: "skipped" } ]);
    expect(counts).toEqual({ done: 2, queued: 0, skipped: 1 });
    expect(bulkToastMessage(counts, "Emitir")).toBe("<b>Emitir</b>: 2 atualizados, 1 ignorado.");
    expect(bulkToastMessage({ done: 0, queued: 1, skipped: 0 }, "X")).toContain("1 enfileirado");
  });

  it("pluralizes skipped labels", () => {
    expect(skippedLabelsMessage(1)).toContain("1 etiqueta ignorada");
    expect(skippedLabelsMessage(2)).toContain("2 etiquetas ignoradas");
  });
});

describe("selection", () => {
  const rows = row("PG-1", "payment_confirmed") + row("PG-2", "in_production") + row("PG-3", "merged");

  it("ticks a row and reveals the bulk bar with its actions", () => {
    start(rows);
    click(document.querySelector('[data-check="PG-1"]'));

    expect(document.querySelector("#bulkbar").hidden).toBe(false);
    expect(document.querySelector("#bulk-n").textContent).toBe("1");
    expect(document.querySelector("#bulk-actions").innerHTML).toContain('data-act="to_components"');
    expect(document.querySelector('tr[data-order="PG-1"]').classList.contains("sel-row")).toBe(true);
  });

  it("untickes a row it already had", () => {
    start(rows);
    click(document.querySelector('[data-check="PG-1"]'));
    click(document.querySelector('[data-check="PG-1"]'));

    expect(document.querySelector("#bulkbar").hidden).toBe(true);
  });

  it("select-all takes the page, skipping consolidated rows", () => {
    start(rows);
    click(document.querySelector("#o-checkall"));

    expect(document.querySelector("#bulk-n").textContent).toBe("2");
    expect(document.querySelector("#o-checkall").classList.contains("on")).toBe(true);
  });

  it("select-all clears the page when it is already fully ticked", () => {
    start(rows);
    click(document.querySelector("#o-checkall"));
    click(document.querySelector("#o-checkall"));

    expect(document.querySelector("#bulkbar").hidden).toBe(true);
  });

  it("shows the indeterminate state for a partial page", () => {
    start(rows);
    click(document.querySelector('[data-check="PG-1"]'));

    expect(document.querySelector("#o-checkall").classList.contains("ind")).toBe(true);
  });

  it("remembers a selection whose row has left the page", async () => {
    start(rows);
    click(document.querySelector('[data-check="PG-2"]'));
    expect(document.querySelector("#bulk-actions").innerHTML).toContain('data-act="issue_label"');

    await app.table.set({ page: 2 });

    expect(document.querySelector("#bulk-n").textContent).toBe("1");
    expect(document.querySelector("#bulk-actions").innerHTML).toContain('data-act="issue_label"');
  });

  it("clears everything from the bulk bar", () => {
    start(rows);
    click(document.querySelector("#o-checkall"));
    click(document.querySelector("#bulk-clear"));

    expect(document.querySelector("#bulkbar").hidden).toBe(true);
  });

  it("offers the print button only when a label is ready", () => {
    start(row("PG-9", "label_issued") + rows);

    click(document.querySelector('[data-check="PG-1"]'));
    expect(document.querySelector("#bulk-print").hidden).toBe(true);

    click(document.querySelector('[data-check="PG-9"]'));
    expect(document.querySelector("#bulk-print").hidden).toBe(false);
  });

  it("opens the order when the row itself is clicked", () => {
    start(rows);
    const link = document.querySelector('tr[data-order="PG-1"] a.cell-link');
    const spy = vi.spyOn(link, "click");

    click(document.querySelector('tr[data-order="PG-1"] td.client'));
    expect(spy).toHaveBeenCalledOnce();
  });
});

describe("filters", () => {
  it("searches as you type and reflects it in the url", async () => {
    vi.useFakeTimers();
    start();

    type(document.querySelector("#o-name"), "ana");
    await vi.advanceTimersByTimeAsync(300);

    expect(window.fetch).toHaveBeenCalledWith("/admin?q=ana", expect.anything());
    expect(window.location.search).toBe("?q=ana");
  });

  it("ticks statuses in the popover and sends them all", async () => {
    start();
    click(document.querySelector("#status-trigger"));
    expect(document.querySelector("#status-pop").classList.contains("open")).toBe(true);

    click(document.querySelector('[data-st="shipped"]'));
    await vi.waitFor(() => expect(window.location.search).toBe("?status%5B%5D=shipped"));

    click(document.querySelector('[data-st="delivered"]'));
    await vi.waitFor(() =>
      expect(window.location.search).toBe("?status%5B%5D=shipped&status%5B%5D=delivered"));
  });

  it("clears the statuses and closes the popover on apply", async () => {
    start();
    click(document.querySelector("#status-trigger"));
    click(document.querySelector('[data-st="shipped"]'));
    await vi.waitFor(() => expect(window.location.search).toContain("shipped"));

    click(document.querySelector("#status-clear"));
    await vi.waitFor(() => expect(window.location.search).toBe(""));

    click(document.querySelector("#status-apply"));
    expect(document.querySelector("#status-pop").classList.contains("open")).toBe(false);
  });

  it("toggles the status popover shut when the trigger is clicked twice", () => {
    start();
    click(document.querySelector("#status-trigger"));
    click(document.querySelector("#status-trigger"));
    expect(document.querySelector("#status-pop").classList.contains("open")).toBe(false);
  });

  it("picks a period from the calendar and applies it", async () => {
    start();
    click(document.querySelector("#date-trigger"));
    expect(document.querySelector("#date-pop").classList.contains("open")).toBe(true);

    click(document.querySelector('.dp-preset[data-p="today"]'));
    click(document.querySelector("#dp-apply"));

    await vi.waitFor(() =>
      expect(window.location.search).toBe("?de=2026-06-15&ate=2026-06-15"));
  });

  it("clears the committed period from the trigger", async () => {
    start();
    document.querySelector("#date-trigger").dataset.de = "2026-06-01";

    click(document.querySelector("#date-clear"));
    await vi.waitFor(() => expect(window.fetch).toHaveBeenCalledWith("/admin", expect.anything()));
  });

  it("walks months and clears the draft range inside the popover", () => {
    start();
    click(document.querySelector("#date-trigger"));

    click(document.querySelector('.dp-nav[data-nav="prev"]'));
    expect(document.querySelector("#date-pop").innerHTML).toContain("Maio 2026");

    click(document.querySelector(".dp-day[data-d]"));
    click(document.querySelector("#dp-clear"));
    expect(document.querySelector(".dp-readout").textContent).toContain("Selecione o período");
  });

  it("closes the date popover when the trigger is clicked again", () => {
    start();
    click(document.querySelector("#date-trigger"));
    click(document.querySelector("#date-trigger"));
    expect(document.querySelector("#date-pop").classList.contains("open")).toBe(false);
  });

  it("walks forward a month too", () => {
    start();
    click(document.querySelector("#date-trigger"));
    click(document.querySelector('.dp-nav[data-nav="next"]'));
    expect(document.querySelector("#date-pop").innerHTML).toContain("Agosto 2026");
  });

  it("applies an open-ended range from a single day", async () => {
    start();
    click(document.querySelector("#date-trigger"));
    click(document.querySelector('.dp-day[data-d="2026-06-10"]'));
    click(document.querySelector("#dp-apply"));

    await vi.waitFor(() => expect(window.location.search).toBe("?de=2026-06-10"));
  });

  it("applying an emptied draft drops the period entirely", async () => {
    start();
    document.querySelector("#date-trigger").dataset.de = "2026-06-10";
    click(document.querySelector("#date-trigger"));
    click(document.querySelector("#dp-clear"));
    click(document.querySelector("#dp-apply"));

    await vi.waitFor(() => expect(window.fetch).toHaveBeenCalledWith("/admin", expect.anything()));
  });

  it("seeds the draft range from the committed one when reopened", () => {
    start();
    document.querySelector("#date-trigger").dataset.de = "2026-06-10";
    document.querySelector("#date-trigger").dataset.ate = "2026-06-12";

    click(document.querySelector("#date-trigger"));
    expect(document.querySelector(".dp-readout").textContent).toContain("10 jun 2026");
  });

  it("closes an open popover on an outside click and on Escape", () => {
    start();
    click(document.querySelector("#status-trigger"));
    click(document.body);
    expect(document.querySelector("#status-pop").classList.contains("open")).toBe(false);

    click(document.querySelector("#date-trigger"));
    document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape" }));
    expect(document.querySelector("#date-pop").classList.contains("open")).toBe(false);
  });

  it("repositions an open popover on scroll, and no-ops when none is open", () => {
    start();
    expect(() => window.dispatchEvent(new window.Event("scroll"))).not.toThrow();

    click(document.querySelector("#status-trigger"));
    window.dispatchEvent(new window.Event("resize"));
    expect(document.querySelector("#status-pop").style.top).not.toBe("");
  });
});

describe("bulk actions", () => {
  const rows = row("PG-1", "payment_confirmed") + row("PG-2", "in_production");

  it("posts the eligible numbers and toasts the outcome", async () => {
    window.fetch.mockResolvedValue({
      ok: true,
      text: async () => `<span data-part="count">c</span><div data-part="table"></div>`,
      json: async () => ({ results: [ { number: "PG-1", status: "awaiting_components", outcome: "done" } ] })
    });
    start(rows);
    click(document.querySelector("#o-checkall"));
    click(document.querySelector('[data-act="to_components"]'));

    await vi.waitFor(() => expect(document.querySelector("#toasts .toast")).not.toBeNull());
    const [ url, options ] = window.fetch.mock.calls.find(([ u ]) => u === "/admin/pedidos/lote");
    expect(url).toBe("/admin/pedidos/lote");
    expect(options.body.toString()).toBe("event=to_components&order_numbers%5B%5D=PG-1");
    expect(document.querySelector("#toasts .toast").textContent).toContain("1 atualizado");
  });

  it("asks before cancelling and backs off when refused", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(false);
    start(row("PG-5", "awaiting_payment"));
    click(document.querySelector("#o-checkall"));
    click(document.querySelector('[data-act="cancel"]'));

    expect(window.confirm).toHaveBeenCalled();
    expect(window.fetch).not.toHaveBeenCalledWith("/admin/pedidos/lote", expect.anything());
  });

  it("cancels once the operator confirms, and warns rather than cheers", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true);
    window.fetch.mockResolvedValue({
      ok: true,
      text: async () => `<span data-part="count">c</span><div data-part="table"></div>`,
      json: async () => ({ results: [ { number: "PG-5", status: "cancelled", outcome: "done" } ] })
    });

    start(row("PG-5", "awaiting_payment"));
    click(document.querySelector("#o-checkall"));
    click(document.querySelector('[data-act="cancel"]'));

    await vi.waitFor(() => expect(document.querySelector("#toasts .toast")).not.toBeNull());
    expect(document.querySelector("#toasts .toast").classList.contains("toast-warn")).toBe(true);
  });

  it("warns when the bulk request fails", async () => {
    window.fetch.mockRejectedValue(new Error("boom"));
    start(rows);
    click(document.querySelector("#o-checkall"));
    click(document.querySelector('[data-act="to_components"]'));

    await vi.waitFor(() =>
      expect(document.querySelector("#toasts .toast").textContent).toContain("Não foi possível aplicar"));
  });

  it("ignores a click that lands outside a chip", () => {
    start(rows);
    click(document.querySelector("#o-checkall"));
    expect(() => click(document.querySelector("#bulk-actions"))).not.toThrow();
  });

  it("clears its toast once the operator has had time to read it", async () => {
    vi.useFakeTimers();
    window.fetch.mockRejectedValue(new Error("boom"));
    start(rows);
    click(document.querySelector("#o-checkall"));
    click(document.querySelector('[data-act="to_components"]'));

    await vi.advanceTimersByTimeAsync(0);
    expect(document.querySelector("#toasts .toast")).not.toBeNull();

    await vi.advanceTimersByTimeAsync(3400);
    expect(document.querySelector("#toasts .toast").classList.contains("toast-leaving")).toBe(true);

    await vi.advanceTimersByTimeAsync(320);
    expect(document.querySelector("#toasts .toast")).toBeNull();
  });
});

describe("printing labels", () => {
  it("opens the sheet and reports what was skipped", async () => {
    const open = vi.spyOn(window, "open").mockImplementation(() => {});
    window.URL.createObjectURL = vi.fn(() => "blob:x");
    window.fetch.mockResolvedValue({
      ok: true,
      blob: async () => new window.Blob([ "pdf" ]),
      headers: { get: () => "2" }
    });

    start(row("PG-9", "label_issued"));
    click(document.querySelector("#o-checkall"));
    click(document.querySelector("#bulk-print"));

    await vi.waitFor(() => expect(open).toHaveBeenCalledWith("blob:x", "_blank"));
    expect(document.querySelector("#toasts .toast").textContent).toContain("2 etiquetas ignoradas");
  });

  it("says so when the server has nothing ready", async () => {
    window.fetch.mockResolvedValue({ ok: false });
    start(row("PG-9", "label_issued"));
    click(document.querySelector("#o-checkall"));
    click(document.querySelector("#bulk-print"));

    await vi.waitFor(() =>
      expect(document.querySelector("#toasts .toast").textContent).toContain("Nenhuma etiqueta pronta"));
  });

  it("warns when the print request fails", async () => {
    window.fetch.mockRejectedValue(new Error("boom"));
    start(row("PG-9", "label_issued"));
    click(document.querySelector("#o-checkall"));
    click(document.querySelector("#bulk-print"));

    await vi.waitFor(() =>
      expect(document.querySelector("#toasts .toast").textContent).toContain("Não foi possível gerar"));
  });

  it("does nothing when no printable order is selected", () => {
    start(row("PG-1", "payment_confirmed"));
    click(document.querySelector("#o-checkall"));
    click(document.querySelector("#bulk-print"));

    expect(window.fetch).not.toHaveBeenCalledWith("/admin/etiquetas/impressao", expect.anything());
  });
});
