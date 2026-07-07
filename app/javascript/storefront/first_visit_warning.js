export const COOKIE_NAME = "pg_aviso_home_v1";
const COOKIE_MAX_AGE_DAYS = 365;

export function getCookie(name) {
  const match = document.cookie.match(new RegExp("(?:^|; )" + name + "=([^;]*)"));
  return match ? decodeURIComponent(match[1]) : "";
}

export function setCookie(name, value, days) {
  const maxAge = days * 24 * 60 * 60;
  document.cookie = name + "=" + encodeURIComponent(value) + "; path=/; max-age=" + maxAge;
}

export function initFirstVisitWarning(root) {
  const card = root.querySelector(".aviso-card");
  const body = root.querySelector("[data-aviso-body]");
  const button = root.querySelector("[data-aviso-ok]");

  function markRead() {
    if (button.disabled) {
      button.disabled = false;
      card.classList.add("is-read");
    }
  }

  function checkScroll() {
    if (
      body.scrollHeight - body.clientHeight <= 4 ||
      body.scrollTop + body.clientHeight >= body.scrollHeight - 8
    ) {
      markRead();
    }
  }

  function close() {
    setCookie(COOKIE_NAME, "1", COOKIE_MAX_AGE_DAYS);
    root.classList.remove("is-open");
    root.setAttribute("aria-hidden", "true");
    document.body.style.overflow = "";
    setTimeout(() => root.remove(), 350);
  }

  body.addEventListener("scroll", checkScroll, { passive: true });
  button.addEventListener("click", () => {
    if (!button.disabled) close();
  });

  root.classList.add("is-open");
  root.setAttribute("aria-hidden", "false");
  document.body.style.overflow = "hidden";
  checkScroll();
  body.focus({ preventScroll: true });

  return { markRead, checkScroll, close };
}

/* v8 ignore start -- browser bootstrap; initFirstVisitWarning is unit-tested */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-first-visit-warning]");
  if (root) {
    requestAnimationFrame(() => initFirstVisitWarning(root));
  }
}
/* v8 ignore stop */
