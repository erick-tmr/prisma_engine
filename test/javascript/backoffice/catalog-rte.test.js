import { afterEach, describe, expect, it, vi } from "vitest";
import { initRte, prettyHtml } from "../../../app/javascript/backoffice/catalog-rte.js";

const click = (el) => el.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
const fire = (el, type) => el.dispatchEvent(new window.Event(type, { bubbles: true }));

function mount({ field = true, extras = true } = {}) {
  document.body.innerHTML = `
    <form id="ed-form">
      ${field ? `<input type="hidden" id="f-desc-field" value="<p>seed</p>">` : ""}
      <div class="rte" id="rte" ${extras ? `data-default="<p>padrão</p>"` : ""}>
        <div class="rte-toolbar" id="rte-toolbar">
          <button type="button" class="rte-btn" data-cmd="bold"><i></i></button>
          <button type="button" class="rte-btn" data-cmd="formatBlock" data-value="h2"><i></i></button>
          <button type="button" class="rte-btn" data-cmd="createLink"><i></i></button>
          <button type="button" class="rte-btn rte-code" id="rte-source"><i></i>HTML</button>
        </div>
        <div class="rte-area" id="f-desc" contenteditable="true"></div>
        <textarea class="rte-html" id="f-desc-html" hidden></textarea>
      </div>
      ${extras ? `<span class="default-tag" id="desc-default-tag"></span><button type="button" id="desc-restore"></button>` : ""}
    </form>`;
  return initRte(document);
}

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
});

describe("prettyHtml", () => {
  it("puts block tags on their own lines and indents list items", () => {
    const out = prettyHtml("<p>oi</p><ul><li>a</li><li>b</li></ul>");
    expect(out).toBe("<p>oi</p>\n<ul>\n    <li>a</li>\n    <li>b</li>\n</ul>");
  });

  it("handles empty input", () => {
    expect(prettyHtml("")).toBe("");
  });
});

describe("initRte", () => {
  it("returns null without an #rte host", () => {
    document.body.innerHTML = `<div></div>`;
    expect(initRte(document)).toBeNull();
  });

  it("seeds the surface from the hidden field", () => {
    const api = mount();
    expect(document.querySelector("#f-desc").innerHTML).toBe("<p>seed</p>");
    expect(api.getHtml()).toBe("<p>seed</p>");
  });

  it("toggles into and out of HTML source mode", () => {
    const api = mount();
    const srcBtn = document.querySelector("#rte-source");
    const area = document.querySelector("#f-desc");
    const source = document.querySelector("#f-desc-html");
    const bold = document.querySelector('[data-cmd="bold"]');

    click(srcBtn);
    expect(api.isSource()).toBe(true);
    expect(source.hidden).toBe(false);
    expect(area.hidden).toBe(true);
    expect(bold.disabled).toBe(true);
    expect(source.value).toContain("<p>seed</p>");
    expect(api.getHtml()).toContain("<p>seed</p>");

    click(bold);
    click(srcBtn);
    expect(api.isSource()).toBe(false);
    expect(bold.disabled).toBe(false);
  });

  it("runs a formatting command and mirrors the result into the field", () => {
    mount();
    const area = document.querySelector("#f-desc");
    area.innerHTML = "<p>edited</p>";
    click(document.querySelector('[data-cmd="bold"]'));
    expect(document.querySelector("#f-desc-field").value).toBe("<p>edited</p>");
  });

  it("wraps a heading button's data-value into a formatBlock tag", () => {
    mount();
    const exec = vi.fn();
    document.execCommand = exec;

    click(document.querySelector('[data-value="h2"]'));
    expect(exec).toHaveBeenCalledWith("formatBlock", false, "<h2>");

    click(document.querySelector('[data-cmd="bold"]'));
    expect(exec).toHaveBeenCalledWith("bold", false, null);

    delete document.execCommand;
  });

  it("prompts for a URL on createLink and ignores a cancel", () => {
    mount();
    const prompt = vi.spyOn(window, "prompt").mockReturnValueOnce("https://x").mockReturnValueOnce(null);
    const link = document.querySelector('[data-cmd="createLink"]');
    click(link);
    click(link);
    expect(prompt).toHaveBeenCalledTimes(2);
  });

  it("ignores clicks that miss a button", () => {
    const api = mount();
    click(document.querySelector("#rte-toolbar"));
    expect(api.isSource()).toBe(false);
  });

  it("keeps focus in the surface when a toolbar button is pressed", () => {
    mount();
    const bold = document.querySelector('[data-cmd="bold"]');
    const onButton = new window.MouseEvent("mousedown", { bubbles: true, cancelable: true });
    bold.dispatchEvent(onButton);
    expect(onButton.defaultPrevented).toBe(true);

    const onToolbar = new window.MouseEvent("mousedown", { bubbles: true, cancelable: true });
    document.querySelector("#rte-toolbar").dispatchEvent(onToolbar);
    expect(onToolbar.defaultPrevented).toBe(false);
  });

  it("adds a focus ring and hides the default tag on input", () => {
    mount();
    const wrap = document.querySelector("#rte");
    const area = document.querySelector("#f-desc");
    fire(area, "focus");
    expect(wrap.classList.contains("focus")).toBe(true);
    fire(area, "blur");
    expect(wrap.classList.contains("focus")).toBe(false);

    fire(area, "input");
    expect(document.querySelector("#desc-default-tag").hidden).toBe(true);
  });

  it("restores the default text, exiting source mode first", () => {
    mount();
    click(document.querySelector("#rte-source"));
    click(document.querySelector("#desc-restore"));
    expect(document.querySelector("#f-desc").innerHTML).toBe("<p>padrão</p>");
    expect(document.querySelector("#desc-default-tag").hidden).toBe(false);
    expect(document.querySelector("#f-desc-field").value).toBe("<p>padrão</p>");
  });

  it("flushes into the field on form submit", () => {
    mount();
    const area = document.querySelector("#f-desc");
    area.innerHTML = "<p>final</p>";
    fire(document.querySelector("#ed-form"), "submit");
    expect(document.querySelector("#f-desc-field").value).toBe("<p>final</p>");
  });

  it("works without the hidden field or optional controls", () => {
    const api = mount({ field: false, extras: false });
    expect(api.getHtml()).toBe("");
    fire(document.querySelector("#f-desc"), "input");
    expect(api.isSource()).toBe(false);
  });
});
