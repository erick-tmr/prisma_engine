// Backoffice login behaviour (show/hide password + caps-lock awareness),
// extracted so it can be unit tested (see test/javascript/backoffice/login.test.js).
// Shipped as a self-contained native ES module via
// `javascript_include_tag "backoffice/login", type: "module"` — no importmap,
// no build step. The browser runs the guarded auto-init at the bottom; tests
// import the named functions and drive them against a jsdom fixture. Keep this
// in sync with app/views/admin/sessions/new.html.erb's data hooks.

export function togglePassword(input, button) {
  const showing = input.type === "password";
  input.type = showing ? "text" : "password";
  button.querySelector("i").className = showing ? "bi bi-eye-slash" : "bi bi-eye";
  const label = showing ? button.dataset.hideLabel : button.dataset.showLabel;
  button.setAttribute("aria-label", label);
  button.setAttribute("title", label);
  input.focus();
}

export function capsOn(event) {
  return event.getModifierState("CapsLock");
}

export function bindLogin(root) {
  const input = root.querySelector("[data-bo-password]");
  const toggle = root.querySelector("[data-bo-toggle]");
  const caps = root.querySelector("[data-bo-caps]");

  toggle.addEventListener("click", () => togglePassword(input, toggle));

  const sync = (event) => caps.classList.toggle("is-visible", capsOn(event));
  input.addEventListener("keydown", sync);
  input.addEventListener("keyup", sync);
  input.addEventListener("blur", () => caps.classList.remove("is-visible"));
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-bo-login]");
  if (root) bindLogin(root);
}
/* v8 ignore stop */
