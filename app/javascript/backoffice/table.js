export const DEBOUNCE_MS = 250;

export function buildUrl(path, params) {
  const search = new URLSearchParams();
  Object.entries(params).forEach(([ key, value ]) => {
    if (Array.isArray(value)) value.forEach((entry) => search.append(`${key}[]`, entry));
    else if (value !== null && value !== undefined && value !== "") search.set(key, value);
  });
  const query = search.toString();
  return query ? `${path}?${query}` : path;
}

export function readParams(search) {
  const params = new URLSearchParams(search);
  const out = {};
  params.forEach((value, key) => {
    if (key.endsWith("[]")) {
      const name = key.slice(0, -2);
      (out[name] ||= []).push(value);
    } else {
      out[key] = value;
    }
  });
  return out;
}

export function swapParts(root, html) {
  const parsed = new DOMParser().parseFromString(html, "text/html");
  parsed.querySelectorAll("[data-part]").forEach((incoming) => {
    const target = root.querySelector(`[data-part="${incoming.dataset.part}"]`);
    if (target) target.replaceWith(incoming);
  });
}

export function debounce(fn, wait = DEBOUNCE_MS) {
  let timer = null;
  const wrapped = (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), wait);
  };
  wrapped.cancel = () => clearTimeout(timer);
  return wrapped;
}

export function createTable(root, { path, onRender, onRestore } = {}) {
  const basePath = path || window.location.pathname;
  let params = readParams(window.location.search);
  let pending = 0;

  async function load(next, { push = true } = {}) {
    params = next;
    const url = buildUrl(basePath, params);
    const ticket = ++pending;
    root.classList.add("is-loading");

    try {
      const response = await fetch(url, { headers: { "X-Requested-With": "fetch" } });
      const html = await response.text();
      if (ticket !== pending) return;

      swapParts(root, html);
      if (push) window.history.pushState({}, "", url);
      else if (onRestore) onRestore(params);
      if (onRender) onRender();
    } finally {
      if (ticket === pending) root.classList.remove("is-loading");
    }
  }

  function set(changes, options) {
    const next = { ...params, ...changes };
    Object.keys(changes).forEach((key) => {
      const value = changes[key];
      if (value === null || value === undefined || value === "" || (Array.isArray(value) && !value.length)) delete next[key];
    });
    if (!("page" in changes)) delete next.page;
    return load(next, options);
  }

  // Page and sort links are real hrefs, so they keep working without JS.
  root.addEventListener("click", (event) => {
    const link = event.target.closest("[data-part] a[href]");
    if (!link || link.dataset.noIntercept !== undefined) return;
    const target = new URL(link.href, window.location.origin);
    if (target.pathname !== basePath) return;

    event.preventDefault();
    load(readParams(target.search));
  });

  const onPopState = () => load(readParams(window.location.search), { push: false });
  window.addEventListener("popstate", onPopState);

  return {
    get params() { return { ...params }; },
    set,
    reload: (options) => load(params, options),
    destroy() { window.removeEventListener("popstate", onPopState); }
  };
}
