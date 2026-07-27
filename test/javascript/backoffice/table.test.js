import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { buildUrl, createTable, debounce, readParams, swapParts } from "../../../app/javascript/backoffice/table.js";

const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));

const results = (label) => `
  <span data-part="count">${label} results</span>
  <div data-part="table">
    <a href="/admin?page=2">2</a>
    <a href="/elsewhere">off-list</a>
  </div>`;

let root;
let tables;

const makeTable = (...args) => {
  const table = createTable(...args);
  tables.push(table);
  return table;
};

beforeEach(() => {
  tables = [];
  window.history.pushState({}, "", "/admin");
  document.body.innerHTML = `<div class="app">${results("first")}</div>`;
  root = document.querySelector(".app");
});

afterEach(() => {
  tables.forEach((table) => table.destroy());
  vi.restoreAllMocks();
  vi.useRealTimers();
  window.history.pushState({}, "", "/");
});

describe("buildUrl", () => {
  it("drops empty values and keeps the bare path when nothing is set", () => {
    expect(buildUrl("/admin", { q: "", page: null, sort: undefined })).toBe("/admin");
  });

  it("serializes scalars and repeats array params", () => {
    expect(buildUrl("/admin", { q: "ana", status: [ "shipped", "delivered" ], page: 2 }))
      .toBe("/admin?q=ana&status%5B%5D=shipped&status%5B%5D=delivered&page=2");
  });
});

describe("readParams", () => {
  it("reads scalars and collects bracketed arrays", () => {
    expect(readParams("?q=ana&status[]=shipped&status[]=delivered&page=2"))
      .toEqual({ q: "ana", status: [ "shipped", "delivered" ], page: "2" });
  });

  it("returns nothing for an empty query string", () => {
    expect(readParams("")).toEqual({});
  });
});

describe("swapParts", () => {
  it("replaces each matching part and ignores parts with no home", () => {
    swapParts(root, `<span data-part="count">second results</span><span data-part="nowhere">x</span>`);

    expect(root.querySelector("[data-part=count]").textContent).toBe("second results");
    expect(root.querySelector("[data-part=nowhere]")).toBeNull();
    expect(root.querySelector("[data-part=table]")).not.toBeNull();
  });
});

describe("debounce", () => {
  it("runs once after the quiet period and can be cancelled", () => {
    vi.useFakeTimers();
    const fn = vi.fn();
    const debounced = debounce(fn, 100);

    debounced("a");
    debounced("b");
    vi.advanceTimersByTime(100);
    expect(fn).toHaveBeenCalledExactlyOnceWith("b");

    debounced("c");
    debounced.cancel();
    vi.advanceTimersByTime(100);
    expect(fn).toHaveBeenCalledOnce();
  });
});

describe("createTable", () => {
  const stubFetch = (label = "second") =>
    vi.spyOn(window, "fetch").mockResolvedValue({ text: async () => results(label) });

  it("fetches the fragment, swaps it in and pushes the url", async () => {
    const fetchSpy = stubFetch();
    const table = makeTable(root);

    await table.set({ q: "ana" });

    expect(fetchSpy).toHaveBeenCalledWith("/admin?q=ana", { headers: { "X-Requested-With": "fetch" } });
    expect(root.querySelector("[data-part=count]").textContent).toBe("second results");
    expect(window.location.search).toBe("?q=ana");
    expect(table.params).toEqual({ q: "ana" });
  });

  it("seeds its params from the url it loaded with", () => {
    window.history.pushState({}, "", "/admin?q=ana&page=3");
    expect(makeTable(root).params).toEqual({ q: "ana", page: "3" });
  });

  it("drops a param that is set back to empty", async () => {
    stubFetch();
    const table = makeTable(root);

    await table.set({ q: "ana" });
    await table.set({ q: "" });
    expect(table.params).toEqual({});

    await table.set({ status: [ "shipped" ] });
    await table.set({ status: [] });
    expect(table.params).toEqual({});
  });

  it("returns to the first page whenever a filter changes", async () => {
    stubFetch();
    const table = makeTable(root);

    await table.set({ page: "3" });
    expect(table.params.page).toBe("3");

    await table.set({ q: "ana" });
    expect(table.params.page).toBeUndefined();
  });

  it("keeps the page when the change is the page itself", async () => {
    stubFetch();
    const table = makeTable(root);

    await table.set({ page: 2 });
    expect(table.params.page).toBe(2);
  });

  it("intercepts links inside the results, but leaves other links alone", async () => {
    stubFetch();
    makeTable(root);

    const inside = root.querySelector('[data-part=table] a[href="/admin?page=2"]');
    click(inside);
    await vi.waitFor(() => expect(window.location.search).toBe("?page=2"));

    const offList = root.querySelector('a[href="/elsewhere"]');
    const event = new window.MouseEvent("click", { bubbles: true, cancelable: true });
    offList.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(false);
  });

  it("ignores clicks that are not on a link", () => {
    stubFetch();
    makeTable(root);
    expect(() => click(root.querySelector("[data-part=count]"))).not.toThrow();
  });

  it("reloads without pushing a new entry on back or forward", async () => {
    const fetchSpy = stubFetch();
    makeTable(root);
    const pushSpy = vi.spyOn(window.history, "pushState");

    window.history.pushState({}, "", "/admin?q=back");
    pushSpy.mockClear();
    window.dispatchEvent(new window.PopStateEvent("popstate"));

    await vi.waitFor(() => expect(fetchSpy).toHaveBeenCalledWith("/admin?q=back", expect.anything()));
    expect(pushSpy).not.toHaveBeenCalled();
  });

  it("marks itself busy while loading and calls back after each render", async () => {
    stubFetch();
    const onRender = vi.fn();
    const table = makeTable(root, { path: "/admin", onRender });

    const pending = table.set({ q: "ana" });
    expect(root.classList.contains("is-loading")).toBe(true);
    await pending;
    expect(root.classList.contains("is-loading")).toBe(false);
    expect(onRender).toHaveBeenCalledOnce();
  });

  it("discards a response that a newer request has already superseded", async () => {
    let resolveFirst;
    vi.spyOn(window, "fetch")
      .mockImplementationOnce(() => new Promise((resolve) => { resolveFirst = () => resolve({ text: async () => results("stale") }); }))
      .mockResolvedValue({ text: async () => results("fresh") });

    const table = makeTable(root);
    const first = table.set({ q: "a" });
    const second = table.set({ q: "ab" });

    await second;
    resolveFirst();
    await first;

    expect(root.querySelector("[data-part=count]").textContent).toBe("fresh results");
  });

  it("stops answering history events once destroyed", async () => {
    const fetchSpy = stubFetch();
    const table = makeTable(root);
    table.destroy();
    fetchSpy.mockClear();

    window.dispatchEvent(new window.PopStateEvent("popstate"));
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("reload refetches the current params", async () => {
    const fetchSpy = stubFetch();
    const table = makeTable(root);

    await table.set({ q: "ana" });
    fetchSpy.mockClear();
    await table.reload({ push: false });

    expect(fetchSpy).toHaveBeenCalledWith("/admin?q=ana", expect.anything());
  });
});
