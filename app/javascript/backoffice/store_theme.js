import { bindConfirm, bindFlashDismiss, initShell } from "backoffice/shell";

export function initStoreTheme(root) {
  initShell(root);
  bindConfirm(root);
  bindFlashDismiss(root);
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector('[data-list="store-theme"]');
  if (root) initStoreTheme(root);
}
/* v8 ignore stop */
