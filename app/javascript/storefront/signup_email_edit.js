export function createSignupEmailEdit(root) {
  const view = root.querySelector("[data-email-edit-view]");
  const form = root.querySelector("[data-email-edit-form]");
  const input = form.querySelector('input[type="email"]');
  const openButton = root.querySelector("[data-email-edit-open]");
  const cancelButton = root.querySelector("[data-email-edit-cancel]");

  function open() {
    view.hidden = true;
    form.hidden = false;
    input.focus();
    input.select();
  }

  function close() {
    input.value = input.defaultValue;
    form.hidden = true;
    view.hidden = false;
    openButton.focus();
  }

  openButton.addEventListener("click", open);
  cancelButton.addEventListener("click", close);
  form.addEventListener("keydown", (event) => {
    if (event.key === "Escape") close();
  });

  return { open, close };
}

/* v8 ignore start -- browser bootstrap; createSignupEmailEdit is unit-tested */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-email-edit]");
  if (root) createSignupEmailEdit(root);
}
/* v8 ignore stop */
