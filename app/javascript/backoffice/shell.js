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

export function bindGlobalSearch(root, input) {
  const gsearch = root.querySelector("#gsearch");
  if (!gsearch || !input) return;

  gsearch.addEventListener("input", (event) => {
    input.value = event.target.value;
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
}
