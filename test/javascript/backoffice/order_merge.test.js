import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  OPEN_CLASS, PREVIEW_FAILED, bindMergePanel, formatBRL, plural, selection, summarize
} from "../../../app/javascript/backoffice/order_merge.js";

// Mirrors the data hooks in app/views/admin/orders/_merge_panel.html.erb.
function mount({ bar = true } = {}) {
  document.body.innerHTML = `
    <div data-bo-order>
      <div data-merge-panel data-preview-url="/admin/pedidos/PG-1/mesclagem/previa"
           data-picked-one="1 pedido selecionado" data-picked-other="{n} pedidos selecionados"
           data-items-one="1 item" data-items-other="{n} itens"
           data-adds="+{items} · +{amount} em produtos"
           data-pick="Selecione os pedidos a mesclar" data-stays="O pedido PG-1 permanece como mestre">
        <form data-merge-form id="merge-form" action="/admin/pedidos/PG-1/mesclagem" method="post">
          <input type="hidden" name="authenticity_token" value="tok">
          <label data-merge-row data-items="1" data-subtotal-cents="4000">
            <input type="checkbox" name="numbers[]" value="PG-2" data-merge-pick>
          </label>
          <label data-merge-row data-items="2" data-subtotal-cents="123456">
            <input type="checkbox" name="numbers[]" value="PG-3" data-merge-pick>
          </label>
          ${bar ? `<span data-merge-title></span><span data-merge-summary></span>
          <button type="button" data-merge-clear hidden>Limpar</button>
          <button type="button" data-merge-open disabled>Mesclar</button>` : ""}
        </form>
      </div>
      <div data-merge-modal></div>
    </div>`;
  return {
    panel: document.querySelector("[data-merge-panel]"),
    host: document.querySelector("[data-merge-modal]")
  };
}

function pick(panel, value) {
  const input = panel.querySelector(`[value="${value}"]`);
  input.checked = true;
  input.dispatchEvent(new window.Event("change", { bubbles: true }));
}

const MODAL = `<div data-merge-overlay><div class="mg-modal">
  <button type="button" data-merge-close><span data-inner>Cancelar</span></button>
  <button type="submit" form="merge-form" data-merge-confirm>Confirmar</button>
</div></div>`;

const ERROR_MODAL = `<div data-merge-overlay><div class="mg-modal">
  <p data-merge-error>Erro</p><button type="button" data-merge-close>Cancelar</button>
</div></div>`;

describe("formatting", () => {
  it("formats cents the way HasMoney.format does", () => {
    expect(formatBRL(123456)).toBe("R$ 1.234,56");
    expect(formatBRL(0)).toBe("R$ 0,00");
  });

  it("picks the singular or plural template from the panel", () => {
    const { panel } = mount();
    expect(plural(panel, "items", 1)).toBe("1 item");
    expect(plural(panel, "items", 3)).toBe("3 itens");
  });
});

describe("summarize", () => {
  it("sums the picked rows and enables the actions", () => {
    const { panel } = mount();
    panel.querySelectorAll("[data-merge-pick]").forEach((input) => { input.checked = true; });

    expect(selection(panel)).toEqual({ count: 2, items: 3, cents: 127456 });
    summarize(panel);
    expect(panel.querySelector("[data-merge-title]").textContent).toBe("2 pedidos selecionados");
    expect(panel.querySelector("[data-merge-summary]").textContent).toBe("+3 itens · +R$ 1.274,56 em produtos");
    expect(panel.querySelector("[data-merge-open]").disabled).toBe(false);
    expect(panel.querySelector("[data-merge-clear]").hidden).toBe(false);
  });

  it("falls back to the prompt when nothing is picked", () => {
    const { panel } = mount();
    summarize(panel);
    expect(panel.querySelector("[data-merge-title]").textContent).toBe("Selecione os pedidos a mesclar");
    expect(panel.querySelector("[data-merge-summary]").textContent).toBe("O pedido PG-1 permanece como mestre");
    expect(panel.querySelector("[data-merge-open]").disabled).toBe(true);
  });
});

describe("bindMergePanel", () => {
  let frame;

  beforeEach(() => {
    frame = vi.fn((fn) => fn());
    window.alert = vi.fn();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  function stubFetch(body, ok = true) {
    const fetchMock = vi.fn(async () => ({ ok, status: ok ? 200 : 500, text: async () => body }));
    vi.stubGlobal("fetch", fetchMock);
    return fetchMock;
  }

  it("does nothing without a panel, a host or a merge bar", () => {
    expect(bindMergePanel(null, null)).toBeNull();
    const { panel, host } = mount({ bar: false });
    expect(bindMergePanel(panel, host)).toBeNull();
  });

  it("updates the summary as rows are picked and clears the selection", () => {
    const { panel, host } = mount();
    bindMergePanel(panel, host, { frame });

    pick(panel, "PG-2");
    expect(panel.querySelector("[data-merge-title]").textContent).toBe("1 pedido selecionado");

    panel.querySelector("[data-merge-clear]").click();
    expect(selection(panel).count).toBe(0);
    expect(panel.querySelector("[data-merge-clear]").hidden).toBe(true);
  });

  it("ignores changes from anything but a pick box", () => {
    const { panel, host } = mount();
    bindMergePanel(panel, host, { frame });
    const title = panel.querySelector("[data-merge-title]");
    title.textContent = "untouched";

    panel.querySelector("input[name=authenticity_token]").dispatchEvent(new window.Event("change", { bubbles: true }));
    expect(title.textContent).toBe("untouched");
  });

  it("posts the form to the preview url and opens the returned modal", async () => {
    const { panel, host } = mount();
    const fetchMock = stubFetch(MODAL);
    const merge = bindMergePanel(panel, host, { frame });
    pick(panel, "PG-3");

    await merge.preview();

    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe("/admin/pedidos/PG-1/mesclagem/previa");
    expect(options.method).toBe("POST");
    expect(options.body.getAll("numbers[]")).toEqual(["PG-3"]);
    expect(options.body.get("authenticity_token")).toBe("tok");
    expect(options.headers["X-CSRF-Token"]).toBe("");
    const overlay = host.querySelector("[data-merge-overlay]");
    expect(overlay.classList.contains(OPEN_CLASS)).toBe(true);
    expect(document.activeElement).toBe(host.querySelector("[data-merge-confirm]"));
  });

  it("sends the page's CSRF token, since the form's token is bound to the create action", async () => {
    const { panel, host } = mount();
    const meta = document.createElement("meta");
    meta.name = "csrf-token";
    meta.content = "page-token";
    document.head.appendChild(meta);
    const fetchMock = stubFetch(MODAL);

    await bindMergePanel(panel, host, { frame }).preview();
    expect(fetchMock.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("page-token");
    meta.remove();
  });

  it("focuses the close button when the modal only explains a refusal", async () => {
    const { panel, host } = mount();
    stubFetch(ERROR_MODAL);
    const merge = bindMergePanel(panel, host, { frame });

    await merge.preview();
    expect(document.activeElement).toBe(host.querySelector("[data-merge-close]"));
  });

  it("closes on Cancelar, on the backdrop and on Escape", async () => {
    const { panel, host } = mount();
    stubFetch(MODAL);
    const merge = bindMergePanel(panel, host, { frame });

    await merge.preview();
    host.querySelector("[data-inner]").click();
    expect(host.children).toHaveLength(0);

    await merge.preview();
    host.querySelector(".mg-modal").click();
    expect(host.children).toHaveLength(1);
    host.querySelector("[data-merge-overlay]").click();
    expect(host.children).toHaveLength(0);

    await merge.preview();
    document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter" }));
    expect(host.children).toHaveLength(1);
    document.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape" }));
    expect(host.children).toHaveLength(0);
  });

  it("opens the preview from the merge button", async () => {
    const { panel, host } = mount();
    const fetchMock = stubFetch(MODAL);
    bindMergePanel(panel, host, { frame });
    pick(panel, "PG-2");

    panel.querySelector("[data-merge-open]").click();
    await vi.waitFor(() => expect(host.querySelector("[data-merge-overlay]")).not.toBeNull());
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("alerts when the preview request fails", async () => {
    const { panel, host } = mount();
    stubFetch("", false);
    const merge = bindMergePanel(panel, host, { frame });

    await merge.preview();
    expect(window.alert).toHaveBeenCalledWith(PREVIEW_FAILED);
    expect(host.children).toHaveLength(0);
  });

  it("animates the overlay in on the next frame by default", async () => {
    const { panel, host } = mount();
    stubFetch(MODAL);
    const raf = vi.fn();
    vi.stubGlobal("requestAnimationFrame", raf);
    const merge = bindMergePanel(panel, host);

    await merge.preview();
    expect(raf).toHaveBeenCalledTimes(1);
    expect(host.querySelector("[data-merge-overlay]").classList.contains(OPEN_CLASS)).toBe(false);
  });
});
