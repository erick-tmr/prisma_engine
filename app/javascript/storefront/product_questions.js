export function bindComposer(scope) {
  const input = scope.querySelector("[data-question-body]");
  if (!input) return;

  const counter = scope.querySelector("[data-question-counter]");
  const submit = scope.querySelector("[data-question-submit]");
  const minLength = parseInt(input.dataset.minLength, 10);

  function refresh() {
    counter.textContent = input.value.length + "/" + input.maxLength;
    submit.disabled = input.value.trim().length < minLength;
  }

  input.addEventListener("input", refresh);
  refresh();
}

export function moreLabel(button, count) {
  const template = count === 1 ? button.dataset.templateOne : button.dataset.templateOther;
  return template.replace("{n}", count);
}

export function bindReveal(scope) {
  const list = scope.querySelector("[data-question-list]");
  if (!list) return;

  const items = Array.from(list.querySelectorAll("[data-question-item]"));
  const more = scope.querySelector("[data-question-more]");
  const count = scope.querySelector("[data-question-count]");
  const pageSize = parseInt(list.dataset.pageSize, 10);
  let revealed = pageSize;

  function refresh() {
    items.forEach(function (item, index) { item.hidden = index >= revealed; });
    const shown = Math.min(revealed, items.length);
    const remaining = items.length - shown;
    count.textContent = count.dataset.template.replace("{n}", shown);
    more.hidden = remaining === 0;
    if (remaining > 0) more.textContent = moreLabel(more, remaining);
  }

  more.addEventListener("click", function () {
    revealed += pageSize;
    refresh();
  });

  refresh();
}

export function initProductQuestions(scope) {
  bindComposer(scope);
  bindReveal(scope);
}

/* v8 ignore start -- browser bootstrap */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-product-questions]");
  if (root) initProductQuestions(root);
}
/* v8 ignore stop */
