import { app } from "../../scripts/app.js";

const STYLES = `
#rb-tools-panel {
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
#rb-tools-panel h3 {
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
.kb-progress-container {
  display: none;
  flex-direction: column;
  gap: 8px;
  margin-top: 6px;
}
.kb-progress-container.visible { display: flex; }
.kb-progress-item { display: flex; flex-direction: column; gap: 3px; }
.kb-progress-header {
  display: flex;
  justify-content: space-between;
  font-size: 10px;
  color: #aaa;
}
.kb-progress-bar-bg {
  width: 100%;
  height: 8px;
  background: #222;
  border-radius: 4px;
  overflow: hidden;
}
.kb-progress-bar-fill {
  height: 100%;
  background: #27ae60;
  border-radius: 4px;
  transition: width 0.8s ease;
  width: 0%;
}
.kb-progress-bar-fill.done { background: #4a90d9; }
.kb-progress-bar-fill.error { background: #e74c3c; }
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
  if (document.getElementById("rb-tools-styles")) return;
  const s = document.createElement("style");
  s.id = "rb-tools-styles";
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
      const res = await fetch(`/rb_tools/output/${jobId}`);
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
        statusEl.textContent = ok ? (successMsg || "✅ Completado") : `❌ Error (código ${data.returncode})`;
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

// Poll especializado para descargas con barras de progreso
async function pollDownloadJob(jobId, progressContainer, statusEl, buttons, successMsg) {
  return new Promise(async (resolve) => {
  progressContainer.innerHTML = "";
  progressContainer.classList.add("visible");
  statusEl.className = "kb-status";
  statusEl.textContent = "⏳ Descargando...";
  buttons.forEach(b => b.disabled = true);

  const bars = {}; // filename -> { item, fill, header }
  let lastLine = 0;

  function getOrCreateBar(filename) {
    if (bars[filename]) return bars[filename];
    const item = document.createElement("div");
    item.className = "kb-progress-item";

    const header = document.createElement("div");
    header.className = "kb-progress-header";
    const nameEl = document.createElement("span");
    nameEl.textContent = filename;
    const infoEl = document.createElement("span");
    infoEl.textContent = "0% — 0 MB/s";
    header.append(nameEl, infoEl);

    const bg = document.createElement("div");
    bg.className = "kb-progress-bar-bg";
    const fill = document.createElement("div");
    fill.className = "kb-progress-bar-fill";
    bg.appendChild(fill);

    item.append(header, bg);
    progressContainer.appendChild(item);
    bars[filename] = { fill, infoEl };
    return bars[filename];
  }

  while (true) {
    await new Promise(r => setTimeout(r, 600));
    try {
      const res = await fetch(`/rb_tools/output/${jobId}`);
      const data = await res.json();
      const newLines = data.lines.slice(lastLine);
      lastLine = data.lines.length;

      for (const line of newLines) {
        if (line.startsWith("PROGRESS:")) {
          // PROGRESS:filename:pct:speed
          const parts = line.split(":");
          const fname = parts[1];
          const pct   = Math.min(100, Math.max(0, parseInt(parts[2]) || 0));
          const speed = parseFloat(parts[3]) || 0;
          const bar = getOrCreateBar(fname);
          bar.fill.style.width = pct + "%";
          bar.infoEl.textContent = `${pct}% — ${speed} MB/s`;
        } else if (line.includes("✅")) {
          // Archivo completado
          const fname = line.match(/✅ (.+?) —/)?.[1];
          if (fname && bars[fname]) {
            bars[fname].fill.style.width = "100%";
            bars[fname].fill.classList.add("done");
            bars[fname].infoEl.textContent = line.replace("  ✅ ", "");
          } else {
            // Mensaje general — mostrar como texto pequeño
            const txt = document.createElement("div");
            txt.style.cssText = "font-size:10px;color:#7fc97f;margin-top:2px;";
            txt.textContent = line;
            progressContainer.appendChild(txt);
          }
        } else if (line.includes("❌")) {
          const txt = document.createElement("div");
          txt.style.cssText = "font-size:10px;color:#e74c3c;margin-top:2px;";
          txt.textContent = line;
          progressContainer.appendChild(txt);
        } else if (line.trim() && !line.startsWith("  ✓")) {
          // Info general (pack name, etc)
          const txt = document.createElement("div");
          txt.style.cssText = "font-size:10px;color:#aaa;margin-top:4px;";
          txt.textContent = line;
          progressContainer.appendChild(txt);
        }
        progressContainer.scrollTop = progressContainer.scrollHeight;
      }

      if (data.done) {
        // Marcar todas las barras incompletas como done
        Object.values(bars).forEach(b => {
          if (parseFloat(b.fill.style.width) < 100) {
            b.fill.style.width = "100%";
            b.fill.classList.add("done");
          }
        });
        const ok = data.returncode === 0;
        statusEl.className = ok ? "kb-status ok" : "kb-status err";
        statusEl.textContent = ok ? (successMsg || "✅ Completado") : `❌ Error (código ${data.returncode})`;
        buttons.forEach(b => b.disabled = false);
        resolve();
        break;
      }
    } catch(e) {
      statusEl.className = "kb-status err";
      statusEl.textContent = "❌ Error de comunicación";
      buttons.forEach(b => b.disabled = false);
      resolve();
      break;
    }
  }
  }); // end Promise
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
  panel.id = "rb-tools-panel";

  const title = document.createElement("h3");
  title.textContent = "RB Tools";
  panel.appendChild(title);

  // ============================================================
  // SALVAR TODO
  // ============================================================
  const saveSection = document.createElement("div");
  saveSection.className = "kb-section-save";
  const saveLabel = document.createElement("label");
  saveLabel.textContent = "Workflows + Loras + Input → R2";
  const saveBtn = document.createElement("button");
  saveBtn.className = "kb-btn kb-btn-save";
  saveBtn.textContent = "💾 SALVAR TODO";
  const saveOutput = document.createElement("div");
  saveOutput.className = "kb-output";
  const saveStatus = document.createElement("div");
  saveStatus.className = "kb-status";
  saveBtn.addEventListener("click", () => {
    startJob("/rb_tools/save_all", {}, saveOutput, saveStatus, [saveBtn], "✅ Todo salvado — sesión segura 🎉");
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
  let packData = [];
  fetch("/rb_tools/models_list")
    .then(r => r.json())
    .then(data => {
      modelList.innerHTML = "";
      if (!data.packs || data.packs.length === 0) {
        const empty = document.createElement("div");
        empty.className = "kb-model-empty";
        empty.textContent = data.error || "No hay packs en la lista.";
        modelList.appendChild(empty);
        return;
      }
      packData = data.packs;
      data.packs.forEach(pack => {
        const item = document.createElement("label");
        item.className = "kb-model-item";
        const cb = document.createElement("input");
        cb.type = "checkbox";
        cb.dataset.packName = pack.name;
        const span = document.createElement("span");
        span.textContent = `${pack.name} (${pack.files.length} archivos)`;
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

  const cancelBtn = document.createElement("button");
  cancelBtn.className = "kb-btn kb-btn-neutral";
  cancelBtn.textContent = "❌ Cancelar";
  cancelBtn.style.display = "none";

  dlBtnRow.append(selectAllBtn, downloadBtn, cancelBtn);

  cancelBtn.addEventListener("click", async () => {
    cancelBtn.disabled = true;
    cancelBtn.textContent = "⏳ Cancelando...";
    try {
      const res = await fetch("/rb_tools/cancel_download", { method: "POST" });
      const data = await res.json();
      dlStatus.className = "kb-status err";
      dlStatus.textContent = `🛑 Cancelado — ${data.cleaned || 0} archivos eliminados.`;
    } catch(e) {
      dlStatus.className = "kb-status err";
      dlStatus.textContent = "❌ Error al cancelar";
    }
    cancelBtn.style.display = "none";
    cancelBtn.textContent = "❌ Cancelar";
    cancelBtn.disabled = false;
    downloadBtn.disabled = false;
    selectAllBtn.disabled = false;
  });

  const dlProgressContainer = document.createElement("div");
  dlProgressContainer.className = "kb-progress-container";
  dlProgressContainer.style.maxHeight = "250px";
  dlProgressContainer.style.overflowY = "auto";
  const dlStatus = document.createElement("div");
  dlStatus.className = "kb-status";

  downloadBtn.addEventListener("click", () => {
    const checked = [...modelList.querySelectorAll("input[type=checkbox]:checked")];
    if (checked.length === 0) {
      dlStatus.className = "kb-status err";
      dlStatus.textContent = "❌ Selecciona al menos un pack.";
      return;
    }
    const packs = checked.map(cb => cb.dataset.packName);
    // Iniciar job
    fetch("/rb_tools/download_models", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ packs })
    })
    .then(r => r.json())
    .then(data => {
      if (data.job_id) {
        cancelBtn.style.display = "";
        pollDownloadJob(data.job_id, dlProgressContainer, dlStatus, [downloadBtn, selectAllBtn], "✅ Modelos descargados.")
          .finally(() => { cancelBtn.style.display = "none"; });
      } else {
        dlStatus.className = "kb-status err";
        dlStatus.textContent = "❌ No se pudo iniciar";
      }
    })
    .catch(e => {
      dlStatus.className = "kb-status err";
      dlStatus.textContent = `❌ ${e.message}`;
    });
  });

  dlSection.append(dlLabel, modelList, dlBtnRow, dlStatus, dlProgressContainer);

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
    startJob("/rb_tools/sync_input", { mode: "download" }, inputOutput, inputStatus, inputBtns, "✅ Input descargado.")
  );
  inputUlBtn.addEventListener("click", () =>
    startJob("/rb_tools/sync_input", { mode: "upload" }, inputOutput, inputStatus, inputBtns, "✅ Input subido.")
  );

  inputSection.append(inputLabel, inputBtnRow, inputStatus, inputOutput);

  // ============================================================
  // UPDATE NODES
  // ============================================================
  const nodesSection = document.createElement("div");
  nodesSection.className = "kb-section";
  const nodesLabel = document.createElement("label");
  nodesLabel.textContent = "🧩 Update Nodes → Dockerfile → GitHub";
  const nodesBtn = document.createElement("button");
  nodesBtn.className = "kb-btn kb-btn-primary";
  nodesBtn.textContent = "🧩 Update Nodes";
  nodesBtn.style.width = "100%";
  const nodesOutput = document.createElement("div");
  nodesOutput.className = "kb-output";
  const nodesStatus = document.createElement("div");
  nodesStatus.className = "kb-status";
  nodesBtn.addEventListener("click", () => {
    startJob("/rb_tools/update_nodes", {}, nodesOutput, nodesStatus, [nodesBtn], "✅ Nodes actualizados → build disparado.");
  });
  nodesSection.append(nodesLabel, nodesBtn, nodesStatus, nodesOutput);

  // ============================================================
  // EDITOR DE PACKS
  // ============================================================
  const editorSection = document.createElement("div");
  editorSection.className = "kb-section";
  const editorLabel = document.createElement("label");
  editorLabel.textContent = "✏️ Agregar Pack de Modelos";

  // Form fields
  function makeField(placeholder) {
    const inp = document.createElement("input");
    inp.type = "text";
    inp.placeholder = placeholder;
    inp.style.cssText = "width:100%;padding:5px 6px;background:#0d0d0d;border:1px solid #333;border-radius:4px;color:#ccc;font-size:11px;font-family:monospace;box-sizing:border-box;margin-bottom:4px;";
    return inp;
  }

  const packNameInput = makeField("Nombre del pack (ej: Klein 9B fp8)");
  const modelInput    = makeField("URL modelo (diffusion_model)");
  const clipInput     = makeField("URL text encoder (clip/t5/qwen)");
  const vaeInput      = makeField("URL VAE");

  const addPackBtn = document.createElement("button");
  addPackBtn.className = "kb-btn kb-btn-primary";
  addPackBtn.textContent = "+ Agregar pack";
  addPackBtn.style.width = "100%";
  addPackBtn.style.marginTop = "4px";

  const editorStatus = document.createElement("div");
  editorStatus.className = "kb-status";

  // Inferir destino desde URL
  function inferDest(url, type) {
    const fname = url.split("/").pop().split("?")[0];
    if (type === "model") return `models/diffusion_models/${fname}`;
    if (type === "clip")  return `models/text_encoders/${fname}`;
    if (type === "vae")   return `models/vae/${fname}`;
    return `models/${fname}`;
  }

  addPackBtn.addEventListener("click", async () => {
    const name  = packNameInput.value.trim();
    const model = modelInput.value.trim();
    const clip  = clipInput.value.trim();
    const vae   = vaeInput.value.trim();

    if (!name || !model || !clip || !vae) {
      editorStatus.className = "kb-status err";
      editorStatus.textContent = "❌ Completa todos los campos.";
      return;
    }

    editorStatus.className = "kb-status";
    editorStatus.textContent = "⏳ Cargando lista actual...";

    try {
      // Leer txt actual
      const res = await fetch("/rb_tools/models_txt");
      const data = await res.json();
      if (data.error) throw new Error(data.error);

      // Armar nuevo pack
      const newPack = `\nPACK: ${name}\n${model} ${inferDest(model, "model")}\n${clip} ${inferDest(clip, "clip")}\n${vae} ${inferDest(vae, "vae")}\n`;
      const newContent = (data.content || "").trimEnd() + newPack;

      // Guardar en R2
      const saveRes = await fetch("/rb_tools/save_models_txt", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content: newContent })
      });
      const saveData = await saveRes.json();
      if (!saveData.ok) throw new Error(saveData.error || "Error guardando");

      editorStatus.className = "kb-status ok";
      editorStatus.textContent = `✅ Pack "${name}" agregado. Recarga RB Tools para verlo.`;

      // Limpiar campos
      packNameInput.value = "";
      modelInput.value = "";
      clipInput.value = "";
      vaeInput.value = "";

      // Recargar lista de packs
      modelList.innerHTML = "<div class='kb-model-empty'>Recargando...</div>";
      fetch("/rb_tools/models_list").then(r => r.json()).then(d => {
        modelList.innerHTML = "";
        (d.packs || []).forEach(pack => {
          const item = document.createElement("label");
          item.className = "kb-model-item";
          const cb = document.createElement("input");
          cb.type = "checkbox";
          cb.dataset.packName = pack.name;
          const span = document.createElement("span");
          span.textContent = `${pack.name} (${pack.files.length} archivos)`;
          item.append(cb, span);
          modelList.appendChild(item);
        });
      });

    } catch(e) {
      editorStatus.className = "kb-status err";
      editorStatus.textContent = `❌ ${e.message}`;
    }
  });

  editorSection.append(editorLabel, packNameInput, modelInput, clipInput, vaeInput, addPackBtn, editorStatus);

  panel.append(saveSection, dlSection, inputSection, nodesSection, editorSection);
  return panel;
}

app.registerExtension({
  name: "RBTools.Panel",
  async setup() {
    if (app.extensionManager?.registerSidebarTab) {
      app.extensionManager.registerSidebarTab({
        id: "rb-tools",
        icon: "pi pi-wrench",
        title: "RB Tools",
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
        if (document.getElementById("rb-tools-panel")) return;
        menu.appendChild(buildPanel());
      };
      setTimeout(inject, 2000);
    }
  }
});
