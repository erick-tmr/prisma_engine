import { createTable } from "backoffice/table";
import { initShell } from "backoffice/shell";

export function initReports(root) {
  const table = createTable(root);
  initShell(root);

  root.addEventListener("click", (event) => {
    const row = event.target.closest("tr[data-report]");
    const link = row?.querySelector("a.cell-link");
    if (link && link !== event.target) link.click();
  });

  return table;
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector('[data-list="reports"]');
  if (root) initReports(root);
}
/* v8 ignore stop */
