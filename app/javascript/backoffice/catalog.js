import { createTable } from "backoffice/table";
import { bindFilters, syncFilters } from "backoffice/filters";
import { bindGlobalSearch, initShell } from "backoffice/shell";

export function navigate(href) {
  window.location.assign(href);
}

export function initCatalog(root) {
  const table = createTable(root, { onRestore: (params) => syncFilters(root, params) });
  initShell(root);
  bindFilters(root, table);
  bindGlobalSearch(root, root.querySelector("#c-q"));

  root.addEventListener("click", (event) => {
    if (event.target.closest("a")) return;
    const row = event.target.closest("tr[data-row]");
    if (row) navigate(row.dataset.href);
  });

  return table;
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector('[data-list="catalog"]');
  if (root) initCatalog(root);
}
/* v8 ignore stop */
