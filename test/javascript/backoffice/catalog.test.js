import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { applyFilters, dismissToasts, initCatalog, plural, rowMatches } from "../../../app/javascript/backoffice/catalog.js";

const input = (el) => el.dispatchEvent(new window.Event("input", { bubbles: true }));
const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));

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

describe("applyFilters", () => {
  it("hides non-matching rows and counts the visible ones", () => {
    document.body.innerHTML = `<table><tbody>
      <tr data-row data-name="a" data-slug="a" data-cat="c1" data-status="published"></tr>
      <tr data-row data-name="b" data-slug="b" data-cat="c2" data-status="draft"></tr>
    </tbody></table>`;
    const rows = Array.from(document.querySelectorAll("[data-row]"));
    const visible = applyFilters(rows, { cat: "c1" });
    expect(visible).toBe(1);
    expect(rows[0].hidden).toBe(false);
    expect(rows[1].hidden).toBe(true);
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
    document.body.innerHTML = `
      <div data-catalog>
        <input id="gsearch">
        <input id="c-q"><select id="c-cat"><option value=""></option><option value="c1">c1</option></select>
        <select id="c-status"><option value=""></option><option value="draft">draft</option></select>
        <span id="catalog-count"></span>
        <table><tbody id="catalog-body">
          <tr data-row data-href="/edit/1" data-name="alpha" data-slug="alpha" data-cat="c1" data-status="published"></tr>
          <tr data-row data-href="/edit/2" data-name="beta" data-slug="beta" data-cat="c2" data-status="draft"></tr>
        </tbody></table>
        <div id="catalog-empty"></div>
      </div>
      <div class="toasts"><div data-toast>saved</div></div>`;
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
});
