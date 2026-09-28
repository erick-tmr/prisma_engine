export const COPIED_MS = 1600;

function priceSlot(form) {
  return form.querySelector("[data-return-quote-price]");
}

function customerPays(form) {
  return form.querySelector('[data-return-payer="customer"]').checked;
}

function showPrice(slot, price) {
  slot.classList.toggle("is-unavailable", !price);
  slot.textContent = price ? price.price_formatted : slot.dataset.unavailable;
}

export function bindReturnFreight(root, { fetchFn = fetch, clipboard = navigator.clipboard } = {}) {
  const quotes = new Map();

  function loadQuote(url) {
    if (!quotes.has(url)) {
      const request = fetchFn(url, { headers: { Accept: "application/json" } })
        .then((res) => {
          if (!res.ok) throw new Error(String(res.status));
          return res.json();
        })
        .catch(() => {
          quotes.delete(url);
          return null;
        });
      quotes.set(url, request);
    }
    return quotes.get(url);
  }

  async function refreshPrice(form) {
    if (!customerPays(form)) return;

    const slot = priceSlot(form);
    slot.classList.remove("is-unavailable");
    slot.textContent = slot.dataset.loading;
    const prices = await loadQuote(form.dataset.quoteUrl);
    showPrice(slot, prices?.[form.querySelector("[data-return-service]").value]);
  }

  function copy(button) {
    const text = button.parentElement.querySelector("[data-copy-source]").textContent.trim();
    const label = button.querySelector("[data-copy-text]");
    const original = label.textContent;
    const flash = () => {
      button.classList.add("is-copied");
      label.textContent = button.dataset.copiedLabel;
      setTimeout(() => {
        button.classList.remove("is-copied");
        label.textContent = original;
      }, COPIED_MS);
    };
    const write = clipboard ? clipboard.writeText(text) : Promise.resolve();
    return write.then(flash, flash);
  }

  root.addEventListener("change", (event) => {
    const form = event.target.closest("[data-return-form]");
    if (form && event.target.matches("[data-return-payer], [data-return-service]")) refreshPrice(form);
  });

  root.addEventListener("click", (event) => {
    const button = event.target.closest("[data-copy-link]");
    if (button) copy(button);
  });

  root.querySelectorAll("[data-return-form]").forEach(refreshPrice);
}
