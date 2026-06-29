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
  const railLinks = document.querySelectorAll("[data-rail-link]");
  if (railLinks.length) {
    bindRailNavigation(document);

    const groups = document.querySelectorAll("[data-topic-group]");
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
