import { beforeEach, describe, expect, it } from "vitest";
import { togglePassword, capsOn, bindLogin } from "../../../app/javascript/backoffice/login.js";

// Mirrors the data hooks in app/views/admin/sessions/new.html.erb: the password
// input ([data-bo-password]), the show/hide toggle ([data-bo-toggle]) with its
// pt-BR labels, and the caps-lock hint ([data-bo-caps]).
function mountLogin() {
  document.body.innerHTML = `
    <div data-bo-login>
      <input data-bo-password type="password" value="hunter2">
      <button type="button" data-bo-toggle
              data-show-label="Mostrar senha" data-hide-label="Ocultar senha"
              aria-label="Mostrar senha" title="Mostrar senha">
        <i class="bi bi-eye"></i>
      </button>
      <span data-bo-caps class="bo-login__caps"></span>
    </div>`;
  return document.querySelector("[data-bo-login]");
}

function fireKey(el, type, capsLock) {
  const event = new window.KeyboardEvent(type, { bubbles: true });
  event.getModifierState = (key) => key === "CapsLock" && capsLock;
  el.dispatchEvent(event);
}

describe("togglePassword", () => {
  let input;
  let button;

  beforeEach(() => {
    mountLogin();
    input = document.querySelector("[data-bo-password]");
    button = document.querySelector("[data-bo-toggle]");
  });

  it("reveals the password: type, icon and labels flip to the hidden state", () => {
    togglePassword(input, button);

    expect(input.type).toBe("text");
    expect(button.querySelector("i").className).toBe("bi bi-eye-slash");
    expect(button.getAttribute("aria-label")).toBe("Ocultar senha");
    expect(button.getAttribute("title")).toBe("Ocultar senha");
  });

  it("toggles back to a masked password on a second call", () => {
    togglePassword(input, button);
    togglePassword(input, button);

    expect(input.type).toBe("password");
    expect(button.querySelector("i").className).toBe("bi bi-eye");
    expect(button.getAttribute("aria-label")).toBe("Mostrar senha");
  });
});

describe("capsOn", () => {
  it("reflects the CapsLock modifier state of the event", () => {
    expect(capsOn({ getModifierState: (key) => key === "CapsLock" })).toBe(true);
    expect(capsOn({ getModifierState: () => false })).toBe(false);
  });
});

describe("bindLogin", () => {
  let root;
  let input;
  let toggle;
  let caps;

  beforeEach(() => {
    root = mountLogin();
    input = root.querySelector("[data-bo-password]");
    toggle = root.querySelector("[data-bo-toggle]");
    caps = root.querySelector("[data-bo-caps]");
    bindLogin(root);
  });

  it("wires the toggle button to reveal/mask the password", () => {
    toggle.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    expect(input.type).toBe("text");

    toggle.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    expect(input.type).toBe("password");
  });

  it("shows the caps-lock hint while Caps Lock is on and hides it otherwise", () => {
    fireKey(input, "keydown", true);
    expect(caps.classList.contains("is-visible")).toBe(true);

    fireKey(input, "keyup", false);
    expect(caps.classList.contains("is-visible")).toBe(false);
  });

  it("clears the caps-lock hint when the password field loses focus", () => {
    fireKey(input, "keydown", true);
    expect(caps.classList.contains("is-visible")).toBe(true);

    input.dispatchEvent(new window.FocusEvent("blur"));
    expect(caps.classList.contains("is-visible")).toBe(false);
  });
});
