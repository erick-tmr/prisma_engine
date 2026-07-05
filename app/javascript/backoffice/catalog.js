export function plural(count, one, many) {
  return `${count} ${count === 1 ? one : many}`;
}

export function rowMatches(data, filters) {
  const query = (filters.q || "").toLowerCase().trim();
  if (query && !data.name.includes(query) && !data.slug.includes(query)) return false;
  if (filters.cat && data.cat !== filters.cat) return false;
  if (filters.status && data.status !== filters.status) return false;
  return true;
}

export function applyFilters(rows, filters) {
  let visible = 0;
  rows.forEach((row) => {
    const shown = rowMatches(row.dataset, filters);
    row.hidden = !shown;
    if (shown) visible += 1;
  });
  return visible;
}

export function dismissToasts(root, delay = 3600) {
  root.querySelectorAll("[data-toast]").forEach((toast) => {
    setTimeout(() => toast.remove(), delay);
  });
}

export function initCatalog(root) {
  const body = root.querySelector("#catalog-body");
  if (!body) return null;

  const rows = Array.from(body.querySelectorAll("[data-row]"));
  const query = root.querySelector("#c-q");
  const category = root.querySelector("#c-cat");
  const status = root.querySelector("#c-status");
  const gsearch = root.querySelector("#gsearch");
  const countEl = root.querySelector("#catalog-count");
  const empty = root.querySelector("#catalog-empty");

  const render = () => {
    const visible = applyFilters(rows, { q: query.value, cat: category.value, status: status.value });
    if (countEl) countEl.textContent = plural(visible, "produto", "produtos");
    if (empty) empty.classList.toggle("show", visible === 0);
  };

  [query, category, status].forEach((el) => el.addEventListener("input", render));
  if (gsearch) {
    gsearch.addEventListener("input", (event) => {
      query.value = event.target.value;
      render();
    });
  }
  rows.forEach((row) => {
    row.addEventListener("click", () => navigate(row.dataset.href));
  });

  dismissToasts(root);
  render();
  return { render };
}

export function navigate(href) {
  window.location.assign(href);
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-catalog]");
  if (root) initCatalog(root);
}
/* v8 ignore stop */
