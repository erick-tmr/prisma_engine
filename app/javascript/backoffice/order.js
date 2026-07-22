export function bindConfirm(root) {
  root.querySelectorAll("form[data-confirm]").forEach((form) => {
    form.addEventListener("submit", (event) => {
      if (!window.confirm(form.dataset.confirm)) event.preventDefault();
    });
  });
}

export function bindMenu(root) {
  const toggle = root.querySelector("[data-menu-toggle]");
  const sidebar = root.querySelector("[data-sidebar]");
  toggle.addEventListener("click", () => sidebar.classList.toggle("show"));
}

export function bindFlashDismiss(root) {
  root.querySelectorAll("[data-flash-close]").forEach((button) => {
    button.addEventListener("click", () => {
      const flash = button.closest(".od-flash");
      if (flash) flash.remove();
    });
  });
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
