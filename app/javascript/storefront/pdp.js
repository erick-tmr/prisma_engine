// Product detail page (PDP) behaviour, extracted from the inline view script so
// it can be unit tested (see test/javascript/pdp.test.js). Self-contained native
// ES module loaded via `javascript_include_tag "storefront/pdp", type: "module"`
// — no importmap, no build step. Keep in sync with app/views/products/show.html.erb.

// Variant pill selection: clicking a pill sets the matching hidden
// `option_ids[]` field (keyed by data-variant-group) and marks the pill as
// selected within its group.
export function bindVariantPills(scope) {
  scope.querySelectorAll("[data-pdp-form] [data-vpill]").forEach(function (pill) {
    pill.addEventListener("click", function () {
      const hidden = pill.closest("form").querySelector(
        'input[data-variant-group="' + CSS.escape(pill.dataset.vgroup) + '"]'
      );
      if (hidden) hidden.value = pill.dataset.vopt;
      pill.parentElement.querySelectorAll("[data-vpill]").forEach(function (p) {
        p.classList.toggle("is-selected", p === pill);
      });
    });
  });
}

/* v8 ignore start -- browser bootstrap */
if (typeof document !== "undefined") bindVariantPills(document);
/* v8 ignore stop */
