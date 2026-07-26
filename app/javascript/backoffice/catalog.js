import { clampPage, pageSlice, renderPager, scrollPanelTop } from "backoffice/pager";

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

export function matchingRows(rows, filters) {
  return rows.filter((row) => rowMatches(row.dataset, filters));
}

export function showOnly(rows, pageRows) {
  const visible = new Set(pageRows);
  rows.forEach((row) => { row.hidden = !visible.has(row); });
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
  const foot = root.querySelector("#catalog-foot");
  let page = 1;

  const render = () => {
    const matching = matchingRows(rows, { q: query.value, cat: category.value, status: status.value });
    page = clampPage(page, matching.length);
    showOnly(rows, pageSlice(matching, page));
    if (countEl) countEl.textContent = plural(matching.length, "produto", "produtos");
    if (empty) empty.classList.toggle("show", matching.length === 0);
    renderPager(foot, {
      page, total: matching.length, noun: ["produto", "produtos"],
      onGo(target) { page = target; render(); scrollPanelTop(foot); }
    });
  };

  const reset = () => {
    page = 1;
    render();
  };

  [query, category, status].forEach((el) => el.addEventListener("input", reset));
  if (gsearch) {
    gsearch.addEventListener("input", (event) => {
      query.value = event.target.value;
      reset();
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
