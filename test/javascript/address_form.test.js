import { afterEach, describe, expect, it, vi } from "vitest";
import { bindAddressForm } from "../../app/javascript/storefront/address_form.js";

function mountAddressForm({ zip = "", number = "" } = {}) {
  document.body.innerHTML = `
    <form data-user-name="João Silva" data-user-cpf="123.456.789-09"
          data-cep-lookup-url="/minha-conta/enderecos/cep">
      <input type="checkbox" data-receiver-self>
      <input name="address[receiver_name]">
      <input name="address[receiver_cpf]">
      <input name="address[zip]" data-mask-cep value="${zip}">
      <input name="address[street]">
      <input name="address[number]" value="${number}">
      <input name="address[neighborhood]">
      <input name="address[city]">
      <select name="address[state]">
        <option value=""></option>
        <option value="SP">SP</option>
        <option value="MG">MG</option>
      </select>
    </form>`;
  bindAddressForm(document);
  return document.querySelector("form");
}

const tick = () => new Promise((r) => setTimeout(r, 0));
const CEP = { street: "Av. Paulista", neighborhood: "Bela Vista", city: "São Paulo", state: "SP" };
const blur = (form) =>
  form.querySelector("[data-mask-cep]").dispatchEvent(new window.Event("blur", { bubbles: true }));
const val = (form, field) => form.querySelector('[name="address[' + field + ']"]').value;

describe("bindAddressForm: receiver self", () => {
  it("fills name + CPF from the form data attrs when checked, clears when unchecked", () => {
    const form = mountAddressForm();
    const toggle = form.querySelector("[data-receiver-self]");

    toggle.checked = true;
    toggle.dispatchEvent(new window.Event("change", { bubbles: true }));
    expect(val(form, "receiver_name")).toBe("João Silva");
    expect(val(form, "receiver_cpf")).toBe("123.456.789-09");

    toggle.checked = false;
    toggle.dispatchEvent(new window.Event("change", { bubbles: true }));
    expect(val(form, "receiver_name")).toBe("");
    expect(val(form, "receiver_cpf")).toBe("");
  });
});

describe("bindAddressForm: CEP lookup", () => {
  afterEach(() => vi.restoreAllMocks());

  it("does not look up a CEP shorter than 8 digits", () => {
    const form = mountAddressForm();
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    form.querySelector("[data-mask-cep]").value = "0131";
    blur(form);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("does not re-fetch the on-load baseline CEP (edit flow)", () => {
    const form = mountAddressForm({ zip: "01310-100" });
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    blur(form);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("looks up a new CEP, fills the address, and focuses the empty number", async () => {
    const form = mountAddressForm();
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => CEP });
    vi.stubGlobal("fetch", fetchMock);
    form.querySelector("[data-mask-cep]").value = "01310-100";
    blur(form);
    await tick();

    expect(fetchMock.mock.calls[0][0]).toBe("/minha-conta/enderecos/cep/01310100");
    expect(val(form, "street")).toBe("Av. Paulista");
    expect(val(form, "neighborhood")).toBe("Bela Vista");
    expect(val(form, "city")).toBe("São Paulo");
    expect(val(form, "state")).toBe("SP");
    expect(document.activeElement).toBe(form.querySelector('[name="address[number]"]'));
  });

  it("clears stale fields when the response is sparse (town-wide CEP)", async () => {
    const form = mountAddressForm();
    form.querySelector('[name="address[street]"]').value = "Rua Velha";
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ city: "Itajubá", state: "MG" }) }));
    form.querySelector("[data-mask-cep]").value = "37500-000";
    blur(form);
    await tick();
    expect(val(form, "street")).toBe("");
    expect(val(form, "city")).toBe("Itajubá");
  });

  it("leaves a filled number field alone", async () => {
    const form = mountAddressForm({ number: "42" });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => CEP }));
    form.querySelector("[data-mask-cep]").value = "01310-100";
    blur(form);
    await tick();
    expect(document.activeElement).not.toBe(form.querySelector('[name="address[number]"]'));
  });

  it("ignores a non-ok response", async () => {
    const form = mountAddressForm();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, json: async () => ({}) }));
    form.querySelector("[data-mask-cep]").value = "01310-100";
    blur(form);
    await tick();
    expect(val(form, "street")).toBe("");
  });

  it("swallows a network error", async () => {
    const form = mountAddressForm();
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));
    form.querySelector("[data-mask-cep]").value = "01310-100";
    blur(form);
    await tick();
    expect(val(form, "street")).toBe("");
  });

  it("tolerates a missing number field and missing target fields", async () => {
    const form = mountAddressForm();
    form.querySelector('[name="address[number]"]').remove();
    form.querySelector('[name="address[state]"]').remove();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => CEP }));
    form.querySelector("[data-mask-cep]").value = "01310-100";
    blur(form);
    await tick();
    expect(val(form, "city")).toBe("São Paulo");
  });
});
