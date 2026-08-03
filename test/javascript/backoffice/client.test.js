import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { elapsedPercent, initClient, paintClock, remaining, startClock }
  from "../../../app/javascript/backoffice/client.js";

const SECOND = 1000;
const MINUTE = 60 * SECOND;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));

// Mirrors the data hooks in app/views/admin/clients/{show,_strikes,_order_row}.html.erb.
const clockMarkup = (startedAt, expiresAt) => `
  <div class="sk-clock" data-strike-clock data-started-at="${startedAt}" data-expires-at="${expiresAt}">
    <span class="u"><b data-clock-value="days">00</b></span>
    <span class="u"><b data-clock-value="hours">00</b></span>
    <span class="u"><b data-clock-value="minutes">00</b></span>
    <span class="u"><b data-clock-value="seconds">00</b></span>
  </div>
  <div class="sk-bar"><i data-strike-bar></i></div>`;

const shell = (inner = "") => `
  <div class="app" data-list="client">
    <aside data-sidebar></aside>
    <button id="menu-toggle" type="button"></button>
    ${inner}
    <span data-part="count">0</span>
    <div data-part="table">
      <table><tbody>
        <tr data-order="PG-00001">
          <td><a class="cell-link" href="/admin/pedidos/PG-00001">PG-00001</a></td>
          <td class="other">2 itens</td>
        </tr>
      </tbody></table>
    </div>
  </div>`;

const readClock = () =>
  [ "days", "hours", "minutes", "seconds" ].map((unit) => document.querySelector(`[data-clock-value="${unit}"]`).textContent);

let started;

beforeEach(() => {
  started = [];
  window.history.pushState({}, "", "/admin/clientes/7");
  vi.spyOn(window, "fetch").mockResolvedValue({ text: async () => "" });
});

afterEach(() => {
  started.forEach((client) => client.destroy());
  document.body.innerHTML = "";
  vi.restoreAllMocks();
  vi.useRealTimers();
  window.history.pushState({}, "", "/");
});

describe("remaining", () => {
  it("splits the gap into days, hours, minutes and seconds", () => {
    const now = Date.parse("2026-08-01T00:00:00Z");
    expect(remaining(now + 2 * DAY + 3 * HOUR + 4 * MINUTE + 5 * SECOND, now))
      .toEqual({ days: 2, hours: 3, minutes: 4, seconds: 5 });
  });

  it("floors at zero once the ban is over", () => {
    const now = Date.parse("2026-08-01T00:00:00Z");
    expect(remaining(now - DAY, now)).toEqual({ days: 0, hours: 0, minutes: 0, seconds: 0 });
  });
});

describe("elapsedPercent", () => {
  const started = Date.parse("2026-08-01T00:00:00Z");

  it("tracks how much of the penalty has been served", () => {
    expect(elapsedPercent(started, started + 10 * DAY, started + 5 * DAY)).toBe(50);
  });

  it("keeps a sliver visible at the very start and never overflows at the end", () => {
    expect(elapsedPercent(started, started + 10 * DAY, started)).toBe(2);
    expect(elapsedPercent(started, started + 10 * DAY, started + 40 * DAY)).toBe(100);
  });

  it("reads a zero-length penalty as fully served", () => {
    expect(elapsedPercent(started, started, started)).toBe(100);
  });
});

describe("paintClock", () => {
  it("writes zero-padded units and fills the bar", () => {
    const now = Date.parse("2026-08-01T00:00:00Z");
    document.body.innerHTML = clockMarkup(new Date(now - DAY).toISOString(), new Date(now + DAY).toISOString());

    const running = paintClock(document.querySelector("[data-strike-clock]"), document.querySelector("[data-strike-bar]"), now);

    expect(running).toBe(true);
    expect(readClock()).toEqual([ "01", "00", "00", "00" ]);
    expect(document.querySelector("[data-strike-bar]").style.width).toBe("50%");
  });

  it("reports the ban as over once the deadline passes", () => {
    const now = Date.parse("2026-08-01T00:00:00Z");
    document.body.innerHTML = clockMarkup(new Date(now - 2 * DAY).toISOString(), new Date(now - DAY).toISOString());

    expect(paintClock(document.querySelector("[data-strike-clock]"), null, now)).toBe(false);
    expect(readClock()).toEqual([ "00", "00", "00", "00" ]);
  });

  it("skips units the panel does not render", () => {
    document.body.innerHTML = `<div data-strike-clock data-started-at="2026-08-01T00:00:00Z" data-expires-at="2026-08-08T00:00:00Z"></div>`;

    expect(() => paintClock(document.querySelector("[data-strike-clock]"), null, Date.parse("2026-08-02T00:00:00Z")))
      .not.toThrow();
  });
});

describe("startClock", () => {
  it("ticks every second while the ban is running", () => {
    vi.useFakeTimers();
    const now = Date.now();
    document.body.innerHTML = clockMarkup(new Date(now - DAY).toISOString(), new Date(now + 3 * SECOND).toISOString());
    const stop = startClock(document.body);

    expect(readClock()).toEqual([ "00", "00", "00", "03" ]);
    vi.advanceTimersByTime(2 * SECOND);
    expect(readClock()).toEqual([ "00", "00", "00", "01" ]);

    stop();
  });

  it("stops itself the moment the ban expires", () => {
    vi.useFakeTimers();
    const now = Date.now();
    document.body.innerHTML = clockMarkup(new Date(now - DAY).toISOString(), new Date(now + SECOND).toISOString());
    startClock(document.body);

    vi.advanceTimersByTime(5 * SECOND);
    expect(readClock()).toEqual([ "00", "00", "00", "00" ]);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("does nothing on a client with no active ban", () => {
    document.body.innerHTML = `<div class="app"></div>`;
    expect(startClock(document.querySelector(".app"))).toBeNull();
  });
});

describe("initClient", () => {
  it("opens an order by forwarding the row click to its link", () => {
    document.body.innerHTML = shell();
    started.push(initClient(document.querySelector(".app")));

    const link = document.querySelector("a.cell-link");
    const spy = vi.spyOn(link, "click");
    click(document.querySelector("td.other"));

    expect(spy).toHaveBeenCalledOnce();
  });

  it("ignores clicks that land outside an order row", () => {
    document.body.innerHTML = shell();
    started.push(initClient(document.querySelector(".app")));

    expect(() => click(document.querySelector("[data-part=count]"))).not.toThrow();
  });

  it("pages the order history through the query string", async () => {
    document.body.innerHTML = shell();
    document.querySelector("[data-part=table]").insertAdjacentHTML(
      "beforeend", `<a class="pg" href="/admin/clientes/7?page=2">2</a>`
    );
    started.push(initClient(document.querySelector(".app")));

    click(document.querySelector("a.pg"));

    await vi.waitFor(() =>
      expect(window.fetch).toHaveBeenCalledWith("/admin/clientes/7?page=2", expect.anything()));
  });

  it("guards the strike removal behind a confirm", () => {
    document.body.innerHTML = shell(`<form data-confirm="Remover?" id="drop"><button type="submit"></button></form>`);
    started.push(initClient(document.querySelector(".app")));

    window.confirm = vi.fn(() => false);
    const event = new window.Event("submit", { cancelable: true, bubbles: true });
    document.getElementById("drop").dispatchEvent(event);

    expect(window.confirm).toHaveBeenCalledWith("Remover?");
    expect(event.defaultPrevented).toBe(true);
  });

  it("dismisses the flash and tears the clock down on destroy", () => {
    vi.useFakeTimers();
    const now = Date.now();
    document.body.innerHTML = shell(
      `<div class="od-flash"><button data-flash-close></button></div>` +
      clockMarkup(new Date(now - DAY).toISOString(), new Date(now + DAY).toISOString())
    );
    const client = initClient(document.querySelector(".app"));

    click(document.querySelector("[data-flash-close]"));
    expect(document.querySelector(".od-flash")).toBeNull();

    client.destroy();
    expect(vi.getTimerCount()).toBe(0);
  });
});
