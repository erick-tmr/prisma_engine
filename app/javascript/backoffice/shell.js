export function dismissToasts(root, delay = 3600) {
  root.querySelectorAll("[data-toast]").forEach((toast) => {
    setTimeout(() => toast.remove(), delay);
  });
}

export const MOBILE_NAV_MAX_WIDTH = 820;

export function bindSidebar(toggle, sidebar, doc = document) {
  if (!toggle || !sidebar) return;

  const close = () => sidebar.classList.remove("show");
  toggle.addEventListener("click", () => sidebar.classList.toggle("show"));
  doc.addEventListener("click", (event) => {
    if (!sidebar.classList.contains("show")) return;
    if (sidebar.contains(event.target) || toggle.contains(event.target)) return;

    close();
  });
  doc.addEventListener("keydown", (event) => {
    if (event.key === "Escape") close();
  });
  doc.defaultView.addEventListener("resize", () => {
    if (doc.defaultView.innerWidth > MOBILE_NAV_MAX_WIDTH) close();
  });
}

export function initShell(root, doc = document) {
  bindSidebar(root.querySelector("#menu-toggle"), root.querySelector("[data-sidebar]"), doc);
  dismissToasts(doc);
}

export function bindConfirm(root) {
  root.querySelectorAll("form[data-confirm]").forEach((form) => {
    form.addEventListener("submit", (event) => {
      if (!window.confirm(form.dataset.confirm)) event.preventDefault();
    });
  });
}

export function bindFlashDismiss(root) {
  root.querySelectorAll("[data-flash-close]").forEach((button) => {
    button.addEventListener("click", () => {
      const flash = button.closest(".od-flash");
      if (flash) flash.remove();
    });
  });
}
