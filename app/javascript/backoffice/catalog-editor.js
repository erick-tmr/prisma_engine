
export const MONTHS = [
  "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
  "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"
];
export const DEFAULT_LANGUAGES = ["Português BR", "Inglês", "Japonês"];
export const DEFAULT_WEIGHT = 60;

export const CO_FIELDS = [
  { input: "f-co-title", echo: "cop-title" },
  { input: "f-co-sub", echo: "cop-sub" },
  { input: "f-co-game-label", echo: "cop-game-label" },
  { input: "f-co-game-ph", echo: "cop-game-ph" },
  { input: "f-co-game-hint", echo: "cop-game-hint" },
  { input: "f-co-game-error", echo: null },
  { input: "f-co-obs-label", echo: "cop-obs-label" },
  { input: "f-co-obs-ph", echo: "cop-obs-ph" }
];

const MSG = {
  nameRequired: "Dê um <b>nome</b> ao produto antes de salvar.",
  weightRequired: "O <b>peso base</b> precisa ser maior que zero.",
  brindeImage: "Cada <b>brinde</b> precisa de uma imagem.",
  gotmOn: "<b>Jogo do Mês</b> ativado: campos extras liberados abaixo.",
  customOrderOn: "<b>Sob encomenda</b> ativado: o formulário de pedido aparece na loja.",
  customOrderRestored: "Textos do formulário restaurados ao padrão."
};

export function plural(count, one, many) {
  return `${count} ${count === 1 ? one : many}`;
}

export function slugify(value) {
  return (value || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9\s-]/g, "").trim().replace(/\s+/g, "-").replace(/-+/g, "-");
}

export function moveItem(list, from, to) {
  const next = list.slice();
  const [moved] = next.splice(from, 1);
  next.splice(to, 0, moved);
  return next;
}

export function brindeWeight(brindes) {
  return brindes.reduce((sum, brinde) => sum + (parseInt(brinde.weight, 10) || 0), 0);
}

export function hasImage(item) {
  return Boolean(item.id || item.preview);
}

export function hydrate(graph) {
  const gotm = graph.gotm || {};
  return {
    photos: (graph.photos || []).map((photo) => ({ id: photo.id || null, key: null, url: photo.url || null, alt: photo.alt || "", preview: null })),
    groups: (graph.options || []).map((group) => ({
      name: group.group_name || "",
      values: (group.values || []).map((value) => ({ name: value.name || "", weight: value.weight || 0 }))
    })),
    tags: (graph.tags || []).slice(),
    brindes: (gotm.brindes || []).map((brinde) => ({
      id: brinde.id || null, key: null, url: brinde.url || null, preview: null,
      caption: brinde.caption || "", kind: brinde.kind || "", description: brinde.description || "", weight: brinde.weight || 0
    }))
  };
}

export function serialize(state, gotm) {
  return {
    options: state.groups.map((group) => ({
      group_name: group.name,
      values: group.values.map((value) => ({ name: value.name, weight: parseInt(value.weight, 10) || 0 }))
    })),
    tags: state.tags.slice(),
    photos: state.photos.filter(hasImage).map((photo) => photoRef(photo)),
    gotm: {
      enabled: gotm.enabled, year: gotm.year, month: gotm.month, position: gotm.position, blurb: gotm.blurb,
      brindes: state.brindes.filter(hasImage).map((brinde) => brindeRef(brinde))
    }
  };
}

function photoRef(photo) {
  const ref = photo.id ? { id: photo.id } : { key: photo.key };
  ref.alt = photo.alt;
  return ref;
}

function brindeRef(brinde) {
  const ref = brinde.id ? { id: brinde.id } : { key: brinde.key };
  return { ...ref, caption: brinde.caption, kind: brinde.kind, description: brinde.description, weight: parseInt(brinde.weight, 10) || 0 };
}

export function validate(state, fields) {
  if (!fields.name.trim()) return "nameRequired";
  if (!fields.weight || fields.weight < 1) return "weightRequired";
  if (fields.gotmEnabled && state.brindes.some((brinde) => !hasImage(brinde))) return "brindeImage";
  return null;
}

export function initEditor(root) {
  const form = root.querySelector("[data-catalog-editor]");
  if (!form) return null;

  const els = collectElements(root);
  const graph = JSON.parse(form.dataset.graph || "{}");
  const state = hydrate(graph);
  let seq = 0;
  const nextKey = (prefix) => `${prefix}-${seq++}`;

  const toast = (kind, html) => pushToast(root, kind, html);

  const renderPhotos = () => {
    els.photoGrid.replaceChildren();
    state.photos.forEach((photo, index) => els.photoGrid.appendChild(photoCard(photo, index)));
    els.photoGrid.appendChild(photoAdd());
    els.photoCount.textContent = plural(state.photos.length, "foto", "fotos");
  };

  const addPhoto = () => {
    state.photos.push({ id: null, key: nextKey("p"), url: null, alt: "", preview: null });
    renderPhotos();
  };

  function photoCard(photo, index) {
    const card = elt("div", "photo-card");
    card.draggable = true;
    card.dataset.i = index;
    const frame = elt("div", "photo-frame" + (imageUrl(photo) ? "" : " is-empty"));
    if (imageUrl(photo)) frame.style.backgroundImage = `url("${imageUrl(photo)}")`;
    frame.innerHTML = (imageUrl(photo) ? "" : `<div class="photo-empty-in"><i class="bi bi-image"></i><span>Enviar imagem</span></div>`) +
      (index === 0 ? `<span class="photo-cover-badge">Capa</span>` : "") +
      `<div class="photo-tools"><button type="button" class="drag" tabindex="-1"><i class="bi bi-arrows-move"></i></button>` +
      `<button type="button" class="rm" title="Remover"><i class="bi bi-trash"></i></button></div>`;
    frame.addEventListener("click", (event) => {
      if (event.target.closest(".photo-tools")) return;
      pickPhoto(photo, renderPhotos);
    });
    frame.querySelector(".rm").addEventListener("click", (event) => {
      event.stopPropagation();
      removePhotoFile(photo);
      state.photos.splice(index, 1);
      renderPhotos();
    });

    const meta = elt("div", "photo-meta");
    meta.innerHTML = `<div class="alt-lbl">Texto alternativo</div>`;
    const alt = document.createElement("input");
    alt.type = "text";
    alt.value = photo.alt || "";
    alt.placeholder = "Descreva a imagem…";
    alt.addEventListener("input", () => (photo.alt = alt.value));
    meta.appendChild(alt);

    card.append(frame, meta);
    attachDrag(card, state.photos, renderPhotos);
    return card;
  }

  function photoAdd() {
    const add = elt("div", "photo-add");
    add.innerHTML = `<i class="bi bi-plus-lg"></i><span>Adicionar foto</span>`;
    add.addEventListener("click", addPhoto);
    return add;
  }

  const pickPhoto = (photo, rerender) => selectFile(els.photoFiles, photo, `product[photo_files][${photo.key}]`, rerender);
  const removePhotoFile = (photo) => dropFile(els.photoFiles, photo.key);

  const renderGroups = () => {
    els.optGroups.replaceChildren();
    if (!state.groups.length) {
      els.optGroups.innerHTML = `<div class="opt-empty">Nenhum grupo de opções. Este produto é vendido sem variações.</div>`;
      return;
    }
    state.groups.forEach((group, gi) => els.optGroups.appendChild(groupCard(group, gi)));
  };

  function groupCard(group, gi) {
    const wrapper = elt("div", "opt-group");
    const head = elt("div", "opt-group-head");
    head.innerHTML = `<i class="bi bi-grip-vertical drag"></i>`;
    const name = document.createElement("input");
    name.className = "group-name";
    name.value = group.name;
    name.placeholder = "Nome do grupo (ex.: Idioma)";
    name.addEventListener("input", () => (group.name = name.value));
    const remove = iconButton("opt-group-remove", "bi-trash", () => {
      state.groups.splice(gi, 1);
      renderGroups();
    });
    head.append(name, remove);

    const values = elt("div", "opt-values");
    group.values.forEach((value, vi) => values.appendChild(valueRow(group, value, vi)));
    const addValue = document.createElement("button");
    addValue.type = "button";
    addValue.className = "add-inline";
    addValue.innerHTML = `<i class="bi bi-plus-circle"></i> Adicionar valor`;
    addValue.addEventListener("click", () => {
      group.values.push({ name: "", weight: 0 });
      renderGroups();
    });
    values.appendChild(addValue);

    wrapper.append(head, values);
    return wrapper;
  }

  function valueRow(group, value, vi) {
    const row = elt("div", "opt-value-row");
    row.innerHTML = `<i class="bi bi-grip-vertical drag"></i>`;
    const name = document.createElement("input");
    name.className = "v-name";
    name.value = value.name;
    name.placeholder = "Valor (ex.: Português BR)";
    name.addEventListener("input", () => (value.name = name.value));
    const weight = elt("div", "v-weight");
    weight.innerHTML = `<span class="u">+g</span>`;
    const weightInput = numberInput(value.weight, "Ajuste de peso (g)");
    weightInput.addEventListener("input", () => (value.weight = parseInt(weightInput.value || "0", 10)));
    weight.insertBefore(weightInput, weight.firstChild);
    const remove = iconButton("v-remove", "bi-x-lg", () => {
      group.values.splice(vi, 1);
      renderGroups();
    });
    row.append(name, weight, remove);
    return row;
  }

  const renderTags = () => {
    els.tagEditor.replaceChildren();
    state.tags.forEach((tag, index) => {
      const chip = elt("span", "tagchip");
      chip.innerHTML = `#${tag}<button class="x" type="button" title="Remover"><i class="bi bi-x"></i></button>`;
      chip.querySelector(".x").addEventListener("click", () => {
        state.tags.splice(index, 1);
        renderTags();
      });
      els.tagEditor.appendChild(chip);
    });
    const add = document.createElement("button");
    add.type = "button";
    add.className = "tag-add";
    add.innerHTML = `<i class="bi bi-plus"></i> Tag`;
    add.addEventListener("click", promptTag);
    els.tagEditor.appendChild(add);
  };

  function promptTag() {
    const choice = window.prompt("Digite o nome da tag:");
    if (choice == null) return;
    const tag = slugify(choice);
    if (tag && !state.tags.includes(tag)) {
      state.tags.push(tag);
      renderTags();
    }
  }

  const gotmValues = () => ({
    enabled: els.gotmToggle.checked,
    year: parseInt(els.gotmYear.value, 10),
    month: parseInt(els.gotmMonth.value, 10),
    position: parseInt(els.gotmPos.value || "0", 10),
    blurb: els.gotmBlurb.value
  });

  const syncGotm = () => {
    const on = els.gotmToggle.checked;
    els.gotmPanel.hidden = !on;
    els.gotmCard.classList.toggle("on", on);
    els.gotmBadge.innerHTML = `<i class="bi bi-calendar-event"></i> ${MONTHS[els.gotmMonth.value - 1]} · ${els.gotmYear.value}`;
    updateBrindeWeight();
  };

  const syncCustomOrder = () => {
    els.coBody.hidden = !els.customOrder.checked;
  };

  const syncCoPreview = () => {
    els.coFields.forEach(({ input, echo }) => {
      if (echo) echo.textContent = input.value.trim() || input.placeholder;
    });
  };

  const renderBrindes = () => {
    els.brindeList.replaceChildren();
    if (!state.brindes.length) {
      els.brindeList.innerHTML = `<div class="brinde-empty">Nenhum brinde ainda. Adicione os itens que acompanham esta edição.</div>`;
      updateBrindeWeight();
      return;
    }
    state.brindes.forEach((brinde, index) => els.brindeList.appendChild(brindeCard(brinde, index)));
    updateBrindeWeight();
  };

  function brindeCard(brinde, index) {
    const card = elt("div", "brinde-card");
    card.draggable = true;
    card.dataset.i = index;
    const head = elt("div", "brinde-head");
    head.innerHTML = `<i class="bi bi-grip-vertical drag"></i><span class="b-index">Brinde ${index + 1}</span>` +
      `<button class="b-remove" type="button" title="Remover"><i class="bi bi-trash"></i></button>`;
    head.querySelector(".b-remove").addEventListener("click", () => {
      removeBrindeFile(brinde);
      state.brindes.splice(index, 1);
      renderBrindes();
    });

    const inner = elt("div", "brinde-inner");
    const photo = elt("div", "brinde-photo" + (imageUrl(brinde) ? "" : " is-empty"));
    if (imageUrl(brinde)) photo.style.backgroundImage = `url("${imageUrl(brinde)}")`;
    photo.innerHTML = imageUrl(brinde) ? "" : `<div class="ph-in"><i class="bi bi-image"></i>Imagem<br>(obrigatória)</div><span class="req-dot"></span>`;
    photo.addEventListener("click", () => pickBrinde(brinde, renderBrindes));

    const fields = elt("div", "brinde-fields");
    const rowTop = elt("div", "brinde-row");
    rowTop.append(
      brindeInput("text", brinde.caption, "Legenda (ex.: Pôster)", (v) => (brinde.caption = v)),
      wrapEl(brindeInput("text", brinde.kind, "Tipo (ex.: Colecionável)", (v) => (brinde.kind = v)))
    );
    const desc = document.createElement("textarea");
    desc.className = "bi-inp";
    desc.rows = 2;
    desc.value = brinde.description || "";
    desc.placeholder = "Descrição do brinde…";
    desc.addEventListener("input", () => (brinde.description = desc.value));

    const weightWrap = elt("div", "bi-weight");
    weightWrap.innerHTML = `<span class="u">g</span>`;
    const weightInput = numberInput(brinde.weight, "Peso");
    weightInput.className = "bi-inp";
    weightInput.placeholder = "Peso";
    weightInput.addEventListener("input", () => {
      brinde.weight = parseInt(weightInput.value || "0", 10);
      updateBrindeWeight();
    });
    weightWrap.insertBefore(weightInput, weightWrap.firstChild);
    const weightLabel = document.createElement("div");
    weightLabel.innerHTML = `<span class="mini-label">Peso do brinde</span>`;
    weightLabel.appendChild(weightWrap);

    fields.append(rowTop, desc, weightLabel);
    inner.append(photo, fields);
    card.append(head, inner);
    attachDrag(card, state.brindes, renderBrindes);
    return card;
  }

  const updateBrindeWeight = () => {
    els.brindeWeight.textContent = `${brindeWeight(state.brindes)} g`;
  };

  const addBrinde = () => {
    state.brindes.push({ id: null, key: nextKey("b"), url: null, preview: null, caption: "", kind: "", description: "", weight: 0 });
    renderBrindes();
  };

  const pickBrinde = (brinde, rerender) => selectFile(els.brindeFiles, brinde, `product[brinde_files][${brinde.key}]`, rerender);
  const removeBrindeFile = (brinde) => dropFile(els.brindeFiles, brinde.key);

  const updateSlugEcho = () => {
    els.slugEcho.textContent = els.slug.value || slugify(els.name.value) || "—";
  };

  els.name.addEventListener("input", () => {
    if (!els.slugTouched) els.slug.value = slugify(els.name.value);
    updateSlugEcho();
  });
  els.slug.addEventListener("input", () => {
    els.slugTouched = true;
    updateSlugEcho();
  });
  els.price.addEventListener("blur", () => (els.price.value = formatPrice(els.price.value)));
  els.published.addEventListener("change", () => {
    els.pubTitle.textContent = els.published.checked ? "Publicado" : "Rascunho";
  });
  els.weightRestore.addEventListener("click", () => (els.weight.value = DEFAULT_WEIGHT));

  els.addGroup.addEventListener("click", () => {
    state.groups.push({ name: "", values: [{ name: "", weight: 0 }] });
    renderGroups();
  });
  els.addBrinde.addEventListener("click", addBrinde);

  els.gotmToggle.addEventListener("change", () => {
    syncGotm();
    if (els.gotmToggle.checked) {
      if (!state.brindes.length) addBrinde();
      toast("ok", MSG.gotmOn);
    }
  });
  els.gotmMonth.addEventListener("change", syncGotm);
  els.gotmYear.addEventListener("change", syncGotm);

  els.customOrder.addEventListener("change", () => {
    syncCustomOrder();
    if (els.customOrder.checked) toast("ok", MSG.customOrderOn);
  });
  els.coFields.forEach(({ input }) => input.addEventListener("input", syncCoPreview));
  els.coRestore.addEventListener("click", () => {
    els.coFields.forEach(({ input }) => (input.value = ""));
    syncCoPreview();
    toast("ok", MSG.customOrderRestored);
  });

  form.addEventListener("submit", (event) => {
    const error = validate(state, { name: els.name.value, weight: parseInt(els.weight.value, 10), gotmEnabled: els.gotmToggle.checked });
    if (error) {
      event.preventDefault();
      toast("warn", MSG[error]);
      return;
    }
    els.graph.value = JSON.stringify(serialize(state, gotmValues()));
  });

  els.menuToggle?.addEventListener("click", () => els.sidebar?.classList.toggle("show"));

  applyGotmState(els, graph.gotm || {});
  els.price.value = formatPrice(els.price.value);
  updateSlugEcho();
  renderPhotos();
  renderGroups();
  renderTags();
  renderBrindes();
  syncGotm();
  syncCustomOrder();
  syncCoPreview();

  return { state, serialize: () => serialize(state, gotmValues()) };
}

function collectElements(root) {
  const pick = (id) => root.querySelector(`#${id}`);
  return {
    photoGrid: pick("photo-grid"), photoCount: pick("photo-count"), photoFiles: pick("photo-files"),
    optGroups: pick("opt-groups"), addGroup: pick("add-group"),
    tagEditor: pick("tag-editor"),
    brindeList: pick("brinde-list"), brindeFiles: pick("brinde-files"), brindeWeight: pick("brinde-weight"), addBrinde: pick("add-brinde"),
    gotmToggle: pick("f-gotm"), gotmPanel: pick("gotm-panel"), gotmCard: pick("gotm-card"),
    gotmMonth: pick("f-gotm-month"), gotmYear: pick("f-gotm-year"), gotmPos: pick("f-gotm-pos"), gotmBlurb: pick("f-blurb"), gotmBadge: pick("gotm-edition-badge"),
    name: pick("f-name"), slug: pick("f-slug"), slugEcho: pick("slug-echo"),
    price: pick("f-price"), weight: pick("f-weight"), weightRestore: pick("weight-restore"),
    published: pick("f-published"), pubTitle: pick("pub-title"),
    customOrder: pick("f-custom-order"), coBody: pick("co-body"), coRestore: pick("co-restore"),
    coFields: CO_FIELDS.map(({ input, echo }) => ({ input: pick(input), echo: echo && pick(echo) })),
    graph: pick("f-graph"),
    menuToggle: pick("menu-toggle"), sidebar: root.querySelector("[data-sidebar]"),
    slugTouched: false
  };
}

function applyGotmState(els, gotm) {
  els.gotmToggle.checked = Boolean(gotm.enabled);
  if (gotm.month) els.gotmMonth.value = gotm.month;
  if (gotm.year) els.gotmYear.value = gotm.year;
  els.gotmPos.value = gotm.position || 0;
  els.gotmBlurb.value = gotm.blurb || "";
}

export function formatPrice(value) {
  const raw = String(value).replace(/\./g, "").replace(",", ".");
  const number = parseFloat(raw);
  if (Number.isNaN(number)) return value;
  return number.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function imageUrl(item) {
  return item.preview || item.url;
}

function elt(tag, className) {
  const node = document.createElement(tag);
  node.className = className;
  return node;
}

function wrapEl(child) {
  const wrapper = document.createElement("div");
  wrapper.appendChild(child);
  return wrapper;
}

function iconButton(className, icon, onClick) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = className;
  button.innerHTML = `<i class="bi ${icon}"></i>`;
  button.addEventListener("click", onClick);
  return button;
}

function numberInput(value, title) {
  const input = document.createElement("input");
  input.type = "number";
  input.min = "0";
  input.value = value;
  input.title = title;
  return input;
}

function brindeInput(type, value, placeholder, onInput) {
  const input = document.createElement("input");
  input.type = type;
  input.className = "bi-inp";
  input.value = value || "";
  input.placeholder = placeholder;
  input.addEventListener("input", () => onInput(input.value));
  return input;
}

function pushToast(root, kind, html) {
  const wrap = root.querySelector("#toasts");
  const toast = document.createElement("div");
  toast.className = "toast " + (kind === "warn" ? "toast-warn" : "toast-ok");
  toast.innerHTML = `<i class="bi ${kind === "warn" ? "bi-exclamation-circle-fill" : "bi-check-circle-fill"}"></i><div class="tx">${html}</div>`;
  wrap.appendChild(toast);
  setTimeout(() => toast.remove(), 3600);
  return toast;
}

export function applyPickedFile(item, url, rerender) {
  item.preview = url;
  rerender();
}

/* v8 ignore start */
function ensureFileInput(container, key, name, onPicked) {
  let input = container.querySelector(`input[data-key="${key}"]`);
  if (input) return input;
  input = document.createElement("input");
  input.type = "file";
  input.name = name;
  input.dataset.key = key;
  input.className = "slot-file";
  input.accept = "image/png,image/jpeg,image/webp,image/avif";
  input.addEventListener("change", () => onFileChange(input, onPicked));
  container.appendChild(input);
  return input;
}

function dropFile(container, key) {
  const input = container.querySelector(`input[data-key="${key}"]`);
  if (input) input.remove();
}

function selectFile(container, item, name, rerender) {
  const input = ensureFileInput(container, item.key, name, (url) => applyPickedFile(item, url, rerender));
  input.click();
}

function onFileChange(input, onPicked) {
  const file = input.files && input.files[0];
  if (file) onPicked(URL.createObjectURL(file));
}

let dragCtx = null;
function attachDrag(card, list, rerender) {
  card.addEventListener("dragstart", () => {
    dragCtx = { list, from: Number(card.dataset.i) };
    card.classList.add("dragging");
  });
  card.addEventListener("dragend", () => {
    card.classList.remove("dragging");
    dragCtx = null;
    document.querySelectorAll(".drop-target").forEach((el) => el.classList.remove("drop-target"));
  });
  card.addEventListener("dragover", (event) => {
    if (dragCtx && dragCtx.list === list) {
      event.preventDefault();
      card.classList.add("drop-target");
    }
  });
  card.addEventListener("dragleave", () => card.classList.remove("drop-target"));
  card.addEventListener("drop", (event) => {
    event.preventDefault();
    if (!dragCtx || dragCtx.list !== list) return;
    const to = Number(card.dataset.i);
    if (dragCtx.from === to) return;
    const reordered = moveItem(list, dragCtx.from, to);
    list.splice(0, list.length, ...reordered);
    rerender();
  });
}

if (typeof document !== "undefined") {
  initEditor(document);
}
/* v8 ignore stop */
