import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  appendCanned, bulkBody, confirmMessage, csrfHeader, fillTemplate, initQuestions
} from "../../../app/javascript/backoffice/questions.js";

const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
const type = (el, value) => {
  el.value = value;
  el.dispatchEvent(new window.Event("input", { bubbles: true }));
};
const press = (key) => document.dispatchEvent(new window.KeyboardEvent("keydown", { key, bubbles: true }));

const row = (id) => `
  <tr data-question="${id}" data-status="awaiting_answer">
    <td><span class="rowcheck" data-check="${id}"></span></td>
  </tr>`;

const drawer = (extra = "") => `
  <div class="dw-head"><a class="dw-close" href="/admin/perguntas"></a></div>
  <form class="dw-form" id="dw-form">
    <div class="dw-body">
      <button type="button" data-canned-body="Prazo de 3 a 5 dias úteis."></button>
      <button type="button" data-canned-save></button>
      <span class="lc" data-answer-counter>0 caracteres</span>
      <textarea data-answer-body data-counter-template="{n} caracteres"></textarea>
    </div>
    <div class="dw-foot"><button type="button" data-spam-open></button></div>
  </form>${extra}`;

const shell = ({ drawerContent = "", spam = true } = {}) => `
  <div class="app" data-list="questions" data-bulk-url="/admin/perguntas/lote" data-bulk-error="falhou">
    <aside data-sidebar></aside>
    <button id="menu-toggle" type="button"></button>
    <input id="q-q" type="text" data-filter="q">
    <div data-part="chips"></div>
    <span data-part="count">0</span>
    <div data-part="table">
      <table><tbody id="questions-body">${row("11")}${row("12")}</tbody></table>
      <span class="rowcheck" id="q-checkall"></span>
    </div>
    <div class="bulkbar" id="bulkbar" hidden>
      <b id="bulk-n">0</b>
      <button id="bulk-clear" type="button"></button>
      <button data-bulk="archive" type="button"></button>
      <button data-bulk="spam" type="button"
              data-confirm-one="Marcar esta pergunta como spam?"
              data-confirm-other="Marcar {n} perguntas como spam?"></button>
    </div>
    <div class="scrim" id="scrim" data-drawer-close></div>
    <aside class="drawer" id="drawer" aria-hidden="true">
      <div data-part="drawer" class="dw-part">${drawerContent}</div>
    </aside>
    <div data-part="spam">
      ${spam ? `<div class="scrim" id="mscrim"></div>
      <div class="modal" id="spam-modal" aria-hidden="true">
        <button type="button" data-spam-close></button>
      </div>` : ""}
    </div>
    <div class="scrim" id="cscrim" data-canned-close></div>
    <div class="modal" id="canned-modal" aria-hidden="true">
      <button type="button" data-canned-close></button>
      <form id="canned-form" action="/admin/respostas_prontas" data-create-url="/admin/respostas_prontas">
        <input type="hidden" id="canned-method" value="post">
        <span data-canned-form-title data-title-new="Nova resposta pronta"
              data-title-edit="Editando {label}">Nova resposta pronta</span>
        <input type="text" id="canned-label">
        <textarea id="canned-body"></textarea>
        <button type="button" data-canned-reset hidden></button>
        <span data-canned-submit data-label-add="Adicionar" data-label-edit="Salvar alterações">Adicionar</span>
        <button type="button" data-canned-edit="/admin/respostas_prontas/7"
                data-label="Garantia" data-body="Noventa dias de garantia."></button>
      </form>
    </div>
    <button type="button" data-canned-open id="open-manager"></button>
  </div>
  <div class="toasts" id="toasts"></div>`;

let started;

const start = (markup = shell()) => {
  document.body.innerHTML = markup;
  const root = document.querySelector(".app");
  const instance = initQuestions(root);
  started.push(instance);
  return { root, instance };
};

beforeEach(() => {
  started = [];
  window.history.pushState({}, "", "/admin/perguntas");
  vi.spyOn(window, "fetch").mockResolvedValue({
    text: async () => `<span data-part="count">1</span><div data-part="table"></div>`,
    json: async () => ({ done: 2, skipped: 0, message: "2 perguntas arquivadas e fora da loja." })
  });
});

afterEach(() => {
  started.forEach((instance) => instance.destroy());
  document.body.innerHTML = "";
  vi.restoreAllMocks();
  vi.useRealTimers();
  window.history.pushState({}, "", "/");
});

describe("pure helpers", () => {
  it("appends a shortcut under whatever is already written", () => {
    expect(appendCanned("", "Prazo de 5 dias.")).toBe("Prazo de 5 dias.");
    expect(appendCanned("  ", "Prazo de 5 dias.")).toBe("Prazo de 5 dias.");
    expect(appendCanned("Olá! ", "Prazo de 5 dias.")).toBe("Olá!\n\nPrazo de 5 dias.");
  });

  it("fills the count into a template", () => {
    expect(fillTemplate("{n} caracteres", 12)).toBe("12 caracteres");
  });

  it("builds a bulk form body", () => {
    expect(bulkBody("spam", [ "3", "4" ]).toString()).toBe("event=spam&question_ids%5B%5D=3&question_ids%5B%5D=4");
  });

  it("picks the singular or plural confirmation", () => {
    const button = document.createElement("button");
    button.dataset.confirmOne = "uma?";
    button.dataset.confirmOther = "{n} perguntas?";

    expect(confirmMessage(button, 1)).toBe("uma?");
    expect(confirmMessage(button, 4)).toBe("4 perguntas?");
  });

  it("reads the csrf token, tolerating a page without one", () => {
    expect(csrfHeader(document)["X-CSRF-Token"]).toBe("");

    document.head.innerHTML = `<meta name="csrf-token" content="abc123">`;
    expect(csrfHeader(document)["X-CSRF-Token"]).toBe("abc123");
    document.head.innerHTML = "";
  });
});

describe("the drawer", () => {
  it("stays shut while no question is named", () => {
    const { root } = start();

    expect(root.querySelector("#drawer").classList.contains("open")).toBe(false);
    expect(root.querySelector("#drawer").getAttribute("aria-hidden")).toBe("true");
  });

  it("opens when the server hands back a question", () => {
    const { root } = start(shell({ drawerContent: drawer() }));

    expect(root.querySelector("#drawer").classList.contains("open")).toBe(true);
    expect(root.querySelector("#scrim").classList.contains("open")).toBe(true);
    expect(root.querySelector("#drawer").getAttribute("aria-hidden")).toBe("false");
  });

  it("names the clicked question in the url", async () => {
    const { root } = start();
    click(root.querySelector('tr[data-question="11"]'));
    await vi.waitFor(() => expect(window.fetch).toHaveBeenCalled());

    expect(window.fetch.mock.calls[0][0]).toBe("/admin/perguntas?pergunta=11");
  });

  it("keeps the page when opening a question from deeper in the list", async () => {
    window.history.pushState({}, "", "/admin/perguntas?page=3");
    const { root } = start();
    click(root.querySelector('tr[data-question="12"]'));
    await vi.waitFor(() => expect(window.fetch).toHaveBeenCalled());

    expect(window.fetch.mock.calls[0][0]).toBe("/admin/perguntas?page=3&pergunta=12");
  });

  it("closes on the scrim and on Escape", async () => {
    window.history.pushState({}, "", "/admin/perguntas?pergunta=11");
    const { root } = start(shell({ drawerContent: drawer() }));

    click(root.querySelector("#scrim"));
    await vi.waitFor(() => expect(window.fetch).toHaveBeenCalledWith("/admin/perguntas", expect.anything()));

    press("Escape");
    await vi.waitFor(() => expect(window.fetch).toHaveBeenCalledTimes(2));
  });

  it("ignores Escape when nothing is open", () => {
    start();
    press("Escape");
    press("Enter");

    expect(window.fetch).not.toHaveBeenCalled();
  });
});

describe("the answer composer", () => {
  it("counts the characters as the operator types", () => {
    const { root } = start(shell({ drawerContent: drawer() }));
    type(root.querySelector("[data-answer-body]"), "Roda no GBA.");

    expect(root.querySelector("[data-answer-counter]").textContent).toBe("12 caracteres");
  });

  it("drops a shortcut into the answer and recounts", () => {
    const { root } = start(shell({ drawerContent: drawer() }));
    click(root.querySelector("[data-canned-body]"));

    expect(root.querySelector("[data-answer-body]").value).toBe("Prazo de 3 a 5 dias úteis.");
    expect(root.querySelector("[data-answer-counter]").textContent).toBe("26 caracteres");
  });

  it("ignores input from fields that are not the answer", () => {
    const { root } = start(shell({ drawerContent: drawer() }));
    type(root.querySelector("#canned-label"), "Garantia");

    expect(root.querySelector("[data-answer-counter]").textContent).toBe("0 caracteres");
  });
});

describe("the spam confirmation", () => {
  it("opens and closes without leaving the drawer", () => {
    const { root } = start(shell({ drawerContent: drawer() }));

    click(root.querySelector("[data-spam-open]"));
    expect(root.querySelector("#spam-modal").classList.contains("open")).toBe(true);

    click(root.querySelector("[data-spam-close]"));
    expect(root.querySelector("#spam-modal").classList.contains("open")).toBe(false);
  });

  it("Escape closes the confirmation before the drawer", async () => {
    const { root } = start(shell({ drawerContent: drawer() }));
    click(root.querySelector("[data-spam-open]"));

    press("Escape");
    expect(root.querySelector("#spam-modal").classList.contains("open")).toBe(false);
    expect(window.fetch).not.toHaveBeenCalled();
  });

  it("does nothing on a question that is already spam", () => {
    const { root } = start(shell({ drawerContent: drawer(), spam: false }));

    expect(() => click(root.querySelector("[data-spam-open]"))).not.toThrow();
    expect(root.querySelector("#spam-modal")).toBeNull();
  });
});

describe("the canned replies manager", () => {
  it("opens empty from the panel and prefilled from the composer", () => {
    const { root } = start(shell({ drawerContent: drawer() }));

    click(root.querySelector("#open-manager"));
    expect(root.querySelector("#canned-modal").classList.contains("open")).toBe(true);
    expect(root.querySelector("#canned-body").value).toBe("");

    type(root.querySelector("[data-answer-body]"), "  Resposta escrita à mão.  ");
    click(root.querySelector("[data-canned-save]"));
    expect(root.querySelector("#canned-body").value).toBe("Resposta escrita à mão.");
  });

  it("points the form at the shortcut being edited and back again", () => {
    const { root } = start();
    click(root.querySelector("[data-canned-edit]"));

    const form = root.querySelector("#canned-form");
    expect(form.getAttribute("action")).toBe("/admin/respostas_prontas/7");
    expect(root.querySelector("#canned-method").value).toBe("patch");
    expect(root.querySelector("#canned-label").value).toBe("Garantia");
    expect(root.querySelector("[data-canned-form-title]").textContent).toBe("Editando Garantia");
    expect(root.querySelector("[data-canned-submit]").textContent).toBe("Salvar alterações");
    expect(root.querySelector("[data-canned-reset]").hidden).toBe(false);

    click(root.querySelector("[data-canned-reset]"));
    expect(form.getAttribute("action")).toBe("/admin/respostas_prontas");
    expect(root.querySelector("#canned-method").value).toBe("post");
    expect(root.querySelector("[data-canned-form-title]").textContent).toBe("Nova resposta pronta");
    expect(root.querySelector("[data-canned-submit]").textContent).toBe("Adicionar");
    expect(root.querySelector("[data-canned-reset]").hidden).toBe(true);
  });

  it("drops the reopen flag from the url when it closes", () => {
    window.history.pushState({}, "", "/admin/perguntas?status=spam&respostas=1");
    const { root } = start();

    click(root.querySelector("[data-canned-close]"));
    expect(root.querySelector("#canned-modal").classList.contains("open")).toBe(false);
    expect(window.location.search).toBe("?status=spam");
  });

  it("leaves a clean url alone", () => {
    const { root } = start();
    click(root.querySelector("[data-canned-close]"));

    expect(window.location.search).toBe("");
  });

  it("Escape closes the manager and leaves the drawer open behind it", () => {
    const { root } = start(shell({ drawerContent: drawer() }));
    click(root.querySelector("#open-manager"));

    press("Escape");
    expect(root.querySelector("#canned-modal").classList.contains("open")).toBe(false);
    expect(root.querySelector("#drawer").classList.contains("open")).toBe(true);
    expect(window.fetch).not.toHaveBeenCalled();
  });
});

describe("selection and bulk actions", () => {
  it("selects rows, selects them all and clears", () => {
    const { root } = start();
    const bulkbar = root.querySelector("#bulkbar");

    click(root.querySelector('[data-check="11"]'));
    expect(bulkbar.hidden).toBe(false);
    expect(root.querySelector("#bulk-n").textContent).toBe("1");
    expect(root.querySelector("#q-checkall").classList.contains("ind")).toBe(true);

    click(root.querySelector('[data-check="11"]'));
    expect(bulkbar.hidden).toBe(true);
    click(root.querySelector('[data-check="11"]'));

    click(root.querySelector("#q-checkall"));
    expect(root.querySelector("#bulk-n").textContent).toBe("2");
    expect(root.querySelector("#q-checkall").classList.contains("on")).toBe(true);

    click(root.querySelector("#q-checkall"));
    expect(bulkbar.hidden).toBe(true);

    click(root.querySelector('[data-check="12"]'));
    click(root.querySelector("#bulk-clear"));
    expect(bulkbar.hidden).toBe(true);
  });

  it("posts the selection and toasts what came back", async () => {
    const { root } = start();
    click(root.querySelector('[data-check="11"]'));
    click(root.querySelector('[data-check="12"]'));
    click(root.querySelector('[data-bulk="archive"]'));

    await vi.waitFor(() => expect(document.querySelector(".toast")).not.toBeNull());
    const [ url, options ] = window.fetch.mock.calls[0];

    expect(url).toBe("/admin/perguntas/lote");
    expect(options.body.toString()).toBe("event=archive&question_ids%5B%5D=11&question_ids%5B%5D=12");
    expect(document.querySelector(".toast").textContent).toContain("2 perguntas arquivadas");
    expect(root.querySelector("#bulkbar").hidden).toBe(true);
  });

  it("asks before striking accounts and honours a refusal", async () => {
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false);
    const { root } = start();
    click(root.querySelector('[data-check="11"]'));
    click(root.querySelector('[data-bulk="spam"]'));

    expect(confirmSpy).toHaveBeenCalledWith("Marcar esta pergunta como spam?");
    expect(window.fetch).not.toHaveBeenCalled();

    confirmSpy.mockReturnValue(true);
    click(root.querySelector('[data-bulk="spam"]'));
    await vi.waitFor(() => expect(document.querySelector(".toast")).not.toBeNull());
    expect(document.querySelector(".toast").classList.contains("toast-warn")).toBe(true);
  });

  it("does nothing when nothing is selected", () => {
    const { root } = start();
    click(root.querySelector('[data-bulk="archive"]'));

    expect(window.fetch).not.toHaveBeenCalled();
  });

  it("toasts a warning when the request fails", async () => {
    window.fetch.mockRejectedValue(new Error("offline"));
    const { root } = start();
    click(root.querySelector('[data-check="11"]'));
    click(root.querySelector('[data-bulk="archive"]'));

    await vi.waitFor(() => expect(document.querySelector(".toast")).not.toBeNull());
    expect(document.querySelector(".toast").textContent).toContain("falhou");
  });

  it("clears the toast after its delay", async () => {
    vi.useFakeTimers();
    const { root } = start();
    click(root.querySelector('[data-check="11"]'));
    click(root.querySelector('[data-bulk="archive"]'));

    await vi.waitFor(() => expect(document.querySelector(".toast")).not.toBeNull());
    vi.advanceTimersByTime(3600);
    expect(document.querySelector(".toast")).toBeNull();
  });
});
