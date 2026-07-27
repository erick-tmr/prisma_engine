import { debounce } from "backoffice/table";

// Back and forward change the params without redrawing the filter bar, so the
// controls are rewound from the url rather than left showing the old query.
export function syncFilters(root, params) {
  root.querySelectorAll("[data-filter]").forEach((el) => {
    const value = params[el.dataset.filter] ?? "";
    if (el.value !== value) el.value = value;
  });
}

// Text inputs filter as you type; selects apply immediately.
export function bindFilters(root, table) {
  const inputs = Array.from(root.querySelectorAll("[data-filter]"));

  inputs.forEach((el) => {
    const key = el.dataset.filter;
    if (el.tagName === "SELECT") {
      el.addEventListener("change", () => table.set({ [key]: el.value }));
    } else {
      const apply = debounce(() => table.set({ [key]: el.value }));
      el.addEventListener("input", apply);
    }
  });

  return inputs;
}
