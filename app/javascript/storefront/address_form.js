const MASKS = {
  cpf: { limit: 11, groups: [ 3, 3, 3, 2 ], separators: [ ".", ".", "-" ] },
  cep: { limit: 8, groups: [ 5, 3 ], separators: [ "-" ] }
};

export function mask(raw, spec) {
  const digits = String(raw == null ? "" : raw).replace(/\D/g, "").slice(0, spec.limit);
  let out = "";
  let at = 0;
  spec.groups.forEach(function (size, index) {
    if (at >= digits.length) return;
    if (index > 0) out += spec.separators[index - 1];
    out += digits.slice(at, at + size);
    at += size;
  });
  return out;
}

export const maskCpf = (raw) => mask(raw, MASKS.cpf);
export const maskCep = (raw) => mask(raw, MASKS.cep);

export function caretAfterDigits(masked, count) {
  if (count === 0) return 0;
  let seen = 0;
  for (let i = 0; i < masked.length; i += 1) {
    if (!/\d/.test(masked[i])) continue;
    seen += 1;
    if (seen === count) return i + 1;
  }
  return masked.length;
}

function bindMask(input, spec) {
  const apply = function () {
    const typed = input.value.slice(0, input.selectionStart).replace(/\D/g, "").length;
    input.value = mask(input.value, spec);
    const caret = caretAfterDigits(input.value, typed);
    input.setSelectionRange(caret, caret);
  };
  apply();
  input.addEventListener("input", apply);
}

function setField(form, field, value) {
  const input = form.querySelector('[name="address[' + field + ']"]');
  if (input) input.value = value;
}

async function lookupCep(baseUrl, digits) {
  try {
    const res = await fetch(baseUrl + "/" + digits, { headers: { Accept: "application/json" } });
    return res.ok ? await res.json() : null;
  } catch (e) {
    return null;
  }
}

function bindCepLookup(cep) {
  let last = cep.value.replace(/\D/g, "");
  if (last.length !== 8) last = null;

  cep.addEventListener("blur", async function () {
    const digits = cep.value.replace(/\D/g, "");
    if (digits.length !== 8 || digits === last) return;
    const form = cep.closest("form");
    const data = await lookupCep(form.dataset.cepLookupUrl, digits);
    if (!data) return;
    last = digits;
    [ "street", "neighborhood", "city", "state" ].forEach(function (field) {
      setField(form, field, data[field] || "");
    });
    const number = form.querySelector('[name="address[number]"]');
    if (number && !number.value) number.focus();
  });
}

export function bindAddressForm(scope) {
  scope.querySelectorAll("[data-addr-cpf]").forEach(function (input) {
    bindMask(input, MASKS.cpf);
  });

  scope.querySelectorAll("[data-addr-cep]").forEach(function (cep) {
    bindMask(cep, MASKS.cep);
    bindCepLookup(cep);
  });

  scope.querySelectorAll("[data-receiver-self]").forEach(function (toggle) {
    toggle.addEventListener("change", function () {
      const form = toggle.closest("form");
      setField(form, "receiver_name", toggle.checked ? form.dataset.userName : "");
      setField(form, "receiver_cpf", toggle.checked ? maskCpf(form.dataset.userCpf) : "");
    });
  });
}

/* v8 ignore start -- browser bootstrap */
if (typeof document !== "undefined") bindAddressForm(document);
/* v8 ignore stop */
