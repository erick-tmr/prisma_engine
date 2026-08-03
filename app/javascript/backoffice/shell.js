export function dismissToasts(root, delay = 3600) {
  root.querySelectorAll("[data-toast]").forEach((toast) => {
    setTimeout(() => toast.remove(), delay);
  });
}

export function initShell(root, doc = document) {
  const toggle = root.querySelector("#menu-toggle");
  const sidebar = root.querySelector("[data-sidebar]");
  if (toggle && sidebar) {
    toggle.addEventListener("click", () => sidebar.classList.toggle("show"));
  }
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
