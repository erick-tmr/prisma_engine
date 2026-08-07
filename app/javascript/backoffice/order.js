import { bindConfirm, bindFlashDismiss } from "backoffice/shell";
import { createLabelFeedback, inFlight } from "backoffice/label_feedback";

export const ELAPSED_TICK_MS = 1_000;
export const RETRY_FAILED = "Não foi possível reenviar para os Correios. Tente novamente.";

export function bindMenu(root) {
  const toggle = root.querySelector("[data-menu-toggle]");
  const sidebar = root.querySelector("[data-sidebar]");
  toggle.addEventListener("click", () => sidebar.classList.toggle("show"));
}

export function elapsedText(seconds) {
  if (seconds < 60) return `${seconds}s`;

  return `${Math.floor(seconds / 60)}min ${seconds % 60}s`;
}

export function tickElapsed(root, now = Date.now()) {
  root.querySelectorAll("[data-elapsed-since]").forEach((el) => {
    const since = Date.parse(el.dataset.elapsedSince);
    if (Number.isNaN(since)) return;

    el.textContent = elapsedText(Math.max(0, Math.round((now - since) / 1000)));
  });
}

export function initOrder(root, doc = document) {
  const feedback = createLabelFeedback(root, {
    path: root.dataset.feedbackUrl,
    onSwap: () => { bindConfirm(root); tickElapsed(root); }
  });

  async function retryLabel(url) {
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "X-CSRF-Token": doc.querySelector('meta[name="csrf-token"]')?.content ?? "", "Accept": "application/json" }
      });
      if (!res.ok) throw new Error(String(res.status));

      feedback.start();
    } catch (e) {
      window.alert(RETRY_FAILED);
    }
  }

  root.addEventListener("click", (event) => {
    const retry = event.target.closest("[data-retry-url]");
    if (retry) retryLabel(retry.dataset.retryUrl);
  });

  bindConfirm(root);
  bindMenu(root);
  bindFlashDismiss(root);
  tickElapsed(root);
  const ticker = setInterval(() => tickElapsed(root), ELAPSED_TICK_MS);
  if (inFlight(root)) feedback.start();

  return {
    feedback,
    destroy() {
      clearInterval(ticker);
      feedback.destroy();
    }
  };
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-bo-order]");
  if (root) initOrder(root);
}
/* v8 ignore stop */
