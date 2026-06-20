function setOpen(item, button, open) {
  item.classList.toggle("is-open", open);
  button.setAttribute("aria-expanded", String(open));
}

export function bindAccordion(scope) {
  scope.querySelectorAll("[data-faq-item]").forEach(function (item, idx) {
    const button = item.querySelector("[data-faq-toggle]");
    setOpen(item, button, idx === 0);
    button.addEventListener("click", function () {
      setOpen(item, button, !item.classList.contains("is-open"));
    });
  });
}

export function setActiveRail(railLinks, activeId) {
  railLinks.forEach(function (link) {
    link.classList.toggle("is-active", link.dataset.target === activeId);
  });
}

export function bindRailNavigation(doc) {
  doc.querySelectorAll("[data-rail-link]").forEach(function (link) {
    link.addEventListener("click", function (event) {
      event.preventDefault();
      const target = doc.getElementById(link.dataset.target);
      if (!target) return;
      const view = doc.defaultView;
      view.scrollTo({
        top: target.getBoundingClientRect().top + view.scrollY - 16,
        behavior: "smooth",
      });
    });
  });
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector("[data-faq]");
  if (root) {
    bindAccordion(root);
    bindRailNavigation(document);

    const railLinks = document.querySelectorAll("[data-rail-link]");
    const groups = document.querySelectorAll("[data-faq-group]");
    if (groups.length && "IntersectionObserver" in window) {
      const spy = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (entry) {
            if (entry.isIntersecting) setActiveRail(railLinks, entry.target.id);
          });
        },
        { rootMargin: "-20% 0px -70% 0px", threshold: 0 }
      );
      groups.forEach(function (group) {
        spy.observe(group);
      });
    }
  }
}
/* v8 ignore stop */
