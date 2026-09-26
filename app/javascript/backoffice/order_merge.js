export const OPEN_CLASS = "is-open";
export const PREVIEW_FAILED = "Não foi possível montar a prévia da mesclagem. Tente novamente.";

export function formatBRL(cents) {
  const value = (cents / 100).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return `R$ ${value}`;
}

export function plural(panel, key, count) {
  const template = count === 1 ? panel.dataset[`${key}One`] : panel.dataset[`${key}Other`];
  return template.replace("{n}", String(count));
}

export function selection(panel) {
  const rows = Array.from(panel.querySelectorAll("[data-merge-pick]:checked"), (input) => input.closest("[data-merge-row]"));
  return {
    count: rows.length,
    items: rows.reduce((sum, row) => sum + Number(row.dataset.items), 0),
    cents: rows.reduce((sum, row) => sum + Number(row.dataset.subtotalCents), 0)
  };
}

export function summarize(panel) {
  const picked = selection(panel);
  const title = panel.querySelector("[data-merge-title]");
  const summary = panel.querySelector("[data-merge-summary]");
  const any = picked.count > 0;

  title.textContent = any ? plural(panel, "picked", picked.count) : panel.dataset.pick;
  summary.textContent = any
    ? panel.dataset.adds.replace("{items}", plural(panel, "items", picked.items)).replace("{amount}", formatBRL(picked.cents))
    : panel.dataset.stays;
  panel.querySelector("[data-merge-open]").disabled = !any;
  panel.querySelector("[data-merge-clear]").hidden = !any;
  return picked;
}

export function bindMergePanel(panel, host, { doc = document, frame = (fn) => requestAnimationFrame(fn) } = {}) {
  if (!panel || !host || !panel.querySelector("[data-merge-open]")) return null;

  const form = panel.querySelector("[data-merge-form]");

  function onKey(event) {
    if (event.key === "Escape") close();
  }

  function close() {
    host.replaceChildren();
    doc.removeEventListener("keydown", onKey);
  }

  function show(html) {
    const overlay = new DOMParser().parseFromString(html, "text/html").querySelector("[data-merge-overlay]");
    host.replaceChildren(overlay);
    doc.addEventListener("keydown", onKey);
    frame(() => overlay.classList.add(OPEN_CLASS));
    (overlay.querySelector("[data-merge-confirm]") || overlay.querySelector("[data-merge-close]")).focus();
  }

  async function preview() {
    try {
      const response = await fetch(panel.dataset.previewUrl, {
        method: "POST",
        body: new FormData(form),
        headers: { "X-CSRF-Token": doc.querySelector('meta[name="csrf-token"]')?.content ?? "", "X-Requested-With": "fetch" }
      });
      if (!response.ok) throw new Error(String(response.status));

      show(await response.text());
    } catch (e) {
      window.alert(PREVIEW_FAILED);
    }
  }

  panel.addEventListener("change", (event) => {
    if (event.target.matches("[data-merge-pick]")) summarize(panel);
  });
  panel.querySelector("[data-merge-clear]").addEventListener("click", () => {
    panel.querySelectorAll("[data-merge-pick]").forEach((input) => { input.checked = false; });
    summarize(panel);
  });
  panel.querySelector("[data-merge-open]").addEventListener("click", preview);
  host.addEventListener("click", (event) => {
    if (event.target.matches("[data-merge-overlay]") || event.target.closest("[data-merge-close]")) close();
  });

  summarize(panel);
  return { preview, close };
}
