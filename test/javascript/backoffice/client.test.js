import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { bindContactEdit, elapsedPercent, initClient, maskPhone, paintClock, remaining, startClock }
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

// Mirrors app/views/admin/clients/_contact.html.erb.
const contactMarkup = ({ editing = false, email = "ana@example.com", phone = "(11) 98876-5521" } = {}) => `
  <div class="app">
    <section data-contact>
      <button type="button" data-contact-edit ${editing ? "hidden" : ""}></button>
      <div data-contact-view ${editing ? "hidden" : ""}></div>
      <form data-contact-form ${editing ? "" : "hidden"}>
        <input data-contact-input="email" data-original="ana@example.com" data-invalid-message="E-mail ruim" value="${email}">
        <div data-contact-error="email"></div>
        <input data-contact-input="phone" data-original="(11) 98876-5521" data-invalid-message="Telefone ruim" value="${phone}">
        <div data-contact-error="phone"></div>
        <button type="button" data-contact-cancel></button>
        <button type="submit" data-contact-save></button>
      </form>
    </section>
  </div>`;

const type = (input, value) => {
  input.value = value;
  input.dispatchEvent(new window.Event("input", { bubbles: true }));
};
const submit = (form) => {
  const event = new window.Event("submit", { cancelable: true, bubbles: true });
  form.dispatchEvent(event);
  return event;
};
const contact = () => ({
  edit: document.querySelector("[data-contact-edit]"),
  view: document.querySelector("[data-contact-view]"),
  form: document.querySelector("[data-contact-form]"),
  email: document.querySelector("[data-contact-input=email]"),
  phone: document.querySelector("[data-contact-input=phone]"),
  save: document.querySelector("[data-contact-save]"),
  error: (field) => document.querySelector(`[data-contact-error=${field}]`).textContent
});

describe("maskPhone", () => {
  it("formats a mobile and a landline", () => {
    expect(maskPhone("11988765521")).toBe("(11) 98876-5521");
    expect(maskPhone("1133334444")).toBe("(11) 3333-4444");
  });

  it("builds the mask up as digits arrive", () => {
    expect(maskPhone("")).toBe("");
    expect(maskPhone("1")).toBe("(1");
    expect(maskPhone("11")).toBe("(11");
    expect(maskPhone("119")).toBe("(11) 9");
    expect(maskPhone("119887")).toBe("(11) 9887");
    expect(maskPhone("1198876")).toBe("(11) 9887-6");
  });

  it("drops anything that is not a digit and caps at eleven", () => {
    expect(maskPhone("(11) 98876-5521 999")).toBe("(11) 98876-5521");
  });
});

describe("bindContactEdit", () => {
  it("does nothing on a page without the contact card", () => {
    document.body.innerHTML = `<div class="app"></div>`;
    expect(() => bindContactEdit(document.querySelector(".app"))).not.toThrow();
  });

  it("opens the form in place of the card, with save held until something changes", () => {
    document.body.innerHTML = contactMarkup();
    bindContactEdit(document.querySelector(".app"));
    const c = contact();

    click(c.edit);

    expect(c.form.hidden).toBe(false);
    expect(c.view.hidden).toBe(true);
    expect(c.edit.hidden).toBe(true);
    expect(document.activeElement).toBe(c.email);
    expect(c.save.disabled).toBe(true);
  });

  it("ignores case and padding in the e-mail and formatting in the phone when deciding what changed", () => {
    document.body.innerHTML = contactMarkup();
    bindContactEdit(document.querySelector(".app"));
    const c = contact();

    type(c.email, " ANA@example.com ");
    expect(c.save.disabled).toBe(true);

    type(c.email, "ana.nova@example.com");
    expect(c.save.disabled).toBe(false);
  });

  it("masks the phone as it is typed", () => {
    document.body.innerHTML = contactMarkup();
    bindContactEdit(document.querySelector(".app"));
    const c = contact();

    type(c.phone, "11977776666");

    expect(c.phone.value).toBe("(11) 97777-6666");
    expect(c.save.disabled).toBe(false);
  });

  it("blocks a submit with a malformed e-mail or a short phone and focuses the first one", () => {
    document.body.innerHTML = contactMarkup({ editing: true, email: "ana@", phone: "(11) 9887" });
    bindContactEdit(document.querySelector(".app"));
    const c = contact();

    const event = submit(c.form);

    expect(event.defaultPrevented).toBe(true);
    expect(c.error("email")).toBe("E-mail ruim");
    expect(c.error("phone")).toBe("Telefone ruim");
    expect(c.email.classList.contains("bad")).toBe(true);
    expect(document.activeElement).toBe(c.email);
  });

  it("clears a field's error as soon as it is edited", () => {
    document.body.innerHTML = contactMarkup({ editing: true, email: "ana@" });
    bindContactEdit(document.querySelector(".app"));
    const c = contact();
    submit(c.form);

    type(c.email, "ana@example.com.br");

    expect(c.error("email")).toBe("");
    expect(c.email.classList.contains("bad")).toBe(false);
  });

  it("lets a valid contact through to the server", () => {
    document.body.innerHTML = contactMarkup({ editing: true, email: "ana.nova@example.com" });
    bindContactEdit(document.querySelector(".app"));

    expect(submit(contact().form).defaultPrevented).toBe(false);
  });

  it("enables save on a form the server reopened with the rejected values", () => {
    document.body.innerHTML = contactMarkup({ editing: true, email: "outra@example.com" });
    bindContactEdit(document.querySelector(".app"));

    expect(contact().save.disabled).toBe(false);
  });

  it("cancels back to the card with the stored values, by button or Escape", () => {
    document.body.innerHTML = contactMarkup();
    bindContactEdit(document.querySelector(".app"));
    const c = contact();

    click(c.edit);
    type(c.email, "ana@");
    submit(c.form);
    click(document.querySelector("[data-contact-cancel]"));

    expect(c.form.hidden).toBe(true);
    expect(c.view.hidden).toBe(false);
    expect(c.email.value).toBe("ana@example.com");
    expect(c.error("email")).toBe("");
    expect(document.activeElement).toBe(c.edit);

    click(c.edit);
    type(c.phone, "1");
    c.form.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
    expect(c.form.hidden).toBe(false);
    c.form.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape", bubbles: true }));

    expect(c.form.hidden).toBe(true);
    expect(c.phone.value).toBe("(11) 98876-5521");
  });
});
