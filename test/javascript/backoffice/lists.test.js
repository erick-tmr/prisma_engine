import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { dismissToasts, initShell } from "../../../app/javascript/backoffice/shell.js";
import { initClients } from "../../../app/javascript/backoffice/clients.js";
import { initReports } from "../../../app/javascript/backoffice/reports.js";
import { initCatalog, navigate } from "../../../app/javascript/backoffice/catalog.js";

const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
const type = (el, value) => {
  el.value = value;
  el.dispatchEvent(new window.Event("input", { bubbles: true }));
};
const choose = (el, value) => {
  el.value = value;
  el.dispatchEvent(new window.Event("change", { bubbles: true }));
};

const shell = (list, inner) => `
  <div class="app" data-list="${list}">
    <aside data-sidebar></aside>
    <button id="menu-toggle" type="button"></button>
    ${inner}
    <span data-part="count">0</span>
    <div data-part="table">${inner.includes("data-part") ? "" : ""}</div>
  </div>
  <div class="toasts"><div data-toast>saved</div></div>`;

let started;

beforeEach(() => {
  started = [];
  window.history.pushState({}, "", "/admin");
  vi.spyOn(window, "fetch").mockResolvedValue({
    text: async () => `<span data-part="count">1</span><div data-part="table"></div>`
  });
});

afterEach(() => {
  started.forEach((t) => t.destroy?.() ?? t.table?.destroy());
  document.body.innerHTML = "";
  vi.restoreAllMocks();
  vi.useRealTimers();
  window.history.pushState({}, "", "/");
});

describe("initShell", () => {
  it("toggles the mobile sidebar", () => {
    document.body.innerHTML = shell("clients", "");
    const root = document.querySelector(".app");
    initShell(root);

    click(root.querySelector("#menu-toggle"));
    expect(root.querySelector("[data-sidebar]").classList.contains("show")).toBe(true);
    click(root.querySelector("#menu-toggle"));
    expect(root.querySelector("[data-sidebar]").classList.contains("show")).toBe(false);
  });

  it("survives a page with no sidebar or toggle", () => {
    document.body.innerHTML = `<div class="app"></div>`;
    expect(() => initShell(document.querySelector(".app"))).not.toThrow();
  });
});

describe("dismissToasts", () => {
  it("clears toasts after the delay", () => {
    vi.useFakeTimers();
    document.body.innerHTML = `<div data-toast>ok</div>`;
    dismissToasts(document, 1000);

    expect(document.querySelector("[data-toast]")).not.toBeNull();
    vi.advanceTimersByTime(1000);
    expect(document.querySelector("[data-toast]")).toBeNull();
  });
});

describe("initClients", () => {
  const markup = `<input id="c-q" name="q" data-filter="q" type="text">`;

  it("filters as you type, once the typing settles", async () => {
    vi.useFakeTimers();
    document.body.innerHTML = shell("clients", markup);
    started.push(initClients(document.querySelector(".app")));

    type(document.querySelector("#c-q"), "an");
    type(document.querySelector("#c-q"), "ana");
    expect(window.fetch).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(300);
    expect(window.fetch).toHaveBeenCalledExactlyOnceWith("/admin?q=ana", expect.anything());
  });

  it("rewinds the search box when the operator goes back", async () => {
    document.body.innerHTML = shell("clients", markup);
    started.push(initClients(document.querySelector(".app")));
    const input = document.querySelector("#c-q");

    input.value = "ana";
    window.history.pushState({}, "", "/admin?q=ana");
    window.dispatchEvent(new window.PopStateEvent("popstate"));
    await vi.waitFor(() => expect(input.value).toBe("ana"));

    window.history.pushState({}, "", "/admin");
    window.dispatchEvent(new window.PopStateEvent("popstate"));
    await vi.waitFor(() => expect(input.value).toBe(""));
  });

  it("opens a client by forwarding the row click to its link", () => {
    document.body.innerHTML = shell("clients", markup);
    document.querySelector("[data-part=table]").innerHTML =
      `<table><tbody><tr data-client="9"><td><a class="cell-link" href="/admin/clientes/9">Ana</a></td><td class="other">SP</td></tr></tbody></table>`;
    started.push(initClients(document.querySelector(".app")));

    const link = document.querySelector("a.cell-link");
    const spy = vi.spyOn(link, "click");
    click(document.querySelector("td.other"));

    expect(spy).toHaveBeenCalledOnce();
  });

  it("ignores clicks outside a client row", () => {
    document.body.innerHTML = shell("clients", markup);
    started.push(initClients(document.querySelector(".app")));

    expect(() => click(document.querySelector("[data-part=count]"))).not.toThrow();
  });
});

describe("initReports", () => {
  it("opens a batch by forwarding the row click to its link", () => {
    document.body.innerHTML = shell("reports", "");
    document.querySelector("[data-part=table]").innerHTML =
      `<table><tbody><tr data-report="12"><td><a class="cell-link" href="/admin/relatorio-producao/12">x</a></td><td class="other">y</td></tr></tbody></table>`;
    started.push(initReports(document.querySelector(".app")));

    const link = document.querySelector("a.cell-link");
    const spy = vi.spyOn(link, "click");
    click(document.querySelector("td.other"));

    expect(spy).toHaveBeenCalledOnce();
  });

  it("ignores clicks outside a batch row", () => {
    document.body.innerHTML = shell("reports", "");
    started.push(initReports(document.querySelector(".app")));
    expect(() => click(document.querySelector("[data-part=count]"))).not.toThrow();
  });
});

describe("initCatalog", () => {
  const markup = `
    <input id="c-q" name="q" data-filter="q" type="text">
    <select id="c-cat" name="cat" data-filter="cat"><option value=""></option><option value="gbc">gbc</option></select>
    <select id="c-status" name="status" data-filter="status"><option value=""></option><option value="draft">draft</option></select>`;

  it("applies a select immediately, without waiting for a debounce", async () => {
    document.body.innerHTML = shell("catalog", markup);
    started.push(initCatalog(document.querySelector(".app")));

    choose(document.querySelector("#c-status"), "draft");
    await vi.waitFor(() => expect(window.fetch).toHaveBeenCalledWith("/admin?status=draft", expect.anything()));
  });

  it("opens a product row, but lets a real link through untouched", () => {
    document.body.innerHTML = shell("catalog", markup);
    document.querySelector("[data-part=table]").innerHTML =
      `<table><tbody><tr data-row data-href="/admin/produtos/x/editar"><td class="cell">y</td><td><a href="/somewhere">link</a></td></tr></tbody></table>`;
    started.push(initCatalog(document.querySelector(".app")));

    const assign = vi.fn();
    vi.spyOn(window, "location", "get").mockReturnValue({ assign });

    click(document.querySelector("td.cell"));
    expect(assign).toHaveBeenCalledWith("/admin/produtos/x/editar");

    assign.mockClear();
    click(document.querySelector('a[href="/somewhere"]'));
    expect(assign).not.toHaveBeenCalled();
  });

  it("ignores clicks that land outside any row", () => {
    document.body.innerHTML = shell("catalog", markup);
    started.push(initCatalog(document.querySelector(".app")));
    expect(() => click(document.querySelector("[data-part=count]"))).not.toThrow();
  });

  it("rewinds every filter control when the operator goes back", async () => {
    document.body.innerHTML = shell("catalog", markup);
    started.push(initCatalog(document.querySelector(".app")));

    window.history.pushState({}, "", "/admin?q=zelda&cat=gbc&status=draft");
    window.dispatchEvent(new window.PopStateEvent("popstate"));

    await vi.waitFor(() => expect(document.querySelector("#c-q").value).toBe("zelda"));
    expect(document.querySelector("#c-cat").value).toBe("gbc");
    expect(document.querySelector("#c-status").value).toBe("draft");
  });
});

describe("navigate", () => {
  it("sends the browser to the given href", () => {
    const assign = vi.fn();
    vi.spyOn(window, "location", "get").mockReturnValue({ assign });
    navigate("/admin/produtos/1/editar");
    expect(assign).toHaveBeenCalledWith("/admin/produtos/1/editar");
  });
});
