// Account address form behaviour, a vanilla rewrite of the inline jQuery script
// so it can be unit tested (see test/javascript/address_form.test.js). Loaded via
// `javascript_include_tag "storefront/address_form", type: "module"`. The CEP
// field's *masking* still comes from the layout's global jQuery mask plugin; this
// module only adds the receiver-self autofill and the CEP-blur address lookup.
// Keep in sync with app/views/account/addresses/_form.html.erb.

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
  // "Eu mesmo(a) recebo" → fill the receiver name/CPF from the form's data attrs.
  scope.querySelectorAll("[data-receiver-self]").forEach(function (toggle) {
    toggle.addEventListener("change", function () {
      const form = toggle.closest("form");
      setField(form, "receiver_name", toggle.checked ? form.dataset.userName : "");
      setField(form, "receiver_cpf", toggle.checked ? form.dataset.userCpf : "");
    });
  });

  // CEP blur → look the address up and fill street/neighborhood/city/state.
  scope.querySelectorAll("[data-mask-cep]").forEach(function (cep) {
    // Treat a CEP already in the field on load (edit flow) as the baseline —
    // don't refetch unless the customer actually changes it.
    let last = cep.value.replace(/\D/g, "");
    if (last.length !== 8) last = null;

    cep.addEventListener("blur", async function () {
      const digits = cep.value.replace(/\D/g, "");
      if (digits.length !== 8 || digits === last) return;
      const form = cep.closest("form");
      const data = await lookupCep(form.dataset.cepLookupUrl, digits);
      if (!data) return;
      last = digits;
      // Always replace — a sparse (town-wide) response would otherwise leave
      // stale values from the previous CEP behind.
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
