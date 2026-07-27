import { createTable } from "backoffice/table";
import { bindFilters, syncFilters } from "backoffice/filters";
import { bindGlobalSearch, initShell } from "backoffice/shell";

export function initClients(root) {
  const table = createTable(root, { onRestore: (params) => syncFilters(root, params) });
  initShell(root);
  bindFilters(root, table);
  bindGlobalSearch(root, root.querySelector("#c-q"));
  return table;
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector('[data-list="clients"]');
  if (root) initClients(root);
}
/* v8 ignore stop */
