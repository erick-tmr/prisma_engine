import { afterEach, describe, expect, it, vi } from "vitest";
import {
  DEFAULT_TIME, formatBR, initSchedulePicker, initStoreTheme, joinValue, readoutText, splitValue
} from "../../../app/javascript/backoffice/store_theme.js";

const TODAY = new Date(2026, 10, 26);
const LABELS = { empty: "Selecione o período", openEnd: "sem fim" };

const formHtml = (start = "", end = "") => `
  <form data-schedule data-schedule-empty="${LABELS.empty}" data-schedule-open-end="${LABELS.openEnd}">
    <input type="hidden" name="store_setting[black_friday_starts_at]" value="${start}" data-schedule-value="start">
    <input type="hidden" name="store_setting[black_friday_ends_at]" value="${end}" data-schedule-value="end">
    <div data-schedule-cals></div>
    <input type="text" data-schedule-time="start">
    <input type="text" data-schedule-time="end">
    <span data-schedule-readout></span>
    <button type="button" data-schedule-clear>Limpar</button>
  </form>`;

const mount = (start, end) => {
  document.body.innerHTML = formHtml(start, end);
  const form = document.querySelector("form");
  return { form, state: initSchedulePicker(form, TODAY) };
};

const $ = (selector) => document.querySelector(selector);
const value = (key) => $(`[data-schedule-value="${key}"]`).value;
const readout = () => $("[data-schedule-readout]").textContent;
const clickDay = (iso) => $(`.dp-day[data-d="${iso}"]`).click();
const type = (key, text) => {
  const input = $(`[data-schedule-time="${key}"]`);
  input.value = text;
  input.dispatchEvent(new window.Event("input"));
};

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
});

describe("value helpers", () => {
  it("splits a stored value into a local date and a 24h time", () => {
    const { date, time } = splitValue("2026-11-27T00:00");
    expect([ date.getFullYear(), date.getMonth(), date.getDate() ]).toEqual([ 2026, 10, 27 ]);
    expect(time).toBe("00:00");
    expect(splitValue("")).toEqual({ date: null, time: DEFAULT_TIME });
  });

  it("joins a date and time back into the submitted value", () => {
    expect(joinValue(new Date(2026, 11, 1), "19:30")).toBe("2026-12-01T19:30");
    expect(joinValue(null, "00:00")).toBe("");
  });

  it("formats dates day first, the Brazilian way", () => {
    expect(formatBR(new Date(2026, 10, 7), "08:05")).toBe("07/11/2026 08:05");
  });

  it("describes the window in the readout", () => {
    const times = { start: "00:00", end: "00:00" };
    expect(readoutText({ from: null, to: null }, times, LABELS)).toBe("Selecione o período");
    expect(readoutText({ from: new Date(2026, 10, 27), to: null }, times, LABELS)).toBe("27/11/2026 00:00 → sem fim");
    expect(readoutText({ from: new Date(2026, 10, 27), to: new Date(2026, 11, 1) }, times, LABELS))
      .toBe("27/11/2026 00:00 → 01/12/2026 00:00");
  });
});

describe("initSchedulePicker", () => {
  it("returns null without a form", () => {
    expect(initSchedulePicker(null)).toBeNull();
  });

  it("starts from the saved window", () => {
    mount("2026-11-27T00:00", "2026-12-01T00:00");

    expect(readout()).toBe("27/11/2026 00:00 → 01/12/2026 00:00");
    expect($('[data-schedule-time="start"]').value).toBe("00:00");
    expect($('[data-schedule-time="end"]').disabled).toBe(false);
    expect($(".dp-day.range-start").dataset.d).toBe("2026-11-27");
    expect($(".dp-day.range-end").dataset.d).toBe("2026-12-01");
  });

  it("picks a start day, then an end day, and writes both hidden values", () => {
    mount();
    expect(readout()).toBe("Selecione o período");
    expect($('[data-schedule-time="end"]').disabled).toBe(true);

    clickDay("2026-11-27");
    expect(value("start")).toBe("2026-11-27T00:00");
    expect(value("end")).toBe("");
    expect(readout()).toBe("27/11/2026 00:00 → sem fim");

    clickDay("2026-12-01");
    expect(value("end")).toBe("2026-12-01T00:00");
    expect($('[data-schedule-time="end"]').disabled).toBe(false);
  });

  it("applies valid 24h times and ignores half-typed ones", () => {
    mount("2026-11-27T00:00", "2026-12-01T00:00");

    type("start", "19:3");
    expect(value("start")).toBe("2026-11-27T00:00");

    type("start", "19:30");
    type("end", "23:59");
    expect(value("start")).toBe("2026-11-27T19:30");
    expect(value("end")).toBe("2026-12-01T23:59");
    expect(readout()).toBe("27/11/2026 19:30 → 01/12/2026 23:59");
  });

  it("moves between months with the arrows", () => {
    mount();
    expect($(".mname").textContent).toBe("Novembro 2026");

    $('.dp-nav[data-nav="next"]').click();
    expect($(".mname").textContent).toBe("Dezembro 2026");

    $('.dp-nav[data-nav="prev"]').click();
    expect($(".mname").textContent).toBe("Novembro 2026");
  });

  it("ignores clicks that land on neither a day nor an arrow", () => {
    mount();
    $(".dp-grid").click();
    expect(value("start")).toBe("");
  });

  it("clears the window", () => {
    mount("2026-11-27T00:00", "2026-12-01T00:00");

    $("[data-schedule-clear]").click();

    expect(value("start")).toBe("");
    expect(value("end")).toBe("");
    expect(readout()).toBe("Selecione o período");
  });
});

describe("initStoreTheme", () => {
  it("wires the shell, the turn-off confirmation and the picker", () => {
    document.body.innerHTML = `
      <div class="app" data-list="store-theme">
        <aside data-sidebar></aside>
        <button id="menu-toggle" type="button">menu</button>
        <div class="od-flash"><button type="button" data-flash-close>x</button></div>
        ${formHtml("2026-11-27T00:00", "")}
        <form data-confirm="Desligar?" id="off"><button type="submit">off</button></form>
      </div>`;
    const root = $("[data-list]");

    const state = initStoreTheme(root);
    expect(state.sel.from.getDate()).toBe(27);

    $("#menu-toggle").click();
    expect($("[data-sidebar]").classList.contains("show")).toBe(true);

    $("[data-flash-close]").click();
    expect($(".od-flash")).toBeNull();

    vi.spyOn(window, "confirm").mockReturnValue(false);
    const event = new window.Event("submit", { cancelable: true });
    $("#off").dispatchEvent(event);
    expect(event.defaultPrevented).toBe(true);
  });
});
