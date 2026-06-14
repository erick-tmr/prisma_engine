function pad(value) {
  return String(value).padStart(2, "0");
}

export function createPaymentCountdown(root, onExpire) {
  const deadline = new Date(root.dataset.deadline).getTime();
  const hEl = root.querySelector("[data-cd-h]");
  const mEl = root.querySelector("[data-cd-m]");
  const sEl = root.querySelector("[data-cd-s]");

  function tick() {
    let remaining = Math.floor((deadline - Date.now()) / 1000);
    if (remaining <= 0) {
      onExpire();
      return false;
    }
    const hours = Math.floor(remaining / 3600);
    remaining -= hours * 3600;
    const minutes = Math.floor(remaining / 60);
    hEl.textContent = pad(hours);
    mEl.textContent = pad(minutes);
    sEl.textContent = pad(remaining - minutes * 60);
    return true;
  }

  return { tick };
}

/* v8 ignore start -- browser bootstrap; createPaymentCountdown is unit-tested */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-countdown]");
  if (root && root.dataset.deadline) {
    const countdown = createPaymentCountdown(root, () => window.location.reload());
    if (countdown.tick()) {
      const timer = setInterval(() => {
        if (!countdown.tick()) clearInterval(timer);
      }, 1000);
    }
  }
}
/* v8 ignore stop */
