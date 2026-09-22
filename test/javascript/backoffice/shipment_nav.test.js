import { beforeEach, describe, expect, it } from "vitest";
import { bindShipmentNav, initShipmentNav } from "../../../app/javascript/backoffice/shipment_nav.js";

// Mirrors the data hooks in app/views/admin/orders/_shipment_track.html.erb.
function panel(count, direction = "outbound") {
  const views = Array.from({ length: count }, (_, index) => `
    <div class="shv" data-shipment-view="${index}"${index === count - 1 ? "" : " hidden"}>
      ${index === count - 1 ? "" : '<button data-shipment-latest><i id="latest-icon-' + index + '"></i></button>'}
      <span>view ${index}</span>
    </div>`).join("");
  const nav = count > 1 ? `
    <button data-shipment-step="-1"><i id="prev-icon-${direction}"></i></button>
    <b data-shipment-pos>${count}</b>
    <button data-shipment-step="1" disabled></button>` : "";
  return `<div data-shipment-nav data-direction="${direction}">${nav}${views}</div>`;
}

function visible(root) {
  return [...root.querySelectorAll("[data-shipment-view]")].filter((view) => !view.hidden).map((view) => view.dataset.shipmentView);
}

function key(target, name) {
  target.dispatchEvent(new window.KeyboardEvent("keydown", { key: name, bubbles: true }));
}

describe("initShipmentNav", () => {
  let root;
  let nav;

  beforeEach(() => {
    document.body.innerHTML = panel(3);
    root = document.querySelector("[data-shipment-nav]");
    nav = initShipmentNav(root);
  });

  it("opens on the latest despatch", () => {
    expect(nav.current).toBe(2);
    expect(visible(root)).toEqual([ "2" ]);
  });

  it("steps back to an earlier despatch, sliding in from the left", () => {
    document.getElementById("prev-icon-outbound").click();

    expect(visible(root)).toEqual([ "1" ]);
    expect(root.querySelector('[data-shipment-view="1"]').classList.contains("from-left")).toBe(true);
    expect(root.querySelector("[data-shipment-pos]").textContent).toBe("2");
    expect(root.querySelector('[data-shipment-step="1"]').disabled).toBe(false);
    expect(root.querySelector('[data-shipment-step="-1"]').disabled).toBe(false);
  });

  it("disables the previous button on the first despatch", () => {
    nav.show(0);

    expect(root.querySelector('[data-shipment-step="-1"]').disabled).toBe(true);
    expect(root.querySelector("[data-shipment-pos]").textContent).toBe("1");
  });

  it("steps forward sliding in from the right, and stops at the latest", () => {
    nav.show(0);
    root.querySelector('[data-shipment-step="1"]').click();

    expect(visible(root)).toEqual([ "1" ]);
    const view = root.querySelector('[data-shipment-view="1"]');
    expect(view.classList.contains("from-right")).toBe(true);
    expect(view.classList.contains("from-left")).toBe(false);

    nav.show(2);
    expect(root.querySelector('[data-shipment-step="1"]').disabled).toBe(true);
  });

  it("jumps back to the latest from a past despatch", () => {
    nav.show(0);
    document.getElementById("latest-icon-0").click();

    expect(visible(root)).toEqual([ "2" ]);
  });

  it("ignores steps past either end and clicks elsewhere in the panel", () => {
    root.querySelector('[data-shipment-step="1"]').click();
    root.querySelector('[data-shipment-view="2"] span').click();
    nav.show(-1);

    expect(visible(root)).toEqual([ "2" ]);
  });

  it("follows the arrow keys", () => {
    const button = root.querySelector('[data-shipment-step="-1"]');
    key(button, "ArrowLeft");
    key(button, "ArrowLeft");
    expect(visible(root)).toEqual([ "0" ]);

    key(button, "ArrowRight");
    key(button, "Enter");
    expect(visible(root)).toEqual([ "1" ]);
  });
});

describe("bindShipmentNav", () => {
  it("binds only the panels that hold more than one despatch", () => {
    document.body.innerHTML = `<div id="root">${panel(2)}${panel(1, "inbound")}</div>`;

    const navs = bindShipmentNav(document.getElementById("root"));

    expect(navs).toHaveLength(1);
    expect(navs[0].current).toBe(1);
  });
});
