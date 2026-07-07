import { afterEach, describe, expect, it, vi } from "vitest";
import {
  COOKIE_NAME,
  getCookie,
  setCookie,
  initFirstVisitWarning,
} from "../../app/javascript/storefront/first_visit_warning.js";

function mountWarning() {
  document.body.innerHTML = `
    <div class="aviso-overlay" data-first-visit-warning aria-hidden="true">
      <div class="aviso-card">
        <div class="aviso-card__body" data-aviso-body tabindex="0"></div>
        <button class="aviso-btn" data-aviso-ok disabled></button>
      </div>
    </div>
  `;
  return document.querySelector("[data-first-visit-warning]");
}

function setScrollMetrics(el, { scrollHeight, clientHeight, scrollTop }) {
  Object.defineProperty(el, "scrollHeight", { value: scrollHeight, configurable: true });
  Object.defineProperty(el, "clientHeight", { value: clientHeight, configurable: true });
  Object.defineProperty(el, "scrollTop", { value: scrollTop, writable: true, configurable: true });
}

afterEach(() => {
  document.body.innerHTML = "";
  document.body.style.overflow = "";
  document.cookie.split(";").forEach((entry) => {
    const name = entry.split("=")[0].trim();
    if (name) document.cookie = `${name}=; path=/; max-age=0`;
  });
  vi.useRealTimers();
});

describe("cookie helpers", () => {
  it("round-trips a value and returns empty string when absent", () => {
    expect(getCookie("missing")).toBe("");
    setCookie("foo", "bar", 1);
    expect(getCookie("foo")).toBe("bar");
  });
});

describe("initFirstVisitWarning", () => {
  it("opens the modal and enables the button when content fits without scrolling", () => {
    const root = mountWarning();
    setScrollMetrics(root.querySelector("[data-aviso-body]"), {
      scrollHeight: 200,
      clientHeight: 300,
      scrollTop: 0,
    });

    initFirstVisitWarning(root);

    expect(root.classList.contains("is-open")).toBe(true);
    expect(root.getAttribute("aria-hidden")).toBe("false");
    expect(document.body.style.overflow).toBe("hidden");
    const button = root.querySelector("[data-aviso-ok]");
    expect(button.disabled).toBe(false);
    expect(root.querySelector(".aviso-card").classList.contains("is-read")).toBe(true);
  });

  it("keeps the button disabled until the body is scrolled to the bottom", () => {
    const root = mountWarning();
    const body = root.querySelector("[data-aviso-body]");
    setScrollMetrics(body, { scrollHeight: 500, clientHeight: 300, scrollTop: 0 });

    initFirstVisitWarning(root);
    const button = root.querySelector("[data-aviso-ok]");
    expect(button.disabled).toBe(true);
    expect(root.querySelector(".aviso-card").classList.contains("is-read")).toBe(false);

    body.scrollTop = 200;
    body.dispatchEvent(new Event("scroll"));
    expect(button.disabled).toBe(false);
    expect(root.querySelector(".aviso-card").classList.contains("is-read")).toBe(true);

    body.dispatchEvent(new Event("scroll"));
    expect(button.disabled).toBe(false);
  });

  it("writes the cookie and closes the modal when the enabled button is clicked", () => {
    vi.useFakeTimers();
    const root = mountWarning();
    setScrollMetrics(root.querySelector("[data-aviso-body]"), {
      scrollHeight: 200,
      clientHeight: 300,
      scrollTop: 0,
    });

    initFirstVisitWarning(root);
    expect(getCookie(COOKIE_NAME)).toBe("");

    root.querySelector("[data-aviso-ok]").click();

    expect(getCookie(COOKIE_NAME)).toBe("1");
    expect(root.classList.contains("is-open")).toBe(false);
    expect(root.getAttribute("aria-hidden")).toBe("true");
    expect(document.body.style.overflow).toBe("");
    expect(root.isConnected).toBe(true);

    vi.runAllTimers();
    expect(root.isConnected).toBe(false);
  });

  it("ignores clicks while the button is still disabled", () => {
    const root = mountWarning();
    setScrollMetrics(root.querySelector("[data-aviso-body]"), {
      scrollHeight: 500,
      clientHeight: 300,
      scrollTop: 0,
    });

    initFirstVisitWarning(root);
    root.querySelector("[data-aviso-ok]").click();

    expect(getCookie(COOKIE_NAME)).toBe("");
    expect(root.classList.contains("is-open")).toBe(true);
  });
});
