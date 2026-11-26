import { addMonths, anchorMonth, calendarHtml, nextSelection, parseISO, toISO } from "backoffice/date_picker";
import { bindConfirm, bindFlashDismiss, initShell } from "backoffice/shell";

export const TIME_PATTERN = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;
export const DEFAULT_TIME = "00:00";

const pad2 = (n) => String(n).padStart(2, "0");

export function splitValue(value) {
  if (!value) return { date: null, time: DEFAULT_TIME };

  const [ iso, time ] = value.split("T");
  return { date: parseISO(iso), time: time.slice(0, 5) };
}

export function joinValue(date, time) {
  return date ? `${toISO(date)}T${time}` : "";
}

export function formatBR(date, time) {
  return `${pad2(date.getDate())}/${pad2(date.getMonth() + 1)}/${date.getFullYear()} ${time}`;
}

export function readoutText(sel, times, labels) {
  if (!sel.from) return labels.empty;

  const end = sel.to ? formatBR(sel.to, times.end) : labels.openEnd;
  return `${formatBR(sel.from, times.start)} → ${end}`;
}

export function initSchedulePicker(form, today = new Date()) {
  if (!form) return null;

  const field = (key) => form.querySelector(`[data-schedule-value="${key}"]`);
  const timeInput = (key) => form.querySelector(`[data-schedule-time="${key}"]`);
  const cals = form.querySelector("[data-schedule-cals]");
  const readout = form.querySelector("[data-schedule-readout]");
  const labels = { empty: form.dataset.scheduleEmpty, openEnd: form.dataset.scheduleOpenEnd };

  const start = splitValue(field("start").value);
  const end = splitValue(field("end").value);
  const state = {
    sel: { from: start.date, to: end.date },
    times: { start: start.time, end: end.time }
  };
  state.left = anchorMonth(state.sel, today);

  function sync() {
    field("start").value = joinValue(state.sel.from, state.times.start);
    field("end").value = joinValue(state.sel.to, state.times.end);
    timeInput("end").disabled = !state.sel.to;
    readout.textContent = readoutText(state.sel, state.times, labels);
  }

  function render() {
    cals.innerHTML = calendarHtml(state.left, "L", state.sel, today) +
      calendarHtml(addMonths(state.left, 1), "R", state.sel, today);
    sync();
  }

  cals.addEventListener("click", (event) => {
    const nav = event.target.closest(".dp-nav[data-nav]");
    if (nav) {
      state.left = addMonths(state.left, nav.dataset.nav === "prev" ? -1 : 1);
      render();
      return;
    }
    const day = event.target.closest(".dp-day[data-d]");
    if (day) {
      state.sel = nextSelection(state.sel, parseISO(day.dataset.d));
      render();
    }
  });

  [ "start", "end" ].forEach((key) => {
    const input = timeInput(key);
    input.value = state.times[key];
    input.addEventListener("input", () => {
      if (!TIME_PATTERN.test(input.value)) return;

      state.times[key] = input.value;
      sync();
    });
  });

  form.querySelector("[data-schedule-clear]").addEventListener("click", () => {
    state.sel = { from: null, to: null };
    render();
  });

  render();
  return state;
}

export function initStoreTheme(root) {
  initShell(root);
  bindConfirm(root);
  bindFlashDismiss(root);
  return initSchedulePicker(root.querySelector("form[data-schedule]"));
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector('[data-list="store-theme"]');
  if (root) initStoreTheme(root);
}
/* v8 ignore stop */
