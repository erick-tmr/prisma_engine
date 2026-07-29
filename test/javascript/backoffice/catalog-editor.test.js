import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  applyPickedFile, brindeWeight, CO_FIELDS, defaultPublishAt, editionKey, formatPrice, hasImage, hydrate,
  initEditor, isFutureEdition, moveItem, plural, serialize, slugify, validate
} from "../../../app/javascript/backoffice/catalog-editor.js";

const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
const fire = (el, type) => el.dispatchEvent(new window.Event(type, { bubbles: true }));
const setInput = (el, value) => { el.value = value; fire(el, "input"); };

function defaultGraph(overrides = {}) {
  return {
    options: [ { group_name: "Idioma", values: [ { name: "Português BR", weight: 0 } ] } ],
    tags: [ "pokemon" ],
    photos: [ { id: 7, url: "/cover.jpg", alt: "capa" } ],
    gotm: { enabled: false, year: 2026, month: 7, publish_at: "2026-07-01T00:00", position: 0, blurb: "", brindes: [] },
    ...overrides
  };
}

function mount(graph = defaultGraph(), currentEdition = "2026-07") {
  const months = Array.from({ length: 12 }, (_, i) => `<option value="${i + 1}">${i + 1}</option>`).join("");
  const withGraph = graph !== null;
  document.body.innerHTML = `
    <div class="app">
      <aside data-sidebar></aside>
      <div class="main">
        <button id="menu-toggle"></button>
        <form id="ed-form" data-catalog-editor>
          <input id="f-graph" type="hidden">
          <input id="f-name" value=""><input id="f-slug" value=""><span id="slug-echo"></span>
          <input id="f-price" value="190,00"><input id="f-weight" type="number" value="60"><button id="weight-restore"></button>
          <input id="f-published" type="checkbox" checked><div id="pub-title"></div>
          <div id="photo-grid"></div><span id="photo-count"></span><div id="photo-files"></div>
          <div id="opt-groups"></div><button id="add-group"></button>
          <div id="tag-editor"></div>
          <div id="gotm-panel" hidden></div><div id="gotm-card"></div>
          <input id="f-gotm" type="checkbox">
          <select id="f-gotm-month">${months}</select>
          <select id="f-gotm-year"><option value="2025">2025</option><option value="2026">2026</option><option value="2027">2027</option></select>
          <input id="f-gotm-pos" type="number" value="0"><textarea id="f-blurb"></textarea><span id="gotm-edition-badge"></span>
          <input id="f-gotm-publish-at" type="datetime-local"><p id="gotm-publish-hint" hidden></p>
          <div id="brinde-list"></div><div id="brinde-files"></div><b id="brinde-weight"></b><button id="add-brinde"></button>
          <input id="f-custom-order" type="checkbox"><div id="co-body" hidden></div><button id="co-restore"></button>
          ${CO_FIELDS.map(({ input, echo }) =>
            `<input id="${input}" placeholder="padrão ${input}">${echo ? `<span id="${echo}"></span>` : ""}`).join("")}
        </form>
      </div>
    </div>
    <div class="toasts" id="toasts"></div>`;
  const form = document.getElementById("ed-form");
  form.dataset.currentEdition = currentEdition;
  if (withGraph) form.dataset.graph = JSON.stringify(graph);
  return initEditor(document);
}

beforeEach(() => {
  vi.spyOn(HTMLInputElement.prototype, "click").mockImplementation(() => {});
});

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
});

describe("pure helpers", () => {
  it("plural agrees the noun", () => {
    expect(plural(1, "foto", "fotos")).toBe("1 foto");
    expect(plural(2, "foto", "fotos")).toBe("2 fotos");
  });

  it("slugify normalizes accents and separators", () => {
    expect(slugify("Pokémon · Crystal RTC!")).toBe("pokemon-crystal-rtc");
    expect(slugify("")).toBe("");
  });

  it("moveItem reorders without mutating the source", () => {
    const list = [ "a", "b", "c" ];
    expect(moveItem(list, 0, 2)).toEqual([ "b", "c", "a" ]);
    expect(list).toEqual([ "a", "b", "c" ]);
  });

  it("brindeWeight sums integer weights", () => {
    expect(brindeWeight([ { weight: 5 }, { weight: "3" }, { weight: null } ])).toBe(8);
  });

  it("hasImage recognizes persisted or freshly picked images", () => {
    expect(hasImage({ id: 1 })).toBe(true);
    expect(hasImage({ preview: "blob:x" })).toBe(true);
    expect(hasImage({ id: null, preview: null })).toBe(false);
  });

  it("hydrate tolerates a bare graph", () => {
    const state = hydrate({});
    expect(state).toEqual({ photos: [], groups: [], tags: [], brindes: [] });
  });

  it("hydrate fills defaults for missing fields", () => {
    const state = hydrate({ photos: [ {} ], options: [ { values: [ {} ] }, {} ], gotm: { brindes: [ {} ] } });
    expect(state.photos[0]).toEqual({ id: null, key: null, url: null, alt: "", preview: null });
    expect(state.groups[0]).toEqual({ name: "", values: [ { name: "", weight: 0 } ] });
    expect(state.groups[1]).toEqual({ name: "", values: [] });
    expect(state.brindes[0]).toEqual({ id: null, key: null, url: null, preview: null, caption: "", kind: "", description: "", weight: 0 });
  });

  it("serialize keeps ids or keys and filters imageless slots", () => {
    const state = {
      groups: [ { name: "Idioma", values: [ { name: "PT", weight: "2" } ] } ],
      tags: [ "rpg" ],
      photos: [ { id: 3, alt: "a" }, { key: "p-0", alt: "b", preview: "blob:x" }, { key: "p-1", alt: "c" } ],
      brindes: [ { id: 9, caption: "x", kind: "k", description: "d", weight: 4 }, { key: "b-0", caption: "y", weight: 0, preview: "blob:y" } ]
    };
    const out = serialize(state, { enabled: true, year: 2026, month: 5, position: 1, blurb: "hey" });
    expect(out.options).toEqual([ { group_name: "Idioma", values: [ { name: "PT", weight: 2 } ] } ]);
    expect(out.tags).toEqual([ "rpg" ]);
    expect(out.photos).toEqual([ { id: 3, alt: "a" }, { key: "p-0", alt: "b" } ]);
    expect(out.gotm.enabled).toBe(true);
    expect(out.gotm.brindes).toEqual([
      { id: 9, caption: "x", kind: "k", description: "d", weight: 4 },
      { key: "b-0", caption: "y", kind: undefined, description: undefined, weight: 0 }
    ]);
  });

  it("validate reports the first blocking problem", () => {
    expect(validate({ brindes: [] }, { name: "Jogo", weight: 60, gotmEnabled: false })).toBeNull();
    expect(validate({ brindes: [] }, { name: " ", weight: 60, gotmEnabled: false })).toBe("nameRequired");
    expect(validate({ brindes: [] }, { name: "Jogo", weight: 0, gotmEnabled: false })).toBe("weightRequired");
    expect(validate({ brindes: [ { id: null } ] }, { name: "Jogo", weight: 60, gotmEnabled: true })).toBe("brindeImage");
  });

  it("formatPrice normalizes to pt-BR and passes through junk", () => {
    expect(formatPrice("1234,5")).toBe("1.234,50");
    expect(formatPrice("abc")).toBe("abc");
  });

  it("applyPickedFile stores the preview and re-renders", () => {
    const item = {};
    const rerender = vi.fn();
    applyPickedFile(item, "blob:y", rerender);
    expect(item.preview).toBe("blob:y");
    expect(rerender).toHaveBeenCalledOnce();
  });
});

describe("initEditor", () => {
  it("returns null without an editor form", () => {
    document.body.innerHTML = `<div></div>`;
    expect(initEditor(document)).toBeNull();
  });

  it("hydrates the collections from the graph", () => {
    const api = mount();
    expect(document.querySelectorAll("#opt-groups .opt-group").length).toBe(1);
    expect(document.querySelectorAll("#tag-editor .tagchip").length).toBe(1);
    expect(document.querySelectorAll("#photo-grid .photo-card").length).toBe(1);
    expect(document.querySelector("#photo-count").textContent).toBe("1 foto");
    expect(api.state.groups[0].name).toBe("Idioma");
  });

  it("shows a cover badge on the first photo and a preview background", () => {
    mount();
    const frame = document.querySelector(".photo-frame");
    expect(frame.querySelector(".photo-cover-badge")).not.toBeNull();
    expect(frame.style.backgroundImage).toContain("/cover.jpg");
  });

  it("adds and removes photos, editing alt text", () => {
    const api = mount();
    click(document.querySelector(".photo-add"));
    expect(api.state.photos.length).toBe(2);

    const altInput = document.querySelectorAll(".photo-meta input")[1];
    setInput(altInput, "segunda");
    expect(api.state.photos[1].alt).toBe("segunda");

    click(document.querySelectorAll(".photo-card .rm")[1]);
    expect(api.state.photos.length).toBe(1);
  });

  it("opens the picker on a frame click but ignores clicks on the tools", () => {
    mount();
    const frame = document.querySelector(".photo-frame");
    click(frame);
    click(frame.querySelector(".drag"));
    expect(HTMLInputElement.prototype.click).toHaveBeenCalledTimes(1);
  });

  it("manages option groups and values", () => {
    const api = mount();
    click(document.querySelector("#add-group"));
    expect(api.state.groups.length).toBe(2);

    const group = document.querySelectorAll(".opt-group")[1];
    setInput(group.querySelector(".group-name"), "Versão");
    expect(api.state.groups[1].name).toBe("Versão");

    click(group.querySelector(".add-inline"));
    expect(api.state.groups[1].values.length).toBe(2);

    const rows = group.querySelectorAll(".opt-value-row");
    setInput(rows[0].querySelector(".v-name"), "DX");
    setInput(rows[0].querySelector(".v-weight input"), "12");
    expect(api.state.groups[1].values[0]).toEqual({ name: "DX", weight: 12 });
    setInput(rows[0].querySelector(".v-weight input"), "");
    expect(api.state.groups[1].values[0].weight).toBe(0);

    click(rows[0].querySelector(".v-remove"));
    expect(api.state.groups[1].values.length).toBe(1);

    click(group.querySelector(".opt-group-remove"));
    click(document.querySelectorAll(".opt-group .opt-group-remove")[0]);
    expect(document.querySelector(".opt-empty")).not.toBeNull();
  });

  it("adds tags via prompt and removes them", () => {
    const api = mount();
    const prompt = vi.spyOn(window, "prompt")
      .mockReturnValueOnce("Zelda").mockReturnValueOnce(null).mockReturnValueOnce("pokemon");
    click(document.querySelector(".tag-add"));
    expect(api.state.tags).toEqual([ "pokemon", "zelda" ]);
    click(document.querySelector(".tag-add"));
    click(document.querySelector(".tag-add"));
    expect(api.state.tags).toEqual([ "pokemon", "zelda" ]);
    expect(prompt).toHaveBeenCalledTimes(3);

    click(document.querySelector(".tagchip .x"));
    expect(api.state.tags).toEqual([ "zelda" ]);
  });

  it("reveals the Jogo do Mês module, seeding a brinde and a toast", () => {
    const api = mount();
    const toggle = document.querySelector("#f-gotm");
    toggle.checked = true;
    fire(toggle, "change");

    expect(document.querySelector("#gotm-panel").hidden).toBe(false);
    expect(document.querySelector("#gotm-card").classList.contains("on")).toBe(true);
    expect(api.state.brindes.length).toBe(1);
    expect(document.querySelector("#toasts .toast")).not.toBeNull();
    expect(document.querySelector("#gotm-edition-badge").textContent).toContain("2026");

    setInput(document.querySelector("#f-gotm-month"), "12");
    fire(document.querySelector("#f-gotm-month"), "change");
    expect(document.querySelector("#gotm-edition-badge").textContent).toContain("· 2026");

    toggle.checked = false;
    fire(toggle, "change");
    expect(document.querySelector("#gotm-panel").hidden).toBe(true);
  });

  it("reveals the sob-encomenda body and toasts when the switch goes on", () => {
    mount();
    const toggle = document.querySelector("#f-custom-order");
    expect(document.querySelector("#co-body").hidden).toBe(true);

    toggle.checked = true;
    fire(toggle, "change");
    expect(document.querySelector("#co-body").hidden).toBe(false);
    expect(document.querySelector("#toasts .toast")).not.toBeNull();

    toggle.checked = false;
    fire(toggle, "change");
    expect(document.querySelector("#co-body").hidden).toBe(true);
  });

  it("echoes the pedido-box copy into the preview, falling back to the placeholder", () => {
    mount();
    const title = document.querySelector("#f-co-title");
    expect(document.querySelector("#cop-title").textContent).toBe("padrão f-co-title");

    setInput(title, "Monte o seu");
    expect(document.querySelector("#cop-title").textContent).toBe("Monte o seu");

    setInput(title, "   ");
    expect(document.querySelector("#cop-title").textContent).toBe("padrão f-co-title");
  });

  it("restores every string by clearing the inputs back to their placeholders", () => {
    mount();
    setInput(document.querySelector("#f-co-title"), "Monte o seu");
    setInput(document.querySelector("#f-co-game-error"), "Diga o jogo.");

    click(document.querySelector("#co-restore"));

    expect(document.querySelector("#f-co-title").value).toBe("");
    expect(document.querySelector("#f-co-game-error").value).toBe("");
    expect(document.querySelector("#cop-title").textContent).toBe("padrão f-co-title");
    expect(document.querySelector("#toasts .toast")).not.toBeNull();
  });

  it("edits brinde fields and totals their weight", () => {
    const api = mount(defaultGraph({
      gotm: { enabled: true, year: 2026, month: 7, position: 0, blurb: "b",
        brindes: [ { id: 5, url: "/b.jpg", caption: "Pôster", kind: "Arte", description: "d", weight: 5 } ] }
    }));
    expect(document.querySelectorAll(".brinde-card").length).toBe(1);
    expect(document.querySelector("#brinde-weight").textContent).toBe("5 g");

    click(document.querySelector("#add-brinde"));
    expect(api.state.brindes.length).toBe(2);

    const second = document.querySelectorAll(".brinde-card")[1];
    setInput(second.querySelector(".brinde-row input"), "Cartão");
    setInput(second.querySelector("textarea"), "trivia");
    setInput(second.querySelector(".bi-weight input"), "3");
    expect(api.state.brindes[1].caption).toBe("Cartão");
    expect(api.state.brindes[1].description).toBe("trivia");
    expect(document.querySelector("#brinde-weight").textContent).toBe("8 g");
    setInput(second.querySelector(".bi-weight input"), "");
    expect(document.querySelector("#brinde-weight").textContent).toBe("5 g");

    click(second.querySelector(".b-remove"));
    expect(api.state.brindes.length).toBe(1);
    click(document.querySelector(".brinde-photo"));
    expect(HTMLInputElement.prototype.click).toHaveBeenCalled();
  });

  it("auto-fills the slug until it is edited by hand", () => {
    mount();
    setInput(document.querySelector("#f-name"), "Zelda DX");
    expect(document.querySelector("#f-slug").value).toBe("zelda-dx");
    expect(document.querySelector("#slug-echo").textContent).toBe("zelda-dx");

    setInput(document.querySelector("#f-slug"), "custom");
    setInput(document.querySelector("#f-name"), "Outro Nome");
    expect(document.querySelector("#f-slug").value).toBe("custom");
    expect(document.querySelector("#slug-echo").textContent).toBe("custom");
  });

  it("formats the price on blur, flips the publish label and restores the weight", () => {
    mount();
    const price = document.querySelector("#f-price");
    price.value = "1234,5";
    fire(price, "blur");
    expect(price.value).toBe("1.234,50");

    const published = document.querySelector("#f-published");
    published.checked = false;
    fire(published, "change");
    expect(document.querySelector("#pub-title").textContent).toBe("Rascunho");
    published.checked = true;
    fire(published, "change");
    expect(document.querySelector("#pub-title").textContent).toBe("Publicado");

    document.querySelector("#f-weight").value = "5";
    click(document.querySelector("#weight-restore"));
    expect(document.querySelector("#f-weight").value).toBe("60");
  });

  it("serializes into the hidden graph field on a valid submit", () => {
    const api = mount();
    setInput(document.querySelector("#f-name"), "Novo Jogo");
    document.querySelector("#f-gotm-pos").value = "";
    fire(document.querySelector("#ed-form"), "submit");
    const graph = JSON.parse(document.querySelector("#f-graph").value);
    expect(graph.tags).toEqual([ "pokemon" ]);
    expect(graph.options[0].group_name).toBe("Idioma");
    expect(graph.gotm.position).toBe(0);
    expect(api.serialize().tags).toEqual([ "pokemon" ]);
  });

  it("defaults to an empty graph when the form carries none", () => {
    const api = mount(null);
    expect(api.state).toEqual({ photos: [], groups: [], tags: [], brindes: [] });
    expect(document.querySelector(".opt-empty")).not.toBeNull();
  });

  it("blocks submit and toasts when validation fails", () => {
    mount();
    const form = document.querySelector("#ed-form");
    const event = new window.Event("submit", { bubbles: true, cancelable: true });
    form.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(true);
    expect(document.querySelector("#toasts .toast-warn")).not.toBeNull();
    expect(document.querySelector("#f-graph").value).toBe("");
  });

  it("toggles the mobile sidebar", () => {
    mount();
    click(document.querySelector("#menu-toggle"));
    expect(document.querySelector("[data-sidebar]").classList.contains("show")).toBe(true);
  });

  it("renders empty-state copy for no groups and no brindes", () => {
    mount(defaultGraph({ options: [], gotm: { enabled: true, brindes: [] } }));
    expect(document.querySelector(".opt-empty")).not.toBeNull();
    expect(document.querySelector(".brinde-empty")).not.toBeNull();
  });

  it("applies a bare gotm block without month, year, position, blurb or publish_at", () => {
    mount(defaultGraph({ gotm: { enabled: false } }));
    expect(document.querySelector("#f-gotm-pos").value).toBe("0");
    expect(document.querySelector("#f-blurb").value).toBe("");
    expect(document.querySelector("#f-gotm-publish-at").value).toBe("");
  });

  it("builds a zero-padded edition key and its midnight default", () => {
    expect(editionKey(2026, 8)).toBe("2026-08");
    expect(defaultPublishAt(2026, 8)).toBe("2026-08-01T00:00");
    expect(isFutureEdition(2026, 8, "2026-07")).toBe(true);
    expect(isFutureEdition(2026, 7, "2026-07")).toBe(false);
    expect(isFutureEdition(2026, 6, "2026-07")).toBe(false);
  });

  it("keeps the stored publish_at on load and round-trips it through the graph", () => {
    mount(defaultGraph({ gotm: { enabled: true, year: 2026, month: 7, publish_at: "2026-07-01T10:30", brindes: [] } }));

    expect(document.querySelector("#f-gotm-publish-at").value).toBe("2026-07-01T10:30");

    setInput(document.querySelector("#f-name"), "Jogo");
    fire(document.querySelector("#ed-form"), "submit");
    expect(JSON.parse(document.querySelector("#f-graph").value).gotm.publish_at).toBe("2026-07-01T10:30");
  });

  it("moving to a later edition drafts the product and defaults its go-live time", () => {
    mount();
    const month = document.querySelector("#f-gotm-month");

    month.value = "9";
    fire(month, "change");

    expect(document.querySelector("#f-gotm-publish-at").value).toBe("2026-09-01T00:00");
    expect(document.querySelector("#f-published").checked).toBe(false);
    expect(document.querySelector("#gotm-publish-hint").hidden).toBe(false);
  });

  it("moving to the running edition leaves the publish state alone", () => {
    mount();
    const month = document.querySelector("#f-gotm-month");

    month.value = "6";
    fire(month, "change");

    expect(document.querySelector("#f-published").checked).toBe(true);
    expect(document.querySelector("#gotm-publish-hint").hidden).toBe(true);
  });

  it("a hand-picked go-live time survives an edition change", () => {
    mount();
    setInput(document.querySelector("#f-gotm-publish-at"), "2026-08-15T18:00");

    const year = document.querySelector("#f-gotm-year");
    year.value = "2027";
    fire(year, "change");

    expect(document.querySelector("#f-gotm-publish-at").value).toBe("2026-08-15T18:00");
    expect(document.querySelector("#f-published").checked).toBe(false);
  });
});
