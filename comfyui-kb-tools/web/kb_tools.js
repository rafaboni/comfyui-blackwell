import { app } from "../../scripts/app.js";

const STYLES = `
#kb-tools-panel {
  padding: 12px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  font-family: monospace;
  font-size: 13px;
  color: #ccc;
  height: 100%;
  overflow-y: auto;
  box-sizing: border-box;
}
#kb-tools-panel h3 {
  margin: 0 0 8px 0;
  font-size: 14px;
  color: #fff;
  letter-spacing: 1px;
  text-transform: uppercase;
  border-bottom: 1px solid #333;
  padding-bottom: 6px;
}
.kb-section {
  background: #1a1a1a;
  border: 1px solid #333;
  border-radius: 6px;
  padding: 10px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.kb-section-save {
  background: #1a2a1a;
  border: 2px solid #27ae60;
  border-radius: 6px;
  padding: 10px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.kb-section label {
  color: #aaa;
  font-size: 11px;
}
.kb-btn-row {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
}
.kb-btn {
  flex: 1;
  min-width: 70px;
  padding: 7px 8px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 11px;
  font-weight: bold;
  transition: opacity 0.15s;
}
.kb-btn:hover { opacity: 0.85; }
.kb-btn:disabled { opacity: 0.4; cursor: not-allowed; }
.kb-btn-primary { background: #4a90d9; color: white; }
.kb-btn-success { background: #27ae60; color: white; }
.kb-btn-warning { background: #e67e22; color: white; }
.kb-btn-neutral { background: #555; color: white; }
.kb-btn-save    { background: #27ae60; color: white; font-size: 13px; padding: 10px; width: 100%; }
.kb-output {
  background: #0d0d0d;
  border: 1px solid #222;
  border-radius: 4px;
  padding: 8px;
  font-size: 10px;
  color: #7fc97f;
  max-height: 180px;
  overflow-y: auto;
  white-space: pre-wrap;
  word-break: break-all;
  display: none;
}
.kb-output.visible { display: block; }
.kb-status {
  font-size: 11px;
  color: #888;
  min-height: 16px;
}
.kb-status.ok  { color: #27ae60; font-weight: bold; }
.kb-status.err { color: #e74c3c; }
.kb-model-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
  max-height: 150px;
  overflow-y: auto;
  background: #0d0d0d;
  border: 1px solid #222;
  border-radius: 4px;
  padding: 6px;
}
.kb-model-item {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  color: #bbb;
  cursor: pointer;
}
.kb-model-item input[type=checkbox] {
  cursor: pointer;
}
.kb-model-empty {
  color: #555;
  font-size: 11px;
  font-style: italic;
}
`;

function injectStyles() {
  if (document.getElementById("kb-tools-styles")) return;
  const s = document.createElement("style");
  s.id = "kb-tools-styles";
  s.textContent = STYLES;
  document.head.appendChild(s);
}

async function pollJob(jobId, outputEl, statusEl, buttons, successMsg) {
  outputEl.textContent = "";
  outputEl.classList.add("visible");
  statusEl.className = "kb-status";
  statusEl.textContent = "⏳ Corriendo...";
  buttons.forEach(b => b.disabled = true);
  let lastLine = 0;
  while (true) {
    await new Promise(r => setTimeout(r, 800));
    try {
      const res = await fetch(`/kb_tools/output/${jobId}`);
      const data = await res.json();
      const newLines = data.lines.slice(lastLine);
      if (newLines.length > 0) {
        outputEl.textContent += newLines.join("\n") + "\n";
        outputEl.scrollTop = outputEl.scrollHeight;
        lastLine = data.lines.length;
      }
      if (data.done) {
        const ok = data.returncode === 0;
        statusEl.className = ok ? "kb-status ok" : "kb-status err";
        statusEl.textContent = ok
          ? (successMsg || "✅ Completado")
          : `❌ Error (código ${data.returncode})`;
        buttons.forEach(b => b.disabled = false);
        break;
      }
    } catch(e) {
      statusEl.className = "kb-status err";
      statusEl.textContent = "❌ Error de comunicación";
      buttons.forEach(b => b.disabled = false);
      break;
    }
  }
}

async function startJob(url, body, outputEl, statusEl, buttons, successMsg) {
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body || {})
    });
    const data = await res.json();
    if (data.job_id) {
      await pollJob(data.job_id, outputEl, statusEl, buttons, successMsg);
    } else {
      statusEl.className = "kb-status err";
      statusEl.textContent = "❌ No se pudo iniciar";
    }
  } catch(e) {
    statusEl.className = "kb-status err";
    statusEl.textContent = `❌ ${e.message}`;
  }
}

function buildPanel() {
  injectStyles();
  const panel = document.createElement("div");
  panel.id = "kb-tools-panel";

  const title = document.createElement("h3");
  title.textContent = "KB Tools";
  panel.appendChild(title);

  // ============================================================
  // SALVAR TODO
  // ============================================================
  const saveSection = document.createElement("div");
  saveSection.className = "kb-section-save";
  const saveLabel = document.createElement("label");
  saveLabel.textContent = "Workflows + Loras + Input → R2 | Nodes → GitHub";
  const saveBtn = document.createElement("button");
  saveBtn.className = "kb-btn kb-btn-save";
  saveBtn.textContent = "💾 SALVAR TODO";
  const saveOutput = document.createElement("div");
  saveOutput.className = "kb-output";
  const saveStatus = document.createElement("div");
  saveStatus.className = "kb-status";
  saveBtn.addEventListener("click", () => {
    startJob("/kb_tools/save_all", {}, saveOutput, saveStatus, [saveBtn], "✅ Todo salvado — sesión segura 🎉");
  });
  saveSection.append(saveLabel, saveBtn, saveStatus, saveOutput);

  // ============================================================
  // DESCARGAR MODELOS
  // ============================================================
  const dlSection = document.createElement("div");
  dlSection.className = "kb-section";
  const dlLabel = document.createElement("label");
  dlLabel.textContent = "📥 Descargar Modelos";

  // Lista de checkboxes
  const modelList = document.createElement("div");
  modelList.className = "kb-model-list";
  const loadingEl = document.createElement("div");
  loadingEl.className = "kb-model-empty";
  loadingEl.textContent = "Cargando lista...";
  modelList.appendChild(loadingEl);

  // Cargar lista desde R2
  let modelData = [];
  fetch("/kb_tools/models_list")
    .then(r => r.json())
    .then(data => {
      modelList.innerHTML = "";
      if (!data.models || data.models.length === 0) {
        const empty = document.createElement("div");
        empty.className = "kb-model-empty";
        empty.textContent = data.error || "No hay modelos en la lista.";
        modelList.appendChild(empty);
        return;
      }
      modelData = data.models;
      data.models.forEach(m => {
        const item = document.createElement("label");
        item.className = "kb-model-item";
        const cb = document.createElement("input");
        cb.type = "checkbox";
        cb.dataset.index = m.index;
        const span = document.createElement("span");
        span.textContent = m.name;
        span.title = m.url;
        item.append(cb, span);
        modelList.appendChild(item);
      });
    })
    .catch(() => {
      modelList.innerHTML = "";
      const empty = document.createElement("div");
      empty.className = "kb-model-empty";
      empty.textContent = "Error cargando lista.";
      modelList.appendChild(empty);
    });

  const dlBtnRow = document.createElement("div");
  dlBtnRow.className = "kb-btn-row";

  const selectAllBtn = document.createElement("button");
  selectAllBtn.className = "kb-btn kb-btn-neutral";
  selectAllBtn.textContent = "Sel. todo";
  selectAllBtn.addEventListener("click", () => {
    modelList.querySelectorAll("input[type=checkbox]").forEach(cb => cb.checked = true);
  });

  const downloadBtn = document.createElement("button");
  downloadBtn.className = "kb-btn kb-btn-success";
  downloadBtn.textContent = "⬇ Descargar";

  dlBtnRow.append(selectAllBtn, downloadBtn);

  const dlOutput = document.createElement("div");
  dlOutput.className = "kb-output";
  const dlStatus = document.createElement("div");
  dlStatus.className = "kb-status";

  downloadBtn.addEventListener("click", () => {
    const checked = [...modelList.querySelectorAll("input[type=checkbox]:checked")];
    if (checked.length === 0) {
      dlStatus.className = "kb-status err";
      dlStatus.textContent = "❌ Selecciona al menos un modelo.";
      return;
    }
    const indices = checked.map(cb => parseInt(cb.dataset.index));
    startJob("/kb_tools/download_models", { indices }, dlOutput, dlStatus, [downloadBtn, selectAllBtn], "✅ Modelos descargados.");
  });

  dlSection.append(dlLabel, modelList, dlBtnRow, dlStatus, dlOutput);

  // ============================================================
  // INPUT
  // ============================================================
  const inputSection = document.createElement("div");
  inputSection.className = "kb-section";
  const inputLabel = document.createElement("label");
  inputLabel.textContent = "🖼  Imágenes de Input ↔ R2";
  const inputBtnRow = document.createElement("div");
  inputBtnRow.className = "kb-btn-row";

  const inputDlBtn = document.createElement("button");
  inputDlBtn.className = "kb-btn kb-btn-primary";
  inputDlBtn.textContent = "⬇ Bajar";

  const inputUlBtn = document.createElement("button");
  inputUlBtn.className = "kb-btn kb-btn-warning";
  inputUlBtn.textContent = "⬆ Subir";

  inputBtnRow.append(inputDlBtn, inputUlBtn);
  const inputOutput = document.createElement("div");
  inputOutput.className = "kb-output";
  const inputStatus = document.createElement("div");
  inputStatus.className = "kb-status";
  const inputBtns = [inputDlBtn, inputUlBtn];

  inputDlBtn.addEventListener("click", () =>
    startJob("/kb_tools/sync_input", { mode: "download" }, inputOutput, inputStatus, inputBtns, "✅ Input descargado.")
  );
  inputUlBtn.addEventListener("click", () =>
    startJob("/kb_tools/sync_input", { mode: "upload" }, inputOutput, inputStatus, inputBtns, "✅ Input subido.")
  );

  inputSection.append(inputLabel, inputBtnRow, inputStatus, inputOutput);

  panel.append(saveSection, dlSection, inputSection);
  return panel;
}

app.registerExtension({
  name: "KBTools.Panel",
  async setup() {
    if (app.extensionManager?.registerSidebarTab) {
      app.extensionManager.registerSidebarTab({
        id: "kb-tools",
        icon: "pi pi-wrench",
        title: "KB Tools",
        tooltip: "Salvar sesión y descargar modelos",
        type: "custom",
        render(el) {
          el.appendChild(buildPanel());
        }
      });
    } else {
      const inject = () => {
        const menu = document.querySelector(".comfy-menu");
        if (!menu) { setTimeout(inject, 1000); return; }
        if (document.getElementById("kb-tools-panel")) return;
        menu.appendChild(buildPanel());
      };
      setTimeout(inject, 2000);
    }
  }
});
