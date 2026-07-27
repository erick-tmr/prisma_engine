import { debounce } from "backoffice/table";

export function syncFilters(root, params) {
  root.querySelectorAll("[data-filter]").forEach((el) => {
    const value = params[el.dataset.filter] ?? "";
    if (el.value !== value) el.value = value;
  });
}

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
