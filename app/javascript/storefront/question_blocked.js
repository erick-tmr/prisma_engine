export function initQuestionBlocked(modal, form) {
  const card = modal.querySelector("[data-question-blocked-card]");
  const submit = form.querySelector("[data-question-submit]");

  function open() {
    modal.classList.add("is-open");
    modal.setAttribute("aria-hidden", "false");
    document.body.style.overflow = "hidden";
    card.focus({ preventScroll: true });
  }

  function close() {
    modal.classList.remove("is-open");
    modal.setAttribute("aria-hidden", "true");
    document.body.style.overflow = "";
    submit.focus();
  }

  form.addEventListener("submit", function (event) {
    event.preventDefault();
    open();
  });

  modal.querySelectorAll("[data-question-blocked-close]").forEach(function (button) {
    button.addEventListener("click", close);
  });

  modal.addEventListener("click", function (event) {
    if (event.target === modal) close();
  });

  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape" && modal.classList.contains("is-open")) close();
  });

  return { open, close };
}

/* v8 ignore start -- browser bootstrap; initQuestionBlocked is unit-tested */
if (typeof document !== "undefined") {
  const modal = document.querySelector("[data-question-blocked]");
  const form = document.querySelector("[data-question-form]");
  if (modal && form) initQuestionBlocked(modal, form);
}
/* v8 ignore stop */
