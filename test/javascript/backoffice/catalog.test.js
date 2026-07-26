import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { dismissToasts, initCatalog, matchingRows, plural, rowMatches, showOnly } from "../../../app/javascript/backoffice/catalog.js";

const input = (el) => el.dispatchEvent(new window.Event("input", { bubbles: true }));
const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

const catalogMarkup = (rows) => `
  <div data-catalog>
    <input id="gsearch">
    <div class="panel">
      <input id="c-q"><select id="c-cat"><option value=""></option><option value="c1">c1</option></select>
      <select id="c-status"><option value=""></option><option value="draft">draft</option></select>
      <span id="catalog-count"></span>
      <table><tbody id="catalog-body">${rows}</tbody></table>
      <div id="catalog-empty"></div>
      <div class="tbl-foot" id="catalog-foot" hidden></div>
    </div>
  </div>
  <div class="toasts"><div data-toast>saved</div></div>`;

const productRows = (count) => Array.from({ length: count }, (_, i) =>
  `<tr data-row data-href="/edit/${i}" data-name="game ${i}" data-slug="game-${i}" data-cat="c1" data-status="published"></tr>`
).join("");

const visibleRowCount = () =>
  document.querySelectorAll("#catalog-body [data-row]:not([hidden])").length;

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
  vi.useRealTimers();
});

describe("plural", () => {
  it("agrees the noun with the count", () => {
    expect(plural(1, "produto", "produtos")).toBe("1 produto");
    expect(plural(3, "produto", "produtos")).toBe("3 produtos");
  });
});

describe("rowMatches", () => {
  const data = { name: "pokémon crystal", slug: "pokemon-crystal", cat: "game-boy-color", status: "gotm" };

  it("matches on name or slug substrings", () => {
    expect(rowMatches(data, { q: "crystal" })).toBe(true);
    expect(rowMatches(data, { q: "pokemon-cr" })).toBe(true);
    expect(rowMatches(data, { q: "zelda" })).toBe(false);
  });

  it("matches category and status exactly", () => {
    expect(rowMatches(data, { cat: "game-boy-color" })).toBe(true);
    expect(rowMatches(data, { cat: "game-boy-classic" })).toBe(false);
    expect(rowMatches(data, { status: "gotm" })).toBe(true);
    expect(rowMatches(data, { status: "draft" })).toBe(false);
  });

  it("passes with no filters", () => {
    expect(rowMatches(data, {})).toBe(true);
  });
});

describe("matchingRows", () => {
  it("keeps only the rows the filters accept", () => {
    document.body.innerHTML = `<table><tbody>
      <tr data-row data-name="a" data-slug="a" data-cat="c1" data-status="published"></tr>
      <tr data-row data-name="b" data-slug="b" data-cat="c2" data-status="draft"></tr>
    </tbody></table>`;
    const rows = Array.from(document.querySelectorAll("[data-row]"));
    expect(matchingRows(rows, { cat: "c1" })).toEqual([rows[0]]);
  });
});

describe("showOnly", () => {
  it("reveals the given rows and hides every other one", () => {
    document.body.innerHTML = `<table><tbody>
      <tr data-row></tr><tr data-row hidden></tr><tr data-row></tr>
    </tbody></table>`;
    const rows = Array.from(document.querySelectorAll("[data-row]"));
    showOnly(rows, [rows[1]]);
    expect(rows.map((row) => row.hidden)).toEqual([true, false, true]);
  });
});

describe("dismissToasts", () => {
  it("removes toasts after the delay", () => {
    vi.useFakeTimers();
    document.body.innerHTML = `<div data-toast>ok</div>`;
    dismissToasts(document, 1000);
    expect(document.querySelector("[data-toast]")).not.toBeNull();
    vi.advanceTimersByTime(1000);
    expect(document.querySelector("[data-toast]")).toBeNull();
  });
});

describe("initCatalog", () => {
  beforeEach(() => {
    document.body.innerHTML = catalogMarkup(`
      <tr data-row data-href="/edit/1" data-name="alpha" data-slug="alpha" data-cat="c1" data-status="published"></tr>
      <tr data-row data-href="/edit/2" data-name="beta" data-slug="beta" data-cat="c2" data-status="draft"></tr>`);
  });

  it("returns null without a table body", () => {
    document.body.innerHTML = `<div data-catalog></div>`;
    expect(initCatalog(document)).toBeNull();
  });

  it("filters, updates the count and toggles the empty state", () => {
    initCatalog(document);
    const count = document.querySelector("#catalog-count");
    const empty = document.querySelector("#catalog-empty");
    expect(count.textContent).toBe("2 produtos");

    const cat = document.querySelector("#c-cat");
    cat.value = "c1";
    input(cat);
    expect(count.textContent).toBe("1 produto");
    expect(empty.classList.contains("show")).toBe(false);

    cat.value = "";
    input(cat);
    const status = document.querySelector("#c-status");
    status.value = "draft";
    input(status);
    expect(count.textContent).toBe("1 produto");

    status.value = "";
    input(status);
    const q = document.querySelector("#c-q");
    q.value = "nothing";
    input(q);
    expect(count.textContent).toBe("0 produtos");
    expect(empty.classList.contains("show")).toBe(true);
  });

  it("mirrors the topbar search into the list filter", () => {
    initCatalog(document);
    const gsearch = document.querySelector("#gsearch");
    gsearch.value = "beta";
    input(gsearch);
    expect(document.querySelector("#c-q").value).toBe("beta");
    expect(document.querySelector("#catalog-count").textContent).toBe("1 produto");
  });

  it("navigates to a row's editor on click", () => {
    const assign = vi.fn();
    vi.spyOn(window, "location", "get").mockReturnValue({ assign });
    initCatalog(document);
    click(document.querySelector('[data-href="/edit/2"]'));
    expect(assign).toHaveBeenCalledWith("/edit/2");
  });

  it("shows the footer count but no page controls when everything fits on one page", () => {
    initCatalog(document);
    expect(document.querySelector("#catalog-foot").hidden).toBe(false);
    expect(document.querySelector("#catalog-foot .pages")).toBeNull();
    expect(document.querySelector("#catalog-foot .foot-range").textContent).toBe("Mostrando 2 produtos");
  });
});

describe("initCatalog pagination", () => {
  beforeEach(() => {
    document.body.innerHTML = catalogMarkup(productRows(31));
  });

  it("shows only the first 30 rows but counts them all", () => {
    initCatalog(document);
    expect(visibleRowCount()).toBe(30);
    expect(document.querySelector("#catalog-count").textContent).toBe("31 produtos");
    expect(document.querySelector("#catalog-foot .foot-range").textContent)
      .toBe("Mostrando 1–30 de 31 produtos");
  });

  it("shows the remainder on the second page", () => {
    initCatalog(document);
    click(document.querySelector('#catalog-foot [data-pg="2"]'));
    expect(visibleRowCount()).toBe(1);
    expect(document.querySelector('[data-href="/edit/30"]').hidden).toBe(false);
  });

  it("returns to the first page when the filters change", () => {
    initCatalog(document);
    click(document.querySelector('#catalog-foot [data-pg="2"]'));
    const q = document.querySelector("#c-q");
    q.value = "game";
    input(q);
    expect(document.querySelector('#catalog-foot [aria-current="page"]').textContent).toBe("1");
    expect(document.querySelector('[data-href="/edit/0"]').hidden).toBe(false);
  });

  it("returns to the first page when the topbar search changes", () => {
    initCatalog(document);
    click(document.querySelector('#catalog-foot [data-pg="2"]'));
    const gsearch = document.querySelector("#gsearch");
    gsearch.value = "game";
    input(gsearch);
    expect(document.querySelector('#catalog-foot [aria-current="page"]').textContent).toBe("1");
  });

  it("hides the footer when a filter matches nothing", () => {
    initCatalog(document);
    const q = document.querySelector("#c-q");
    q.value = "nothing";
    input(q);
    expect(document.querySelector("#catalog-foot").hidden).toBe(true);
    expect(document.querySelector("#catalog-empty").classList.contains("show")).toBe(true);
  });
});
