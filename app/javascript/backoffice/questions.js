import { createTable } from "backoffice/table";
import { bindFilters, syncFilters } from "backoffice/filters";
import { bindGlobalSearch, initShell } from "backoffice/shell";

export function appendCanned(current, snippet) {
  const trimmed = current.trim();
  return trimmed ? `${trimmed}\n\n${snippet}` : snippet;
}

export function fillTemplate(template, value) {
  return String(template).replace("{n}", String(value));
}

export function bulkBody(event, ids) {
  const body = new URLSearchParams();
  body.set("event", event);
  ids.forEach((id) => body.append("question_ids[]", id));
  return body;
}

export function confirmMessage(button, count) {
  const template = count === 1 ? button.dataset.confirmOne : button.dataset.confirmOther;
  return fillTemplate(template, count);
}

export function csrfHeader(doc) {
  const token = doc.querySelector('meta[name="csrf-token"]');
  return { "X-CSRF-Token": token ? token.content : "" };
}

export function initQuestions(root, doc = document) {
  const $ = (sel) => root.querySelector(sel);
  const table = createTable(root, {
    onRender: () => { syncSelection(); syncDrawer(); },
    onRestore: (params) => syncFilters(root, params)
  });
  initShell(root);
  bindFilters(root, table);
  bindGlobalSearch(root, $("#q-q"));

  const selected = new Set();
  const drawer = $("#drawer");
  const scrim = $("#scrim");
  const bulkbar = $("#bulkbar");
  const cannedModal = $("#canned-modal");
  const cannedScrim = $("#cscrim");
  const cannedForm = $("#canned-form");
  const toasts = doc.getElementById("toasts");

  function openQuestion(id) {
    return table.set({ pergunta: id, page: table.params.page });
  }

  function closeQuestion() {
    return table.set({ pergunta: null, page: table.params.page });
  }

  function drawerOpen() {
    return Boolean(root.querySelector('[data-part="drawer"] .dw-head'));
  }

  function syncDrawer() {
    const open = drawerOpen();
    drawer.classList.toggle("open", open);
    drawer.setAttribute("aria-hidden", String(!open));
    scrim.classList.toggle("open", open);
    if (!open) closeSpam();
  }

  function spamModal() {
    return $("#spam-modal");
  }

  function toggleSpam(open) {
    const modal = spamModal();
    if (!modal) return;
    modal.classList.toggle("open", open);
    modal.setAttribute("aria-hidden", String(!open));
    $("#mscrim").classList.toggle("open", open);
  }

  function closeSpam() {
    toggleSpam(false);
  }

  function spamOpen() {
    const modal = spamModal();
    return Boolean(modal && modal.classList.contains("open"));
  }

  function resetCannedForm() {
    cannedForm.setAttribute("action", cannedForm.dataset.createUrl);
    $("#canned-method").value = "post";
    $("#canned-label").value = "";
    $("#canned-body").value = "";
    const title = $("[data-canned-form-title]");
    title.textContent = title.dataset.titleNew;
    const submit = $("[data-canned-submit]");
    submit.textContent = submit.dataset.labelAdd;
    $("[data-canned-reset]").hidden = true;
  }

  function editCanned(button) {
    cannedForm.setAttribute("action", button.dataset.cannedEdit);
    $("#canned-method").value = "patch";
    $("#canned-label").value = button.dataset.label;
    $("#canned-body").value = button.dataset.body;
    const title = $("[data-canned-form-title]");
    title.textContent = title.dataset.titleEdit.replace("{label}", button.dataset.label);
    const submit = $("[data-canned-submit]");
    submit.textContent = submit.dataset.labelEdit;
    $("[data-canned-reset]").hidden = false;
    $("#canned-label").focus();
  }

  function openCanned(prefill) {
    resetCannedForm();
    if (prefill) $("#canned-body").value = prefill;
    cannedModal.classList.add("open");
    cannedModal.setAttribute("aria-hidden", "false");
    cannedScrim.classList.add("open");
  }

  function closeCanned() {
    cannedModal.classList.remove("open");
    cannedModal.setAttribute("aria-hidden", "true");
    cannedScrim.classList.remove("open");
    const url = new URL(window.location.href);
    if (url.searchParams.has("respostas")) {
      url.searchParams.delete("respostas");
      window.history.replaceState({}, "", url.pathname + url.search);
    }
  }

  function cannedOpen() {
    return cannedModal.classList.contains("open");
  }

  function answerField() {
    return root.querySelector("[data-answer-body]");
  }

  function syncCounter(field) {
    const counter = root.querySelector("[data-answer-counter]");
    if (counter) counter.textContent = fillTemplate(field.dataset.counterTemplate, field.value.length);
  }

  function syncSelection() {
    const rows = Array.from(root.querySelectorAll("#questions-body tr[data-question]"));
    rows.forEach((row) => {
      const on = selected.has(row.dataset.question);
      row.classList.toggle("sel-row", on);
      const box = row.querySelector("[data-check]");
      box.classList.toggle("on", on);
      box.setAttribute("aria-checked", String(on));
    });

    const selN = rows.filter((row) => selected.has(row.dataset.question)).length;
    const checkall = $("#q-checkall");
    if (checkall) {
      checkall.classList.toggle("on", selN > 0 && selN === rows.length);
      checkall.classList.toggle("ind", selN > 0 && selN < rows.length);
    }

    bulkbar.hidden = selected.size === 0;
    $("#bulk-n").textContent = selected.size;
  }

  function toggleRow(id) {
    if (selected.has(id)) selected.delete(id); else selected.add(id);
    syncSelection();
  }

  function toggleAll() {
    const rows = Array.from(root.querySelectorAll("#questions-body tr[data-question]"));
    const allSel = rows.length > 0 && rows.every((row) => selected.has(row.dataset.question));
    rows.forEach((row) => {
      if (allSel) selected.delete(row.dataset.question); else selected.add(row.dataset.question);
    });
    syncSelection();
  }

  function toast(kind, message) {
    const el = doc.createElement("div");
    el.className = `toast ${kind === "warn" ? "toast-warn" : "toast-ok"}`;
    el.innerHTML = `<i class="bi ${kind === "warn" ? "bi-exclamation-circle-fill" : "bi-check-circle-fill"}"></i><div class="tx"></div>`;
    el.querySelector(".tx").textContent = message;
    toasts.appendChild(el);
    setTimeout(() => el.remove(), 3600);
  }

  async function applyBulk(button) {
    const ids = [ ...selected ];
    const event = button.dataset.bulk;
    if (ids.length === 0) return;
    if (event === "spam" && !window.confirm(confirmMessage(button, ids.length))) return;

    try {
      const response = await fetch(root.dataset.bulkUrl, {
        method: "POST",
        headers: { ...csrfHeader(doc), "Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded" },
        body: bulkBody(event, ids)
      });
      const data = await response.json();
      selected.clear();
      await table.reload({ push: false });
      toast(event === "spam" ? "warn" : "ok", data.message);
    } catch (error) {
      toast("warn", root.dataset.bulkError);
    }
  }

  root.addEventListener("click", (event) => {
    const check = event.target.closest("[data-check]");
    if (check) {
      event.stopPropagation();
      toggleRow(check.dataset.check);
      return;
    }
    if (event.target.closest("#q-checkall")) {
      toggleAll();
      return;
    }
    if (event.target.closest("[data-drawer-close]")) {
      closeQuestion();
      return;
    }
    if (event.target.closest("[data-spam-open]")) {
      toggleSpam(true);
      return;
    }
    if (event.target.closest("[data-spam-close]")) {
      closeSpam();
      return;
    }
    if (event.target.closest("[data-canned-close]")) {
      closeCanned();
      return;
    }
    if (event.target.closest("[data-canned-reset]")) {
      resetCannedForm();
      return;
    }
    const edit = event.target.closest("[data-canned-edit]");
    if (edit) {
      editCanned(edit);
      return;
    }
    if (event.target.closest("[data-canned-save]")) {
      openCanned(answerField().value.trim());
      return;
    }
    if (event.target.closest("[data-canned-open]")) {
      openCanned("");
      return;
    }
    const chip = event.target.closest("[data-canned-body]");
    if (chip) {
      const field = answerField();
      field.value = appendCanned(field.value, chip.dataset.cannedBody);
      syncCounter(field);
      field.focus();
      return;
    }
    const bulk = event.target.closest("[data-bulk]");
    if (bulk) {
      applyBulk(bulk);
      return;
    }
    if (event.target.closest("#bulk-clear")) {
      selected.clear();
      syncSelection();
      return;
    }
    const row = event.target.closest("#questions-body tr[data-question]");
    if (row) openQuestion(row.dataset.question);
  });

  root.addEventListener("input", (event) => {
    const field = event.target.closest("[data-answer-body]");
    if (field) syncCounter(field);
  });

  const onKeydown = (event) => {
    if (event.key !== "Escape") return;
    if (spamOpen()) closeSpam();
    else if (cannedOpen()) closeCanned();
    else if (drawerOpen()) closeQuestion();
  };
  doc.addEventListener("keydown", onKeydown);

  syncDrawer();
  syncSelection();

  return {
    table,
    selected,
    destroy() {
      doc.removeEventListener("keydown", onKeydown);
      table.destroy();
    }
  };
}

/* v8 ignore start */
if (typeof document !== "undefined") {
  const root = document.querySelector('[data-list="questions"]');
  if (root) initQuestions(root);
}
/* v8 ignore stop */
