export const COPIED_MS = 1600;

function writeClipboard(text) {
  if (navigator.clipboard) {
    return navigator.clipboard.writeText(text);
  }
  return Promise.resolve();
}

export function bindCopy(root) {
  const button = root.querySelector("[data-tracking-copy]");
  const value = root.querySelector("[data-tracking-code]");
  if (!button || !value) return;

  const icon = button.querySelector("i");

  button.addEventListener("click", function () {
    const restore = function () {
      button.classList.add("is-copied");
      icon.className = "bi bi-check2";
      setTimeout(function () {
        button.classList.remove("is-copied");
        icon.className = "bi bi-clipboard";
      }, COPIED_MS);
    };
    writeClipboard(value.textContent.trim()).then(restore, restore);
  });
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  document.querySelectorAll("[data-order-tracking]").forEach(bindCopy);
}
/* v8 ignore stop */
