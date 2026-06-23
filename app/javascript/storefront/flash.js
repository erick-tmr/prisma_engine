const FADE_MS = 150;

function dismissFlash(flash) {
  flash.style.transition = `opacity ${FADE_MS}ms ease`;
  flash.style.opacity = "0";
  setTimeout(function () {
    flash.remove();
  }, FADE_MS);
}

export function bindFlashDismiss(scope) {
  scope.querySelectorAll(".flash__close").forEach(function (button) {
    button.addEventListener("click", function () {
      const flash = button.closest(".flash");
      if (flash) dismissFlash(flash);
    });
  });
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  bindFlashDismiss(document);
}
/* v8 ignore stop */
