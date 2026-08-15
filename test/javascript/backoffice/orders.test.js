import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  ACTIONS, BATCH_HOLD_MS, BATCH_KEY, BULK_THROTTLE_MS, availableActions, batchProgress, bulkChipsHtml,
  bulkFormBody, bulkToastMessage, confirmText, csrfHeader, escapeHtml, initOrders, partitionThrottled,
  plural, readBatch, readSettledAt, skippedLabelsMessage, stampSettled, tallyOutcomes, throttleKey,
  throttledMessage, writeBatch, BATCH_TTL_MS
} from "../../../app/javascript/backoffice/orders.js";
import { POLL_STEPS } from "../../../app/javascript/backoffice/label_feedback.js";

const TODAY = new Date(2026, 5, 15);
const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
const type = (el, value) => {
  el.value = value;
  el.dispatchEvent(new window.Event("input", { bubbles: true }));
};

const row = (number, status, corState = "idle") => `
  <tr data-order="${number}" data-status="${status}"${corState === "queued" || corState === "running" ? ' class="is-busy"' : ""}>
    ${status === "merged" ? '<td class="checkcol"></td>'
      : `<td class="checkcol"><span class="rowcheck" data-check="${number}" role="checkbox"></span></td>`}
    <td><a class="cell-link" href="/admin/pedidos/${number}">${number}</a></td>
    <td class="client">cliente</td>
    <td class="corcell">
      <div data-part="correios-${number}" data-cor-state="${corState}">
        ${corState === "failed" ? `<button class="proc-retry" data-retry="${number}" data-retry-url="/admin/etiquetas/${number}"></button>` : ""}
      </div>
    </td>
  </tr>`;

const procbar = (attrs = {}) => {
  const { total = 0, settled = 0, failed = 0, inFlight = 0, percent = 0, hidden = false } = attrs;
  return `<div class="procbar" data-part="procbar" data-total="${total}" data-settled="${settled}"
    data-failed="${failed}" data-in-flight="${inFlight}" data-percent="${percent}"${hidden ? " hidden" : ""}><div class="pb-fill"></div></div>`;
};

const markup = (rows, bar = procbar()) => `
  <div class="app" data-list="orders" data-bulk-url="/admin/pedidos/lote" data-print-url="/admin/etiquetas/impressao"
       data-feedback-url="/admin/pedidos/correios">
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
      <div id="bulk-actions" data-issuing-label="Emitindo etiquetas…"></div>
      <button id="bulk-print" type="button" hidden></button>
    </div>
    ${bar}
    <span data-part="count">count</span>
    <div data-part="table">
      <table><thead><tr><th><span class="rowcheck" id="o-checkall" role="checkbox"></span></th></tr></thead>
        <tbody id="orders-body">${rows}</tbody>
      </table>
    </div>
  </div>
  <div class="toasts" id="toasts"></div>`;

let app;

const start = (rows = "", bar = procbar()) => {
  document.body.innerHTML = markup(rows, bar);
  document.head.innerHTML = `<meta name="csrf-token" content="test-token">`;
  app = initOrders(document.querySelector(".app"), TODAY);
  return app;
};

beforeEach(() => {
  window.sessionStorage.clear();
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

describe("bulk throttle helpers", () => {
  it("keys a stamp by action and order number", () => {
    expect(throttleKey("issue_label", "PG-1")).toBe("issue_label:PG-1");
  });

  it("holds back numbers stamped inside the window and releases the rest", () => {
    const now = 1_000_000;
    const sentAt = new Map([
      [ "issue_label:PG-1", now - 1_000 ],
      [ "issue_label:PG-2", now - BULK_THROTTLE_MS ],
      [ "to_components:PG-3", now - 1_000 ]
    ]);

    const { fresh, throttled } = partitionThrottled([ "PG-1", "PG-2", "PG-3", "PG-4" ], "issue_label", sentAt, now);

    expect(throttled).toEqual([ "PG-1" ]);
    expect(fresh).toEqual([ "PG-2", "PG-3", "PG-4" ]);
  });

  it("counts the held-back orders in pt-BR", () => {
    expect(throttledMessage(1)).toBe("1 pedido já enviado nos últimos 60s. A fila ainda está processando, aguarde.");
    expect(throttledMessage(3)).toContain("3 pedidos já enviados");
  });
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
      .toEqual([ { action: ACTIONS[0], count: 2 }, { action: ACTIONS[3], count: 2 } ]);
    expect(availableActions([ "delivered" ])).toEqual([]);
  });

  it("withholds bulk cancel once the package is out, until it comes back to us", () => {
    expect(availableActions([ "shipped" ])).toEqual([]);
    expect(availableActions([ "delivery_issue" ])).toEqual([]);
    expect(availableActions([ "returned" ])).toEqual([ { action: ACTIONS[3], count: 1 } ]);
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

  const bulkCalls = () => window.fetch.mock.calls.filter(([ u ]) => u === "/admin/pedidos/lote").length;
  const lastToast = () => [ ...document.querySelectorAll("#toasts .toast") ].at(-1).textContent;

  it("throttles a repeat of the same action on the same order", async () => {
    window.fetch.mockResolvedValue({
      ok: true,
      text: async () => `<span data-part="count">c</span><div data-part="table"></div>`,
      json: async () => ({ results: [ { number: "PG-1", status: "payment_confirmed", outcome: "queued" } ] })
    });
    start(rows);
    click(document.querySelector("#o-checkall"));
    click(document.querySelector('[data-act="to_components"]'));
    await vi.waitFor(() => expect(document.querySelector("#toasts .toast")).not.toBeNull());
    const sent = bulkCalls();

    click(document.querySelector('[data-act="to_components"]'));

    await vi.waitFor(() => expect(lastToast()).toContain("1 pedido já enviado"));
    expect(bulkCalls()).toBe(sent);
    expect(lastToast()).toContain("nos últimos 60s");
  });

  it("lets a failed action be retried immediately", async () => {
    window.fetch.mockRejectedValue(new Error("boom"));
    start(rows);
    click(document.querySelector("#o-checkall"));
    click(document.querySelector('[data-act="to_components"]'));
    await vi.waitFor(() => expect(lastToast()).toContain("Não foi possível aplicar a ação"));
    const failed = bulkCalls();

    click(document.querySelector('[data-act="to_components"]'));

    await vi.waitFor(() => expect(bulkCalls()).toBe(failed + 1));
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

describe("Correios feedback", () => {
  it("remembers the batch a bulk emit queued and starts polling for it", async () => {
    window.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({ results: [
        { number: "PG-1", outcome: "queued", status: "in_production" },
        { number: "PG-2", outcome: "skipped", status: "delivered" }
      ] }),
      text: async () => `<div data-part="table"><tbody id="orders-body"></tbody></div>`
    });

    start(row("PG-1", "in_production") + row("PG-2", "in_production"));
    click(document.querySelector("#o-checkall"));
    click(document.querySelector('[data-act="issue_label"]'));

    await vi.waitFor(() => expect(readBatch(window.sessionStorage)).toEqual(new Set([ "PG-1" ])));
    expect(app.feedback.running).toBe(true);
  });

  it("starts a fresh batch when the previous one already settled", async () => {
    writeBatch(window.sessionStorage, new Set([ "PG-OLD" ]));
    window.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({ results: [ { number: "PG-1", outcome: "queued", status: "in_production" } ] }),
      text: async () => `<div data-part="table"><tbody id="orders-body"></tbody></div>`
    });

    start(row("PG-1", "in_production"), procbar({ total: 1, settled: 1 }));
    click(document.querySelector('[data-check="PG-1"]'));
    click(document.querySelector('[data-act="issue_label"]'));

    await vi.waitFor(() => expect(readBatch(window.sessionStorage)).toEqual(new Set([ "PG-1" ])));
  });

  it("folds into the running batch when the previous one is still working", async () => {
    writeBatch(window.sessionStorage, new Set([ "PG-OLD" ]));
    window.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({ results: [ { number: "PG-1", outcome: "queued", status: "in_production" } ] }),
      text: async () => `<div data-part="table"><tbody id="orders-body"></tbody></div>`
    });

    start(row("PG-1", "in_production"), procbar({ total: 2, settled: 1, inFlight: 1 }));
    click(document.querySelector('[data-check="PG-1"]'));
    click(document.querySelector('[data-act="issue_label"]'));

    await vi.waitFor(() => expect(readBatch(window.sessionStorage)).toEqual(new Set([ "PG-OLD", "PG-1" ])));
  });

  it("resumes polling on load when the server already rendered a busy row", () => {
    start(row("PG-1", "in_production", "running"));
    expect(app.feedback.running).toBe(true);
  });

  it("resumes polling on load to settle a batch left in sessionStorage", () => {
    writeBatch(window.sessionStorage, new Set([ "PG-1" ]));
    start(row("PG-1", "label_issued", "done"));

    expect(app.feedback.running).toBe(true);
  });

  it("stays idle when nothing is in flight and no batch is pending", () => {
    start(row("PG-1", "label_issued", "done"));
    expect(app.feedback.running).toBe(false);
  });

  it("paints the batch strip width from the server-rendered percentage", () => {
    start(row("PG-1", "in_production", "running"), procbar({ total: 4, settled: 1, inFlight: 3, percent: 25 }));
    expect(document.querySelector(".pb-fill").style.width).toBe("25%");
  });

  it("locks the emit chip while the batch is still running", () => {
    start(row("PG-1", "in_production", "running") + row("PG-2", "in_production"),
          procbar({ total: 4, settled: 1, inFlight: 3 }));
    click(document.querySelector("#o-checkall"));

    const chip = document.querySelector('[data-act="issue_label"]');
    expect(chip.disabled).toBe(true);
    expect(chip.textContent).toContain("Emitindo etiquetas…");
    expect(chip.querySelector(".cnt").textContent).toBe("1/4");
  });

  it("refuses to select a row whose label is mid-emission", () => {
    start(row("PG-1", "in_production", "running") + row("PG-2", "in_production"));

    click(document.querySelector('[data-check="PG-1"]'));
    expect(app.selected.size).toBe(0);

    click(document.querySelector("#o-checkall"));
    expect([ ...app.selected.keys() ]).toEqual([ "PG-2" ]);
  });

  it("retries a failed label through the single-order endpoint", async () => {
    start(row("PG-1", "in_production", "failed"));
    click(document.querySelector(".proc-retry"));

    await vi.waitFor(() => expect(window.fetch).toHaveBeenCalledWith("/admin/etiquetas/PG-1", expect.objectContaining({
      method: "POST",
      headers: expect.objectContaining({ "X-CSRF-Token": "test-token" })
    })));
    await vi.waitFor(() => expect(app.feedback.running).toBe(true));
  });

  it("does not navigate to the order when the retry button is clicked", () => {
    start(row("PG-1", "in_production", "failed"));
    const link = document.querySelector("a.cell-link");
    const clicked = vi.spyOn(link, "click");

    click(document.querySelector(".proc-retry"));
    expect(clicked).not.toHaveBeenCalled();
  });

  it("holds back a retry that was already sent moments ago", async () => {
    start(row("PG-1", "in_production", "failed"));
    click(document.querySelector(".proc-retry"));
    await vi.waitFor(() => expect(window.fetch).toHaveBeenCalledTimes(1));

    click(document.querySelector(".proc-retry"));
    await vi.waitFor(() =>
      expect(document.querySelector("#toasts .toast").textContent).toContain("A fila ainda está processando"));
    expect(window.fetch).toHaveBeenCalledTimes(1);
  });

  it("warns and frees the throttle when the retry is rejected", async () => {
    window.fetch.mockResolvedValue({ ok: false, json: async () => ({}) });
    start(row("PG-1", "in_production", "failed"));
    click(document.querySelector(".proc-retry"));

    await vi.waitFor(() =>
      expect(document.querySelector("#toasts .toast").textContent).toContain("Não foi possível reenviar"));
    expect(readBatch(window.sessionStorage).size).toBe(0);
  });

  it("hides the finished strip and forgets the batch after the hold", async () => {
    vi.useFakeTimers();
    writeBatch(window.sessionStorage, new Set([ "PG-1" ]));
    start(row("PG-1", "in_production", "running"), procbar({ total: 1, inFlight: 1 }));
    window.fetch.mockResolvedValue({
      ok: true,
      text: async () => `<div data-part="correios-PG-1" data-cor-state="done"></div>${procbar({ total: 1, settled: 1 })}`
    });

    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);
    expect(readBatch(window.sessionStorage).size).toBe(1);

    // still up a second short of the hold, gone a moment after it
    await vi.advanceTimersByTimeAsync(BATCH_HOLD_MS - 1_000);
    expect(document.querySelector('[data-part="procbar"]').hidden).toBe(false);

    await vi.advanceTimersByTimeAsync(1_001);
    expect(readBatch(window.sessionStorage).size).toBe(0);
    expect(document.querySelector('[data-part="procbar"]').hidden).toBe(true);
  });

  it("hides the finished strip while an unrelated order is still stuck in flight", async () => {
    vi.useFakeTimers();
    writeBatch(window.sessionStorage, new Set([ "PG-1" ]));
    start(row("PG-1", "in_production", "running") + row("PG-9", "in_production", "running"),
      procbar({ total: 1, inFlight: 1 }));
    // once the batch is forgotten the poller stops sending lote, and the server renders the strip hidden
    window.fetch.mockImplementation(async (url) => ({
      ok: true,
      text: async () => `<div data-part="correios-PG-1" data-cor-state="done"></div>` +
        procbar(String(url).includes("lote") ? { total: 1, settled: 1 } : { hidden: true })
    }));

    // PG-9 never settles, so the poller keeps ticking long after our batch is done
    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);
    await vi.advanceTimersByTimeAsync(BATCH_HOLD_MS + 1_000);

    expect(readBatch(window.sessionStorage).size).toBe(0);
    expect(document.querySelector('[data-part="procbar"]').hidden).toBe(true);
  });

  it("keeps the strip up when the batch itself goes back in flight", async () => {
    vi.useFakeTimers();
    writeBatch(window.sessionStorage, new Set([ "PG-1" ]));
    start(row("PG-1", "in_production", "running"), procbar({ total: 1, inFlight: 1 }));
    window.fetch.mockResolvedValue({
      ok: true,
      text: async () => `<div data-part="correios-PG-1" data-cor-state="running"></div>${procbar({ total: 1, inFlight: 1 })}`
    });

    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);
    await vi.advanceTimersByTimeAsync(BATCH_HOLD_MS + 1_000);

    expect(readBatch(window.sessionStorage).size).toBe(1);
    expect(document.querySelector('[data-part="procbar"]').hidden).toBe(false);
  });

  it("reloads the list once the batch settles so finished orders leave a filtered view", async () => {
    vi.useFakeTimers();
    writeBatch(window.sessionStorage, new Set([ "PG-1" ]));
    start(row("PG-1", "in_production", "running"), procbar({ total: 1, inFlight: 1 }));
    window.fetch.mockResolvedValue({
      ok: true,
      text: async () => `<div data-part="correios-PG-1" data-cor-state="done"></div>${procbar({ total: 1, settled: 1 })}`
    });

    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);

    const listReloads = window.fetch.mock.calls.filter(([ url ]) => !String(url).includes("lote"));
    expect(listReloads).toHaveLength(1);
  });

  it("does not reload the list while the batch is still working", async () => {
    vi.useFakeTimers();
    writeBatch(window.sessionStorage, new Set([ "PG-1" ]));
    start(row("PG-1", "in_production", "running"), procbar({ total: 2, settled: 1, inFlight: 1 }));
    window.fetch.mockResolvedValue({
      ok: true,
      text: async () => `<div data-part="correios-PG-1" data-cor-state="running"></div>${procbar({ total: 2, settled: 1, inFlight: 1 })}`
    });

    await vi.advanceTimersByTimeAsync(POLL_STEPS[0] + POLL_STEPS[1]);

    expect(window.fetch.mock.calls.filter(([ url ]) => !String(url).includes("lote"))).toHaveLength(0);
  });

  it("drops settled orders from the selection so the bulk bar stops offering them", async () => {
    vi.useFakeTimers();
    writeBatch(window.sessionStorage, new Set([ "PG-1" ]));
    start(row("PG-1", "in_production"), procbar({ total: 1, inFlight: 1 }));
    click(document.querySelector('[data-check="PG-1"]'));
    expect(document.querySelector("#bulk-n").textContent).toBe("1");

    window.fetch.mockResolvedValue({
      ok: true,
      text: async () => `<div data-part="correios-PG-1" data-cor-state="done"></div>${procbar({ total: 1, settled: 1 })}`
    });
    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);

    expect(document.querySelector("#bulkbar").hidden).toBe(true);
  });

  it("resumes the hold across a reload rather than restarting the two minutes", async () => {
    vi.useFakeTimers();
    writeBatch(window.sessionStorage, new Set([ "PG-1" ]));
    stampSettled(window.sessionStorage, Date.now() - (BATCH_HOLD_MS - 5_000));
    start(row("PG-1", "label_issued", "done"), procbar({ total: 1, settled: 1 }));
    window.fetch.mockResolvedValue({
      ok: true,
      text: async () => `<div data-part="correios-PG-1" data-cor-state="done"></div>${procbar({ total: 1, settled: 1 })}`
    });

    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);
    await vi.advanceTimersByTimeAsync(5_000);

    expect(readBatch(window.sessionStorage).size).toBe(0);
  });

  it("forgets the settle stamp when the batch goes back to work", async () => {
    vi.useFakeTimers();
    writeBatch(window.sessionStorage, new Set([ "PG-1" ]));
    stampSettled(window.sessionStorage, Date.now());
    start(row("PG-1", "in_production", "running"), procbar({ total: 1, inFlight: 1 }));
    window.fetch.mockResolvedValue({
      ok: true,
      text: async () => `<div data-part="correios-PG-1" data-cor-state="running"></div>${procbar({ total: 1, inFlight: 1 })}`
    });

    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);

    expect(readSettledAt(window.sessionStorage)).toBeNull();
  });

  it("gives the finished strip two minutes on screen", () => {
    expect(BATCH_HOLD_MS).toBe(120_000);
  });
});

describe("batch storage", () => {
  it("starts empty when sessionStorage holds nothing or holds junk", () => {
    expect(readBatch(window.sessionStorage)).toEqual(new Set());

    window.sessionStorage.setItem(BATCH_KEY, "{not json");
    expect(readBatch(window.sessionStorage)).toEqual(new Set());
  });

  it("forgets a batch old enough to be abandoned rather than resurrecting it", () => {
    const at = 1_000_000;
    writeBatch(window.sessionStorage, new Set([ "PG-1" ]), at);

    expect(readBatch(window.sessionStorage, at + BATCH_TTL_MS)).toEqual(new Set([ "PG-1" ]));
    expect(readBatch(window.sessionStorage, at + BATCH_TTL_MS + 1)).toEqual(new Set());
  });

  it("discards a batch stored in the older format that carried no timestamp", () => {
    window.sessionStorage.setItem(BATCH_KEY, JSON.stringify([ "PG-1", "PG-2" ]));

    expect(readBatch(window.sessionStorage)).toEqual(new Set());
  });

  it("round-trips a batch through storage", () => {
    writeBatch(window.sessionStorage, new Set([ "PG-1", "PG-2" ]));
    expect(readBatch(window.sessionStorage)).toEqual(new Set([ "PG-1", "PG-2" ]));
  });

  it("survives a storage that refuses to write", () => {
    const storage = { getItem: () => { throw new Error("blocked"); }, setItem: () => { throw new Error("blocked"); } };

    expect(readBatch(storage)).toEqual(new Set());
    expect(() => writeBatch(storage, new Set([ "PG-1" ]))).not.toThrow();
    expect(readSettledAt(storage)).toBeNull();
    expect(stampSettled(storage, 42)).toBe(42);
  });

  it("leaves the settle stamp alone when there is no batch to stamp", () => {
    expect(stampSettled(window.sessionStorage, 42)).toBe(42);
    expect(readSettledAt(window.sessionStorage)).toBeNull();
  });
});

describe("batchProgress", () => {
  it("is null without a strip, or once the strip reports nothing in flight", () => {
    document.body.innerHTML = `<div class="app"></div>`;
    expect(batchProgress(document.querySelector(".app"))).toBeNull();

    document.body.innerHTML = `<div class="app">${procbar({ total: 2, settled: 2 })}</div>`;
    expect(batchProgress(document.querySelector(".app"))).toBeNull();
  });

  it("reports settled over total while a batch runs", () => {
    document.body.innerHTML = `<div class="app">${procbar({ total: 5, settled: 2, inFlight: 3 })}</div>`;
    expect(batchProgress(document.querySelector(".app"))).toEqual({ settled: 2, total: 5 });
  });
});

describe("Correios feedback across a table reload", () => {
  it("restarts polling when a filter change brings a busy row on screen", async () => {
    start(row("PG-1", "label_issued", "done"));
    expect(app.feedback.running).toBe(false);

    window.fetch.mockResolvedValue({
      ok: true,
      text: async () =>
        `<div data-part="table"><tbody id="orders-body">${row("PG-2", "in_production", "running")}</tbody></div>`
    });
    type(document.querySelector("#o-name"), "PG-2");

    await vi.waitFor(() => expect(app.feedback.running).toBe(true));
  });

  it("keeps the strip up while the batch is still moving", async () => {
    vi.useFakeTimers();
    writeBatch(window.sessionStorage, new Set([ "PG-1" ]));
    start(row("PG-1", "in_production", "running"), procbar({ total: 2, settled: 1, inFlight: 1 }));
    window.fetch.mockResolvedValue({
      ok: true,
      text: async () =>
        `<div data-part="correios-PG-1" data-cor-state="running"></div>${procbar({ total: 2, settled: 1, inFlight: 1 })}`
    });

    await vi.advanceTimersByTimeAsync(POLL_STEPS[0] + BATCH_HOLD_MS);

    expect(readBatch(window.sessionStorage).size).toBe(1);
    expect(document.querySelector('[data-part="procbar"]').hidden).toBe(false);
  });
});
