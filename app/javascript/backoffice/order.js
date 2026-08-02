import { bindConfirm, bindFlashDismiss } from "backoffice/shell";

export function bindMenu(root) {
  const toggle = root.querySelector("[data-menu-toggle]");
  const sidebar = root.querySelector("[data-sidebar]");
  toggle.addEventListener("click", () => sidebar.classList.toggle("show"));
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-bo-order]");
  if (root) {
    bindConfirm(root);
    bindMenu(root);
    bindFlashDismiss(root);
  }
}
/* v8 ignore stop */
