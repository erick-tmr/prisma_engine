export function createResendCooldown(root) {
  const deadline = new Date(root.dataset.resendDeadline).getTime();
  const button = root.querySelector("[data-resend-submit]");
  const status = root.querySelector("[data-resend-status]");
  const waitText = root.dataset.resendWaitText;

  function tick() {
    const remaining = Math.ceil((deadline - Date.now()) / 1000);
    if (remaining <= 0) {
      button.disabled = false;
      status.textContent = "";
      return false;
    }
    button.disabled = true;
    status.textContent = waitText.replace("{s}", String(remaining));
    return true;
  }

  return { tick };
}

/* v8 ignore start -- browser bootstrap; createResendCooldown is unit-tested */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-resend]");
  if (root && root.dataset.resendDeadline) {
    const cooldown = createResendCooldown(root);
    if (cooldown.tick()) {
      const timer = setInterval(() => {
        if (!cooldown.tick()) clearInterval(timer);
      }, 1000);
    }
  }
}
/* v8 ignore stop */
