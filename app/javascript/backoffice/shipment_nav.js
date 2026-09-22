export function initShipmentNav(panel) {
  const views = [...panel.querySelectorAll("[data-shipment-view]")];
  const latest = views.length - 1;
  const prev = panel.querySelector('[data-shipment-step="-1"]');
  const next = panel.querySelector('[data-shipment-step="1"]');
  const position = panel.querySelector("[data-shipment-pos]");
  let current = latest;

  function show(index) {
    if (index < 0 || index > latest || index === current) return;

    const view = views[index];
    view.classList.remove("from-left", "from-right");
    view.classList.add(index < current ? "from-left" : "from-right");
    views[current].hidden = true;
    view.hidden = false;
    current = index;
    position.textContent = String(index + 1);
    prev.disabled = index === 0;
    next.disabled = index === latest;
  }

  panel.addEventListener("click", (event) => {
    const step = event.target.closest("[data-shipment-step]");
    if (step) show(current + Number(step.dataset.shipmentStep));
    if (event.target.closest("[data-shipment-latest]")) show(latest);
  });

  panel.addEventListener("keydown", (event) => {
    if (event.key === "ArrowLeft") show(current - 1);
    if (event.key === "ArrowRight") show(current + 1);
  });

  return {
    show,
    get current() { return current; }
  };
}

export function bindShipmentNav(root) {
  return [...root.querySelectorAll("[data-shipment-nav]")]
    .filter((panel) => panel.querySelectorAll("[data-shipment-view]").length > 1)
    .map(initShipmentNav);
}
