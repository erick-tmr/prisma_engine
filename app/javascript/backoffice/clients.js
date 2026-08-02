import { createTable } from "backoffice/table";
import { bindFilters, syncFilters } from "backoffice/filters";
import { initShell } from "backoffice/shell";

export function initClients(root) {
  const table = createTable(root, { onRestore: (params) => syncFilters(root, params) });
  initShell(root);
  bindFilters(root, table);

  root.addEventListener("click", (event) => {
    const row = event.target.closest("tr[data-client]");
    const link = row?.querySelector("a.cell-link");
    if (link && link !== event.target) link.click();
  });

  return table;
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector('[data-list="clients"]');
  if (root) initClients(root);
}
/* v8 ignore stop */
