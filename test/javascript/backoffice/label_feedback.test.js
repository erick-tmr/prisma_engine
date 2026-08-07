import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  POLL_MAX_MS, POLL_STEPS, applyBusyRows, applyProgress, applyRowStatus, cellStates, createLabelFeedback,
  inFlight, nextDelay
} from "../../../app/javascript/backoffice/label_feedback.js";

const cell = (number, state, status = "in_production") => `
  <tr data-order="${number}" data-status="${status}">
    <td class="checkcol"><span class="rowcheck" data-check="${number}"></span></td>
    <td><div data-part="status-${number}" data-row-status="${status}"></div></td>
    <td class="corcell"><div data-part="correios-${number}" data-cor-state="${state}"></div></td>
  </tr>`;

const procbar = ({ inFlight: busy = 0, percent = 0 } = {}) =>
  `<div class="procbar" data-part="procbar" data-in-flight="${busy}" data-percent="${percent}">
     <div class="pb-fill"></div>
   </div>`;

const markup = (rows = "", bar = procbar()) => `
  <div class="app">
    ${bar}
    <table><tbody>${rows}</tbody></table>
  </div>`;

let root;
let poller;

const mount = (rows, bar) => {
  document.body.innerHTML = markup(rows, bar);
  root = document.querySelector(".app");
  return root;
};

const setVisibility = (value) => {
  Object.defineProperty(document, "visibilityState", { value, configurable: true });
  document.dispatchEvent(new window.Event("visibilitychange"));
};

const respondWith = (html) => vi.spyOn(window, "fetch").mockResolvedValue({ ok: true, text: async () => html });

beforeEach(() => {
  mount();
});

afterEach(() => {
  poller?.destroy();
  poller = null;
  setVisibility("visible");
  document.body.innerHTML = "";
  vi.restoreAllMocks();
  vi.useRealTimers();
});

describe("nextDelay", () => {
  it("walks the schedule and then holds at the slowest step", () => {
    expect(POLL_STEPS.map((_, i) => nextDelay(i))).toEqual(POLL_STEPS);
    expect(nextDelay(POLL_STEPS.length)).toBe(POLL_STEPS.at(-1));
    expect(nextDelay(999)).toBe(POLL_STEPS.at(-1));
  });
});

describe("cellStates", () => {
  it("reads every rendered cell state, and nothing when the table is empty", () => {
    expect(cellStates(root)).toEqual([]);

    mount(cell("PG-1", "running") + cell("PG-2", "done"));
    expect(cellStates(root)).toEqual([ "running", "done" ]);
  });
});

describe("inFlight", () => {
  it("is true while any cell is queued or running", () => {
    mount(cell("PG-1", "queued"));
    expect(inFlight(root)).toBe(true);

    mount(cell("PG-1", "running"));
    expect(inFlight(root)).toBe(true);
  });

  it("falls back to the batch strip when no row on screen is busy", () => {
    mount(cell("PG-1", "done"), procbar({ inFlight: 2 }));
    expect(inFlight(root)).toBe(true);
  });

  it("is false when nothing is busy anywhere", () => {
    mount(cell("PG-1", "done") + cell("PG-2", "failed"));
    expect(inFlight(root)).toBe(false);
  });

  it("is false when the page has no batch strip at all", () => {
    document.body.innerHTML = `<div class="app"><table><tbody></tbody></table></div>`;
    expect(inFlight(document.querySelector(".app"))).toBe(false);
  });
});

describe("applyBusyRows", () => {
  it("marks busy rows and releases them once the label settles", () => {
    mount(cell("PG-1", "running") + cell("PG-2", "done"));
    applyBusyRows(root);

    const [ busy, idle ] = Array.from(root.querySelectorAll("tr"));
    expect(busy.classList.contains("is-busy")).toBe(true);
    expect(busy.querySelector("[data-check]").getAttribute("aria-disabled")).toBe("true");
    expect(idle.classList.contains("is-busy")).toBe(false);
    expect(idle.querySelector("[data-check]").getAttribute("aria-disabled")).toBe("false");
  });

  it("leaves a row with no checkbox alone", () => {
    mount(`<tr data-order="PG-9"><td class="corcell"><div data-cor-state="queued"></div></td></tr>`);
    applyBusyRows(root);

    expect(root.querySelector("tr").classList.contains("is-busy")).toBe(true);
  });

  it("ignores a cell that is not inside a row", () => {
    document.body.innerHTML = `<div class="app"><div data-cor-state="running"></div></div>`;
    expect(() => applyBusyRows(document.querySelector(".app"))).not.toThrow();
  });
});

describe("applyProgress", () => {
  it("paints the strip width from the server-rendered percentage", () => {
    mount("", procbar({ percent: 40 }));
    applyProgress(root);

    expect(root.querySelector(".pb-fill").style.width).toBe("40%");
  });

  it("treats a missing percentage as zero and skips a page with no strip", () => {
    mount("", `<div class="procbar" data-part="procbar"><div class="pb-fill"></div></div>`);
    applyProgress(root);
    expect(root.querySelector(".pb-fill").style.width).toBe("0%");

    document.body.innerHTML = `<div class="app"></div>`;
    expect(() => applyProgress(document.querySelector(".app"))).not.toThrow();
  });
});

describe("createLabelFeedback", () => {
  const build = (options = {}) => {
    poller = createLabelFeedback(root, { path: "/admin/pedidos/correios", ...options });
    return poller;
  };

  it("polls the fragment endpoint and swaps only the parts it was given", async () => {
    vi.useFakeTimers();
    mount(cell("PG-1", "queued"));
    respondWith(`<div data-part="correios-PG-1" data-cor-state="done"></div>`);

    build({ params: () => ({ lote: [ "PG-1" ] }) }).start();
    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);

    expect(window.fetch).toHaveBeenCalledWith(
      "/admin/pedidos/correios?lote%5B%5D=PG-1",
      { headers: { "X-Requested-With": "fetch" } }
    );
    expect(root.querySelector("[data-cor-state]").dataset.corState).toBe("done");
  });

  it("stops on its own once nothing is in flight", async () => {
    vi.useFakeTimers();
    mount(cell("PG-1", "running"));
    respondWith(`<div data-part="correios-PG-1" data-cor-state="done"></div>`);

    const feedback = build();
    feedback.start();
    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);
    expect(feedback.running).toBe(false);

    await vi.advanceTimersByTimeAsync(60_000);
    expect(window.fetch).toHaveBeenCalledTimes(1);
  });

  it("keeps polling while the label is still moving, and reports each swap", async () => {
    vi.useFakeTimers();
    mount(cell("PG-1", "queued"));
    respondWith(`<div data-part="correios-PG-1" data-cor-state="running"></div>`);
    const onSwap = vi.fn();

    build({ onSwap }).start();
    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);
    await vi.advanceTimersByTimeAsync(POLL_STEPS[1]);

    expect(window.fetch).toHaveBeenCalledTimes(2);
    expect(onSwap).toHaveBeenCalledTimes(2);
  });

  it("skips a tick while the table is mid-reload rather than racing it", async () => {
    vi.useFakeTimers();
    mount(cell("PG-1", "running"));
    respondWith(`<div data-part="correios-PG-1" data-cor-state="running"></div>`);
    root.classList.add("is-loading");

    build().start();
    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);
    expect(window.fetch).not.toHaveBeenCalled();

    root.classList.remove("is-loading");
    await vi.advanceTimersByTimeAsync(POLL_STEPS[1]);
    expect(window.fetch).toHaveBeenCalledTimes(1);
  });

  it("survives a failed request and tries again on the next tick", async () => {
    vi.useFakeTimers();
    mount(cell("PG-1", "running"));
    vi.spyOn(window, "fetch").mockRejectedValue(new Error("offline"));

    build().start();
    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);
    await vi.advanceTimersByTimeAsync(POLL_STEPS[1]);

    expect(window.fetch).toHaveBeenCalledTimes(2);
    expect(poller.running).toBe(true);
  });

  it("gives up after the hard ceiling instead of polling forever", async () => {
    vi.useFakeTimers();
    mount(cell("PG-1", "running"));
    respondWith(`<div data-part="correios-PG-1" data-cor-state="running"></div>`);
    let clock = 0;

    build({ now: () => clock }).start();
    clock = POLL_MAX_MS + 1;
    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);

    expect(window.fetch).not.toHaveBeenCalled();
    expect(poller.running).toBe(false);
  });

  it("pauses in a hidden tab and picks up again when it comes back", async () => {
    vi.useFakeTimers();
    mount(cell("PG-1", "running"));
    respondWith(`<div data-part="correios-PG-1" data-cor-state="running"></div>`);

    build().start();
    setVisibility("hidden");
    await vi.advanceTimersByTimeAsync(60_000);
    expect(window.fetch).not.toHaveBeenCalled();

    setVisibility("visible");
    await vi.advanceTimersByTimeAsync(POLL_STEPS[0]);
    expect(window.fetch).toHaveBeenCalledTimes(1);
  });

  it("stays quiet when the tab returns and the poller was never started", async () => {
    vi.useFakeTimers();
    build();

    setVisibility("visible");
    await vi.advanceTimersByTimeAsync(60_000);

    expect(poller.running).toBe(false);
  });

  it("a manual poll before start is a no-op", async () => {
    respondWith("");
    await build().poll();

    expect(window.fetch).not.toHaveBeenCalled();
  });

  it("stop and destroy both cancel the pending tick", async () => {
    vi.useFakeTimers();
    mount(cell("PG-1", "running"));
    respondWith("");

    const feedback = build();
    feedback.start();
    feedback.stop();
    await vi.advanceTimersByTimeAsync(60_000);
    expect(window.fetch).not.toHaveBeenCalled();

    feedback.start();
    feedback.destroy();
    await vi.advanceTimersByTimeAsync(60_000);
    expect(window.fetch).not.toHaveBeenCalled();
  });
});

describe("applyRowStatus", () => {
  it("carries a swapped-in status up to the row the bulk bar reads", () => {
    mount(cell("PG-1", "done", "in_production"));
    root.querySelector("[data-row-status]").dataset.rowStatus = "label_issued";

    applyRowStatus(root);

    expect(root.querySelector("tr").dataset.status).toBe("label_issued");
  });

  it("ignores a status cell that is not inside a row", () => {
    document.body.innerHTML = `<div class="app"><div data-row-status="shipped"></div></div>`;
    expect(() => applyRowStatus(document.querySelector(".app"))).not.toThrow();
  });
});
