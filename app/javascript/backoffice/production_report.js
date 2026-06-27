export function initConfirmModal(root) {
  const modal = root.querySelector("[data-pr-modal]");
  if (!modal) return null;

  const open = root.querySelector("[data-pr-open]");
  const show = () => modal.removeAttribute("hidden");
  const hide = () => modal.setAttribute("hidden", "");
  open.addEventListener("click", show);
  root.querySelectorAll("[data-pr-close]").forEach((el) => el.addEventListener("click", hide));
  return { show, hide };
}

export function initPrint(root) {
  const button = root.querySelector("[data-pr-print]");
  if (!button) return;

  button.addEventListener("click", () => window.print());
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  initConfirmModal(document);
  initPrint(document);
}
/* v8 ignore stop */
