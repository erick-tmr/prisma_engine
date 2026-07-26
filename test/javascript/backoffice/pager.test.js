import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  PAGE_SIZE, clampPage, pageCount, pageSlice, pageWindow, pagesHtml,
  rangeHtml, renderPager, scrollPanelTop
} from "../../../app/javascript/backoffice/pager.js";

const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
const rows = (n) => Array.from({ length: n }, (_, i) => i + 1);

let mount;

beforeEach(() => {
  document.body.innerHTML = `<div class="panel"><div class="tbl-foot"></div></div>`;
  mount = document.querySelector(".tbl-foot");
});

describe("pageCount", () => {
  it("never drops below one page, even with nothing to show", () => {
    expect(pageCount(0)).toBe(1);
  });

  it("keeps a full page on one page and spills the next row onto a second", () => {
    expect(pageCount(PAGE_SIZE)).toBe(1);
    expect(pageCount(PAGE_SIZE + 1)).toBe(2);
    expect(pageCount(348)).toBe(12);
  });
});

describe("clampPage", () => {
  it("pulls a stale page back into range after the set shrinks", () => {
    expect(clampPage(9, 40)).toBe(2);
    expect(clampPage(3, 0)).toBe(1);
  });

  it("rejects pages below one", () => {
    expect(clampPage(0, 100)).toBe(1);
    expect(clampPage(-4, 100)).toBe(1);
  });

  it("leaves an in-range page alone", () => {
    expect(clampPage(2, 100)).toBe(2);
  });
});

describe("pageSlice", () => {
  it("cuts the window for the requested page", () => {
    expect(pageSlice(rows(75), 1)).toEqual(rows(30));
    expect(pageSlice(rows(75), 2)[0]).toBe(31);
    expect(pageSlice(rows(75), 3)).toHaveLength(15);
  });

  it("clamps before slicing so a stale page still yields rows", () => {
    expect(pageSlice(rows(40), 9)[0]).toBe(31);
  });

  it("returns nothing when there is nothing to page", () => {
    expect(pageSlice([], 1)).toEqual([]);
  });
});

describe("pageWindow", () => {
  it("lists every page when there are seven or fewer", () => {
    expect(pageWindow(1, 7)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    expect(pageWindow(1, 1)).toEqual([1]);
  });

  it("pads the head and trails off with one gap near the start", () => {
    expect(pageWindow(1, 12)).toEqual([1, 2, 3, 4, "gap", 12]);
    expect(pageWindow(3, 12)).toEqual([1, 2, 3, 4, "gap", 12]);
  });

  it("gaps on both sides in the middle of a long list", () => {
    expect(pageWindow(6, 12)).toEqual([1, "gap", 5, 6, 7, "gap", 12]);
  });

  it("pads the tail near the end", () => {
    expect(pageWindow(12, 12)).toEqual([1, "gap", 9, 10, 11, 12]);
  });
});

describe("rangeHtml", () => {
  it("uses the singular noun for a lone row", () => {
    expect(rangeHtml(1, 1, ["pedido", "pedidos"])).toBe("<b>1</b> pedido");
  });

  it("shows a bare count when everything fits on one page", () => {
    expect(rangeHtml(1, 20, ["produto", "produtos"])).toBe("<b>20</b> produtos");
  });

  it("shows the from-to range once there is more than one page", () => {
    expect(rangeHtml(2, 348, ["pedido", "pedidos"])).toBe("<b>31–60</b> de <b>348</b> pedidos");
  });

  it("stops the range at the total on a partial last page", () => {
    expect(rangeHtml(12, 348, ["pedido", "pedidos"])).toBe("<b>331–348</b> de <b>348</b> pedidos");
  });
});

describe("pagesHtml", () => {
  it("marks the current page and disables only the arrow it sits against", () => {
    const html = pagesHtml(1, 12);
    expect(html).toContain('class="pg on" data-pg="1" aria-current="page"');
    expect(html).toContain('data-pg="0" disabled');
    expect(html).not.toContain('data-pg="2" disabled');
  });

  it("disables the next arrow on the last page", () => {
    expect(pagesHtml(12, 12)).toContain('data-pg="13" disabled');
  });

  it("renders ellipses as inert spans", () => {
    expect(pagesHtml(6, 12)).toContain('<span class="pg-gap" aria-hidden="true">…</span>');
  });
});

describe("renderPager", () => {
  const render = (total, page = 1, onGo = () => {}) =>
    renderPager(mount, { page, total, noun: ["pedido", "pedidos"], onGo });

  it("hides itself entirely when there is nothing to page", () => {
    render(0);
    expect(mount.hidden).toBe(true);
    expect(mount.innerHTML).toBe("");
  });

  it("shows the count without controls when everything fits on one page", () => {
    render(20);
    expect(mount.hidden).toBe(false);
    expect(mount.textContent).toContain("Mostrando 20 pedidos");
    expect(mount.querySelector(".pages")).toBeNull();
    expect(mount.querySelector(".foot-single").textContent).toBe("Página 1 de 1");
  });

  it("renders the range and the page controls for a long list", () => {
    render(348, 6);
    expect(mount.querySelector(".foot-range").textContent).toBe("Mostrando 151–180 de 348 pedidos");
    expect(mount.querySelectorAll(".pg-gap")).toHaveLength(2);
    expect(mount.querySelector('[aria-current="page"]').textContent).toBe("6");
  });

  it("clamps a page past the end before rendering", () => {
    render(348, 99);
    expect(mount.querySelector('[aria-current="page"]').textContent).toBe("12");
  });

  it("reports the page the admin clicked", () => {
    const onGo = vi.fn();
    render(348, 6, onGo);
    click(mount.querySelector('[data-pg="7"]'));
    expect(onGo).toHaveBeenCalledExactlyOnceWith(7);
  });

  it("ignores clicks on the current page, on a disabled arrow, and on the footer itself", () => {
    const onGo = vi.fn();
    render(348, 1, onGo);
    click(mount.querySelector('[aria-current="page"]'));
    click(mount.querySelector('[data-pg="0"]'));
    click(mount.querySelector(".foot-range"));
    expect(onGo).not.toHaveBeenCalled();
  });

  it("replaces its click handler on re-render instead of stacking them", () => {
    const onGo = vi.fn();
    render(348, 1, onGo);
    render(348, 1, onGo);
    click(mount.querySelector('[data-pg="2"]'));
    expect(onGo).toHaveBeenCalledOnce();
  });
});

describe("scrollPanelTop", () => {
  it("scrolls to the top of the panel the footer belongs to", () => {
    const panel = document.querySelector(".panel");
    panel.scrollIntoView = vi.fn();
    scrollPanelTop(mount);
    expect(panel.scrollIntoView).toHaveBeenCalledWith({ block: "start" });
  });
});
