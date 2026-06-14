import { beforeEach, describe, expect, it } from "vitest";
import {
  bindCountdown,
  bindGallery,
  bindStepper,
  bindVariantPills,
  clampQty,
  computeUnitPriceCents,
  countdownText,
  formatPriceCents,
  initPdp,
  updatePrice,
} from "../../app/javascript/storefront/pdp.js";

function fire(el, type) {
  el.dispatchEvent(new window.Event(type, { bubbles: true }));
}

// Mirrors app/views/products/show.html.erb: a .buy box with a [data-price]
// element and a [data-pdp-form] carrying base price, hidden option fields,
// variant pills (with deltas), and a quantity stepper.
function mountPdp() {
  document.body.innerHTML = `
    <div class="buy">
      <span data-price>R$ 180.00</span>
      <form data-pdp-form data-base-cents="18000">
        <input type="hidden" data-variant-group="Idioma" value="1">
        <input type="hidden" data-variant-group="Caixa" value="10">
        <div class="variant-group">
          <div class="variant-group__label">Idioma <span data-vsel="Idioma">Inglês</span></div>
          <div class="variant-pills">
            <button type="button" class="variant-pill is-selected" data-vpill data-vgroup="Idioma" data-vopt="1" data-vname="Inglês" data-delta="0">Inglês</button>
            <button type="button" class="variant-pill" data-vpill data-vgroup="Idioma" data-vopt="2" data-vname="Português BR" data-delta="2000">Português BR</button>
          </div>
        </div>
        <div class="variant-group">
          <div class="variant-group__label">Caixa <span data-vsel="Caixa">Sem caixa</span></div>
          <div class="variant-pills">
            <button type="button" class="variant-pill is-selected" data-vpill data-vgroup="Caixa" data-vopt="10" data-vname="Sem caixa" data-delta="0">Sem caixa</button>
            <button type="button" class="variant-pill" data-vpill data-vgroup="Caixa" data-vopt="11" data-vname="Com caixa" data-delta="2000">Com caixa</button>
          </div>
        </div>
        <div class="stepper">
          <button type="button" data-dec disabled></button>
          <input type="number" value="1" min="1" max="99" data-qty>
          <button type="button" data-inc></button>
        </div>
      </form>
    </div>`;
}

const $ = (sel) => document.querySelector(sel);

describe("formatPriceCents", () => {
  it("renders cents the way HasMoney does (R$ 0.00, no thousands separator)", () => {
    expect(formatPriceCents(18000)).toBe("R$ 180.00");
    expect(formatPriceCents(0)).toBe("R$ 0.00");
    expect(formatPriceCents(1234)).toBe("R$ 12.34");
    expect(formatPriceCents(180000)).toBe("R$ 1800.00");
  });
});

describe("clampQty", () => {
  it("keeps a value already in range", () => {
    expect(clampQty("5")).toBe(5);
    expect(clampQty("1")).toBe(1);
    expect(clampQty("99")).toBe(99);
  });

  it("floors non-positive or unparseable input to 1", () => {
    expect(clampQty("0")).toBe(1);
    expect(clampQty("-3")).toBe(1);
    expect(clampQty("abc")).toBe(1);
  });

  it("caps above 99", () => {
    expect(clampQty("150")).toBe(99);
  });
});

describe("computeUnitPriceCents", () => {
  beforeEach(mountPdp);

  it("is the base price when only zero-delta options are selected", () => {
    expect(computeUnitPriceCents($("[data-pdp-form]"))).toBe(18000);
  });

  it("adds the deltas of the selected pills", () => {
    $('[data-vpill][data-vopt="11"]').classList.add("is-selected");
    expect(computeUnitPriceCents($("[data-pdp-form]"))).toBe(20000);
  });

  it("treats a missing base as zero and ignores unparseable deltas", () => {
    document.body.innerHTML = `
      <form data-pdp-form>
        <button class="variant-pill is-selected" data-delta="500"></button>
        <button class="variant-pill is-selected" data-delta="oops"></button>
      </form>`;
    expect(computeUnitPriceCents($("[data-pdp-form]"))).toBe(500);
  });
});

describe("updatePrice", () => {
  beforeEach(mountPdp);

  it("writes base × quantity into [data-price]", () => {
    const form = $("[data-pdp-form]");
    updatePrice(form);
    expect($("[data-price]").textContent).toBe("R$ 180.00");
    $("[data-qty]").value = "2";
    updatePrice(form);
    expect($("[data-price]").textContent).toBe("R$ 360.00");
  });

  it("defaults quantity to 1 when there is no qty input", () => {
    document.body.innerHTML = `
      <span data-price></span>
      <form data-pdp-form data-base-cents="5000"></form>`;
    updatePrice($("[data-pdp-form]"));
    expect($("[data-price]").textContent).toBe("R$ 50.00");
  });

  it("does nothing (no throw) when there is no price element", () => {
    document.body.innerHTML = `<form data-pdp-form data-base-cents="5000"></form>`;
    expect(() => updatePrice($("[data-pdp-form]"))).not.toThrow();
  });
});

describe("bindVariantPills", () => {
  beforeEach(() => {
    mountPdp();
    bindVariantPills(document);
  });

  it("updates the group's hidden field, highlight, label, and price", () => {
    fire($('[data-vpill][data-vopt="2"]'), "click");
    expect($('input[data-variant-group="Idioma"]').value).toBe("2");
    expect($('[data-vpill][data-vopt="2"]').classList.contains("is-selected")).toBe(true);
    expect($('[data-vpill][data-vopt="1"]').classList.contains("is-selected")).toBe(false);
    expect($('[data-vsel="Idioma"]').textContent).toBe("Português BR");
    expect($("[data-price]").textContent).toBe("R$ 200.00");
  });

  it("only touches its own group", () => {
    fire($('[data-vpill][data-vopt="2"]'), "click");
    expect($('input[data-variant-group="Caixa"]').value).toBe("10");
    expect($('[data-vpill][data-vopt="10"]').classList.contains("is-selected")).toBe(true);
  });

  it("tolerates a missing hidden field and a missing label", () => {
    $('input[data-variant-group="Caixa"]').remove();
    $('[data-vsel="Caixa"]').remove();
    const pill = $('[data-vpill][data-vopt="11"]');
    expect(() => fire(pill, "click")).not.toThrow();
    expect(pill.classList.contains("is-selected")).toBe(true);
  });
});

describe("bindStepper", () => {
  beforeEach(() => {
    mountPdp();
    bindStepper(document);
  });

  it("increments, re-prices, and enables the − button", () => {
    fire($("[data-inc]"), "click");
    expect($("[data-qty]").value).toBe("2");
    expect($("[data-dec]").disabled).toBe(false);
    expect($("[data-price]").textContent).toBe("R$ 360.00");
  });

  it("holds at the floor of 1 and keeps the − button disabled", () => {
    fire($("[data-dec]"), "click");
    expect($("[data-qty]").value).toBe("1");
    expect($("[data-dec]").disabled).toBe(true);
  });

  it("clamps a direct edit on change", () => {
    $("[data-qty]").value = "0";
    fire($("[data-qty]"), "change");
    expect($("[data-qty]").value).toBe("1");
  });

  it("no-ops when the form has no quantity input", () => {
    document.body.innerHTML = `<form data-pdp-form data-base-cents="100"></form>`;
    expect(() => bindStepper(document)).not.toThrow();
  });

  it("still binds the change handler when there are no − / + buttons", () => {
    document.body.innerHTML = `
      <span data-price></span>
      <form data-pdp-form data-base-cents="9000">
        <input data-qty value="3">
      </form>`;
    bindStepper(document);
    $("[data-qty]").value = "150";
    fire($("[data-qty]"), "change");
    expect($("[data-qty]").value).toBe("99");
  });
});

describe("bindGallery", () => {
  function mountGallery() {
    document.body.innerHTML = `
      <div class="gallery">
        <a href="/a.jpg" data-main-zoom><img src="/a.jpg" data-main-img></a>
        <button data-thumb data-src="/a.jpg" class="is-selected"></button>
        <button data-thumb data-src="/b.jpg"></button>
        <button data-thumb></button>
      </div>`;
    bindGallery(document);
  }

  beforeEach(mountGallery);

  it("swaps the main image and zoom link, moving the selection", () => {
    fire(document.querySelectorAll("[data-thumb]")[1], "click");
    expect($("[data-main-img]").getAttribute("src")).toBe("/b.jpg");
    expect($("[data-main-zoom]").getAttribute("href")).toBe("/b.jpg");
    expect(document.querySelectorAll("[data-thumb]")[1].classList.contains("is-selected")).toBe(true);
    expect(document.querySelectorAll("[data-thumb]")[0].classList.contains("is-selected")).toBe(false);
  });

  it("ignores a thumb with no source", () => {
    const before = $("[data-main-img]").getAttribute("src");
    fire(document.querySelectorAll("[data-thumb]")[2], "click");
    expect($("[data-main-img]").getAttribute("src")).toBe(before);
  });

  it("tolerates a missing main image and zoom link", () => {
    document.body.innerHTML = `<div><button data-thumb data-src="/b.jpg"></button></div>`;
    bindGallery(document);
    expect(() => fire($("[data-thumb]"), "click")).not.toThrow();
  });
});

describe("countdownText", () => {
  it("reports days and hours, pluralising days", () => {
    expect(countdownText(2 * 86400000 + 3 * 3600000)).toBe("termina em 2 dias e 3h");
    expect(countdownText(1 * 86400000 + 5 * 3600000)).toBe("termina em 1 dia e 5h");
  });

  it("reports just hours under a day", () => {
    expect(countdownText(4 * 3600000)).toBe("termina em 4h");
  });

  it("is closed once the deadline passes", () => {
    expect(countdownText(0)).toBe("edição encerrada");
    expect(countdownText(-1000)).toBe("edição encerrada");
  });
});

describe("bindCountdown", () => {
  it("fills the deadline text from the edition's end of month", () => {
    document.body.innerHTML = `
      <div data-gotm-countdown data-gotm-year="2026" data-gotm-month="6">
        <b data-countdown-text></b>
      </div>`;
    // End of June 2026 is the 30th 23:59:59; two days before is the 28th.
    bindCountdown(document, new Date(2026, 5, 28, 23, 59, 59));
    expect($("[data-countdown-text]").textContent).toBe("termina em 2 dias e 0h");
  });

  it("no-ops when the countdown text node is absent", () => {
    document.body.innerHTML = `<div data-gotm-countdown data-gotm-year="2026" data-gotm-month="6"></div>`;
    expect(() => bindCountdown(document, new Date(2026, 5, 28))).not.toThrow();
  });
});

describe("initPdp", () => {
  it("wires every behaviour and renders the initial price", () => {
    document.body.innerHTML = `
      <div class="buy">
        <span data-price></span>
        <form data-pdp-form data-base-cents="18000">
          <input type="hidden" data-variant-group="Idioma" value="1">
          <div class="variant-pills">
            <button type="button" class="variant-pill is-selected" data-vpill data-vgroup="Idioma" data-vopt="1" data-vname="Inglês" data-delta="0">Inglês</button>
            <button type="button" class="variant-pill" data-vpill data-vgroup="Idioma" data-vopt="2" data-vname="Português BR" data-delta="2000">Português BR</button>
          </div>
          <input type="number" value="1" data-qty>
          <button type="button" data-inc></button>
        </form>
      </div>
      <div data-gotm-countdown data-gotm-year="2026" data-gotm-month="6"><b data-countdown-text></b></div>`;
    initPdp(document, new Date(2026, 5, 28, 23, 59, 59));
    expect($("[data-price]").textContent).toBe("R$ 180.00");
    expect($("[data-countdown-text]").textContent).toBe("termina em 2 dias e 0h");
    fire($('[data-vpill][data-vopt="2"]'), "click");
    expect($("[data-price]").textContent).toBe("R$ 200.00");
  });
});
