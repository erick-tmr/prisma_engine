function setOpen(item, button, open) {
  item.classList.toggle("is-open", open);
  button.setAttribute("aria-expanded", String(open));
}

export function bindAccordion(scope) {
  scope.querySelectorAll("[data-faq-item]").forEach(function (item, idx) {
    const button = item.querySelector("[data-faq-toggle]");
    setOpen(item, button, idx === 0);
    button.addEventListener("click", function () {
      setOpen(item, button, !item.classList.contains("is-open"));
    });
  });
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-faq]");
  if (root) {
    bindAccordion(root);
  }
}
/* v8 ignore stop */
