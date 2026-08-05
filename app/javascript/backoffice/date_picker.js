export const MONTHS_SHORT = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];
export const MONTHS_LONG = ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho", "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"];
export const DOW = ["D", "S", "T", "Q", "Q", "S", "S"];

export const PRESETS = [
  { id: "today", label: "Hoje" },
  { id: "7", label: "Últimos 7 dias" },
  { id: "30", label: "Últimos 30 dias" },
  { id: "month", label: "Este mês" },
  { id: "prevmonth", label: "Mês passado" },
  { id: "ytd", label: "Este ano" }
];

const pad2 = (n) => String(n).padStart(2, "0");

export function parseISO(iso) {
  const [ y, m, d ] = iso.split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function toISO(date) {
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

export function fmtDate(value) {
  const dt = typeof value === "string" ? parseISO(value) : value;
  return `${pad2(dt.getDate())} ${MONTHS_SHORT[dt.getMonth()]} ${dt.getFullYear()}`;
}

export function sameDay(a, b) {
  return Boolean(a) && Boolean(b) &&
    a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

export function startOfMonth(d) {
  return new Date(d.getFullYear(), d.getMonth(), 1);
}

export function addMonths(d, n) {
  return new Date(d.getFullYear(), d.getMonth() + n, 1);
}

export function monthsBetween(from, to) {
  return (to.getFullYear() - from.getFullYear()) * 12 + (to.getMonth() - from.getMonth());
}

export function anchorMonth(sel, today) {
  const from = sel.from || today;
  const to = sel.to || from;
  if (monthsBetween(from, to) > 1) return addMonths(startOfMonth(to), -1);
  return startOfMonth(from);
}

export function applyPreset(preset, today) {
  const midnight = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const end = new Date(midnight);
  let start = new Date(midnight);

  if (preset === "7") start.setDate(start.getDate() - 6);
  else if (preset === "30") start.setDate(start.getDate() - 29);
  else if (preset === "month") start = new Date(midnight.getFullYear(), midnight.getMonth(), 1);
  else if (preset === "prevmonth") {
    start = new Date(midnight.getFullYear(), midnight.getMonth() - 1, 1);
    end.setTime(new Date(midnight.getFullYear(), midnight.getMonth(), 0).getTime());
  } else if (preset === "ytd") start = new Date(midnight.getFullYear(), 0, 1);

  return { from: start, to: end };
}

export function monthCells(monthDate, sel, today) {
  const y = monthDate.getFullYear();
  const m = monthDate.getMonth();
  const startDow = new Date(y, m, 1).getDay();
  const days = new Date(y, m + 1, 0).getDate();
  const cells = [];
  for (let i = 0; i < startDow; i += 1) cells.push({ blank: true });
  for (let d = 1; d <= days; d += 1) {
    const date = new Date(y, m, d);
    const { from, to } = sel;
    cells.push({
      day: d,
      iso: `${y}-${pad2(m + 1)}-${pad2(d)}`,
      today: sameDay(date, today),
      inRange: Boolean(from && to && date > from && date < to),
      start: Boolean(from && sameDay(date, from)),
      end: Boolean((to && sameDay(date, to)) || (from && !to && sameDay(date, from)))
    });
  }
  return cells;
}

export function calendarHtml(monthDate, side, sel, today) {
  const cells = monthCells(monthDate, sel, today).map((cell) => {
    if (cell.blank) return `<div class="dp-day muted"></div>`;
    const cls = [ "dp-day" ];
    if (cell.today) cls.push("today");
    if (cell.inRange) cls.push("in-range");
    if (cell.start) cls.push("range-start");
    if (cell.end) cls.push("range-end");
    return `<button type="button" class="${cls.join(" ")}" data-d="${cell.iso}">${cell.day}</button>`;
  }).join("");
  const prev = `<button type="button" class="dp-nav ${side === "R" ? "dp-nav--hidden" : ""}" ${side === "L" ? 'data-nav="prev"' : ""}><i class="bi bi-chevron-left"></i></button>`;
  const next = `<button type="button" class="dp-nav ${side === "L" ? "dp-nav--hidden" : ""}" ${side === "R" ? 'data-nav="next"' : ""}><i class="bi bi-chevron-right"></i></button>`;
  const head = `<div class="dp-cal-head">${prev}<span class="mname">${MONTHS_LONG[monthDate.getMonth()]} ${monthDate.getFullYear()}</span>${next}</div>`;
  const dow = DOW.map((x) => `<div class="dp-dow">${x}</div>`).join("");
  return `<div class="dp-cal">${head}<div class="dp-grid">${dow}${cells}</div></div>`;
}

export function dpReadoutHtml(sel) {
  const { from, to } = sel;
  if (!from && !to) return `<span class="ph">Selecione o período</span>`;
  const start = from ? fmtDate(from) : `<span class="ph">início</span>`;
  const end = to ? fmtDate(to) : `<span class="ph">fim</span>`;
  return `${start} &nbsp;→&nbsp; ${end}`;
}

export function datePopHtml(left, sel, today, activePreset) {
  const presets = PRESETS.map((p) =>
    `<button type="button" class="dp-preset ${p.id === activePreset ? "on" : ""}" data-p="${p.id}">${p.label}</button>`
  ).join("");
  return `<div class="dp-body">
      <div class="dp-presets">${presets}</div>
      <div class="dp-cals">${calendarHtml(left, "L", sel, today)}${calendarHtml(addMonths(left, 1), "R", sel, today)}</div>
    </div>
    <div class="dp-foot">
      <span class="dp-readout">${dpReadoutHtml(sel)}</span>
      <span class="sp"></span>
      <button type="button" class="btn-clear" id="dp-clear"><i class="bi bi-x-lg"></i> Limpar</button>
      <button type="button" class="btn-dark" id="dp-apply">Aplicar período</button>
    </div>`;
}

export function nextSelection(current, date) {
  const { from, to } = current;
  if (!from || (from && to)) return { from: date, to: null };
  if (date < from) return { from: date, to: from };
  return { from, to: date };
}
