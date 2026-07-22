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

export function bindAddressForm(scope) {
  scope.querySelectorAll("[data-receiver-self]").forEach(function (toggle) {
    toggle.addEventListener("change", function () {
      const form = toggle.closest("form");
      setField(form, "receiver_name", toggle.checked ? form.dataset.userName : "");
      setField(form, "receiver_cpf", toggle.checked ? form.dataset.userCpf : "");
    });
  });

  scope.querySelectorAll("[data-mask-cep]").forEach(function (cep) {
    let last = cep.value.replace(/\D/g, "");
    if (last.length !== 8) last = null;

    cep.addEventListener("blur", async function () {
      const digits = cep.value.replace(/\D/g, "");
      if (digits.length !== 8 || digits === last) return;
      const form = cep.closest("form");
      const data = await lookupCep(form.dataset.cepLookupUrl, digits);
      if (!data) return;
      last = digits;
      ["street", "neighborhood", "city", "state"].forEach(function (field) {
        setField(form, field, data[field] || "");
      });
      const number = form.querySelector('[name="address[number]"]');
      if (number && !number.value) number.focus();
    });
  });
}

/* v8 ignore start -- browser bootstrap */
if (typeof document !== "undefined") bindAddressForm(document);
/* v8 ignore stop */
