import { beforeEach, describe, expect, it } from "vitest";
import { bindVariantPills } from "../../app/javascript/storefront/pdp.js";

// Mirrors app/views/products/show.html.erb: a [data-pdp-form] form with one
// hidden option_ids field per group and a row of [data-vpill] buttons per group.
function mountPdp() {
  document.body.innerHTML = `
    <form data-pdp-form>
      <input type="hidden" data-variant-group="lang" value="1">
      <input type="hidden" data-variant-group="box" value="10">
      <div class="variant-pills" data-group="lang">
        <button type="button" class="variant-pill is-selected" data-vpill data-vgroup="lang" data-vopt="1">PT</button>
        <button type="button" class="variant-pill" data-vpill data-vgroup="lang" data-vopt="2">EN</button>
      </div>
      <div class="variant-pills" data-group="box">
        <button type="button" class="variant-pill is-selected" data-vpill data-vgroup="box" data-vopt="10">Com caixa</button>
        <button type="button" class="variant-pill" data-vpill data-vgroup="box" data-vopt="11">Sem caixa</button>
      </div>
    </form>`;
  bindVariantPills(document);
}

describe("bindVariantPills", () => {
  beforeEach(mountPdp);

  it("selecting a pill updates the group's hidden field and the is-selected highlight", () => {
    document.querySelector('[data-vpill][data-vopt="2"]').dispatchEvent(new window.Event("click", { bubbles: true }));
    expect(document.querySelector('input[data-variant-group="lang"]').value).toBe("2");
    expect(document.querySelector('[data-vpill][data-vopt="2"]').classList.contains("is-selected")).toBe(true);
    expect(document.querySelector('[data-vpill][data-vopt="1"]').classList.contains("is-selected")).toBe(false);
  });

  it("only touches its own group, leaving the other group untouched", () => {
    document.querySelector('[data-vpill][data-vopt="2"]').dispatchEvent(new window.Event("click", { bubbles: true }));
    // 'box' group hidden + highlight unchanged
    expect(document.querySelector('input[data-variant-group="box"]').value).toBe("10");
    expect(document.querySelector('[data-vpill][data-vopt="10"]').classList.contains("is-selected")).toBe(true);
  });

  it("tolerates a missing hidden field (no throw, still toggles highlight)", () => {
    document.querySelector('input[data-variant-group="box"]').remove();
    const pill = document.querySelector('[data-vpill][data-vopt="11"]');
    expect(() => pill.dispatchEvent(new window.Event("click", { bubbles: true }))).not.toThrow();
    expect(pill.classList.contains("is-selected")).toBe(true);
  });
});
