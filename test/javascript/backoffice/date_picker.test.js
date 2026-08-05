import { describe, expect, it } from "vitest";
import {
  MONTHS_LONG, PRESETS, addMonths, anchorMonth, applyPreset, calendarHtml, datePopHtml,
  dpReadoutHtml, fmtDate, monthCells, monthsBetween, nextSelection, parseISO, sameDay,
  startOfMonth, toISO
} from "../../../app/javascript/backoffice/date_picker.js";

const TODAY = new Date(2026, 5, 15, 14, 37, 12);
const iso = (d) => toISO(d);

describe("date helpers", () => {
  it("round-trips an ISO day through local midnight", () => {
    const parsed = parseISO("2026-06-14");
    expect(parsed.getMonth()).toBe(5);
    expect(parsed.getHours()).toBe(0);
    expect(toISO(parsed)).toBe("2026-06-14");
  });

  it("formats a day the way the list does", () => {
    expect(fmtDate("2026-06-14")).toBe("14 jun 2026");
    expect(fmtDate(new Date(2026, 0, 5))).toBe("05 jan 2026");
  });

  it("compares calendar days, ignoring time and nulls", () => {
    expect(sameDay(new Date(2026, 5, 1, 9), new Date(2026, 5, 1, 23))).toBe(true);
    expect(sameDay(new Date(2026, 5, 1), new Date(2026, 5, 2))).toBe(false);
    expect(sameDay(null, new Date())).toBe(false);
    expect(sameDay(new Date(), null)).toBe(false);
  });

  it("walks months from the first of the month", () => {
    expect(iso(startOfMonth(TODAY))).toBe("2026-06-01");
    expect(iso(addMonths(startOfMonth(TODAY), -1))).toBe("2026-05-01");
    expect(iso(addMonths(startOfMonth(TODAY), 1))).toBe("2026-07-01");
  });
});

describe("anchorMonth", () => {
  it("opens on the current month when nothing is selected", () => {
    expect(iso(anchorMonth({ from: null, to: null }, TODAY))).toBe("2026-06-01");
  });

  it("starts at the month the range starts in", () => {
    const week = applyPreset("7", TODAY);
    expect(iso(anchorMonth(week, TODAY))).toBe("2026-06-01");
    expect(iso(anchorMonth(applyPreset("prevmonth", TODAY), TODAY))).toBe("2026-05-01");
  });

  it("keeps a half-picked range on screen", () => {
    expect(iso(anchorMonth({ from: parseISO("2026-04-20"), to: null }, TODAY))).toBe("2026-04-01");
  });

  it("shows the end of a range too long for two calendars", () => {
    expect(iso(anchorMonth(applyPreset("ytd", TODAY), TODAY))).toBe("2026-05-01");
  });

  it("counts the months a range crosses", () => {
    expect(monthsBetween(parseISO("2026-06-09"), parseISO("2026-06-15"))).toBe(0);
    expect(monthsBetween(parseISO("2026-05-17"), parseISO("2026-06-15"))).toBe(1);
    expect(monthsBetween(parseISO("2025-12-31"), parseISO("2026-06-15"))).toBe(6);
  });
});

describe("applyPreset", () => {
  it("covers whole days, so today is a real one-day range", () => {
    const { from, to } = applyPreset("today", TODAY);
    expect(iso(from)).toBe("2026-06-15");
    expect(iso(to)).toBe("2026-06-15");
    expect(from.getHours()).toBe(0);
    expect(to.getHours()).toBe(0);
  });

  it("spans the number of days it advertises", () => {
    expect(iso(applyPreset("7", TODAY).from)).toBe("2026-06-09");
    expect(iso(applyPreset("30", TODAY).from)).toBe("2026-05-17");
  });

  it("handles the calendar-anchored presets", () => {
    expect(iso(applyPreset("month", TODAY).from)).toBe("2026-06-01");
    expect(iso(applyPreset("ytd", TODAY).from)).toBe("2026-01-01");

    const prev = applyPreset("prevmonth", TODAY);
    expect(iso(prev.from)).toBe("2026-05-01");
    expect(iso(prev.to)).toBe("2026-05-31");
  });

  it("falls back to today for an id it does not know", () => {
    const { from, to } = applyPreset("nonsense", TODAY);
    expect(iso(from)).toBe("2026-06-15");
    expect(iso(to)).toBe("2026-06-15");
  });

  it("offers the six presets the design lists", () => {
    expect(PRESETS.map((p) => p.id)).toEqual([ "today", "7", "30", "month", "prevmonth", "ytd" ]);
  });
});

describe("monthCells", () => {
  it("pads the leading blanks and marks today", () => {
    const cells = monthCells(new Date(2026, 5, 1), { from: null, to: null }, TODAY);
    expect(cells.filter((c) => c.blank)).toHaveLength(1);
    expect(cells.filter((c) => c.day)).toHaveLength(30);
    expect(cells.find((c) => c.day === 15).today).toBe(true);
  });

  it("marks the ends of a range and everything between", () => {
    const sel = { from: new Date(2026, 5, 10), to: new Date(2026, 5, 12) };
    const cells = monthCells(new Date(2026, 5, 1), sel, TODAY);

    expect(cells.find((c) => c.day === 10).start).toBe(true);
    expect(cells.find((c) => c.day === 11).inRange).toBe(true);
    expect(cells.find((c) => c.day === 12).end).toBe(true);
  });

  it("treats a half-picked range as a single marked day", () => {
    const cells = monthCells(new Date(2026, 5, 1), { from: new Date(2026, 5, 10), to: null }, TODAY);
    expect(cells.find((c) => c.day === 10).end).toBe(true);
  });
});

describe("nextSelection", () => {
  it("starts a range, extends it, then starts over", () => {
    const first = nextSelection({ from: null, to: null }, new Date(2026, 5, 10));
    expect(iso(first.from)).toBe("2026-06-10");
    expect(first.to).toBeNull();

    const extended = nextSelection(first, new Date(2026, 5, 12));
    expect(iso(extended.to)).toBe("2026-06-12");

    const restarted = nextSelection(extended, new Date(2026, 5, 20));
    expect(iso(restarted.from)).toBe("2026-06-20");
    expect(restarted.to).toBeNull();
  });

  it("swaps the ends when the second click is earlier", () => {
    const started = { from: new Date(2026, 5, 12), to: null };
    const swapped = nextSelection(started, new Date(2026, 5, 10));

    expect(iso(swapped.from)).toBe("2026-06-10");
    expect(iso(swapped.to)).toBe("2026-06-12");
  });
});

describe("markup", () => {
  it("hides the wrong-side nav on each calendar", () => {
    const sel = { from: null, to: null };
    const left = calendarHtml(new Date(2026, 5, 1), "L", sel, TODAY);
    const right = calendarHtml(new Date(2026, 6, 1), "R", sel, TODAY);

    expect(left).toContain('data-nav="prev"');
    expect(right).toContain('data-nav="next"');
    expect(right).toContain("dp-nav--hidden");
    expect(right).toContain(`${MONTHS_LONG[6]} 2026`);
  });

  it("reads out an empty, half and full range", () => {
    expect(dpReadoutHtml({ from: null, to: null })).toContain("Selecione o período");
    expect(dpReadoutHtml({ from: new Date(2026, 5, 10), to: null })).toContain("fim");
    expect(dpReadoutHtml({ from: null, to: new Date(2026, 5, 20) })).toContain("início");
    expect(dpReadoutHtml({ from: new Date(2026, 5, 10), to: new Date(2026, 5, 20) })).toContain("→");
  });

  it("highlights the active preset in the popover", () => {
    const html = datePopHtml(new Date(2026, 4, 1), { from: null, to: null }, TODAY, "30");
    expect(html).toContain('class="dp-preset on" data-p="30"');
    expect(html).toContain('class="dp-preset " data-p="7"');
    expect(html).toContain("dp-apply");
  });
});
