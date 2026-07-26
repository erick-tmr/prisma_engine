export const PAGE_SIZE = 30;

export function pageCount(total) {
  return Math.max(1, Math.ceil(total / PAGE_SIZE));
}

export function clampPage(page, total) {
  return Math.min(Math.max(1, page), pageCount(total));
}

export function pageSlice(rows, page) {
  const start = (clampPage(page, rows.length) - 1) * PAGE_SIZE;
  return rows.slice(start, start + PAGE_SIZE);
}

export function pageWindow(current, last) {
  if (last <= 7) return Array.from({ length: last }, (_, i) => i + 1);

  const wanted = new Set([1, last, current, current - 1, current + 1]);
  if (current <= 3) [2, 3, 4].forEach((n) => wanted.add(n));
  if (current >= last - 2) [last - 3, last - 2, last - 1].forEach((n) => wanted.add(n));

  const pages = [...wanted].filter((n) => n >= 1 && n <= last).sort((a, b) => a - b);
  const out = [];
  pages.forEach((n, i) => {
    if (i && n - pages[i - 1] > 1) out.push("gap");
    out.push(n);
  });
  return out;
}

export function rangeHtml(page, total, noun) {
  const label = total === 1 ? noun[0] : noun[1];
  if (total <= PAGE_SIZE) return `<b>${total}</b> ${label}`;

  const from = (page - 1) * PAGE_SIZE + 1;
  const to = Math.min(total, page * PAGE_SIZE);
  return `<b>${from}–${to}</b> de <b>${total}</b> ${label}`;
}

export function pagesHtml(page, last) {
  const numbers = pageWindow(page, last).map((n) =>
    n === "gap"
      ? `<span class="pg-gap" aria-hidden="true">…</span>`
      : `<button type="button" class="pg${n === page ? " on" : ""}" data-pg="${n}"${n === page ? ' aria-current="page"' : ""}>${n}</button>`
  ).join("");

  return `<nav class="pages" aria-label="Paginação">
      <button type="button" class="pg pg-nav" data-pg="${page - 1}"${page === 1 ? " disabled" : ""} aria-label="Página anterior"><i class="bi bi-chevron-left"></i></button>
      ${numbers}
      <button type="button" class="pg pg-nav" data-pg="${page + 1}"${page === last ? " disabled" : ""} aria-label="Próxima página"><i class="bi bi-chevron-right"></i></button>
    </nav>`;
}

export function scrollPanelTop(mount) {
  mount.closest(".panel").scrollIntoView({ block: "start" });
}

export function renderPager(mount, { page, total, noun, onGo }) {
  if (total === 0) {
    mount.hidden = true;
    mount.innerHTML = "";
    return;
  }

  const last = pageCount(total);
  const current = clampPage(page, total);
  mount.hidden = false;
  mount.innerHTML =
    `<div class="foot-range">Mostrando ${rangeHtml(current, total, noun)}</div>` +
    (last > 1 ? pagesHtml(current, last) : `<div class="foot-single">Página 1 de 1</div>`);

  mount.onclick = (event) => {
    const button = event.target.closest("button[data-pg]");
    if (!button || button.disabled) return;

    const target = Number(button.dataset.pg);
    if (target !== current) onGo(target);
  };
}
