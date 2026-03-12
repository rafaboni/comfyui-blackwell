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
.kb-section label {
  color: #aaa;
  font-size: 11px;
  margin-bottom: 2px;
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
.kb-btn-info    { background: #8e44ad; color: white; }
.kb-btn-neutral { background: #555; color: white; }
.kb-output {
  background: #0d0d0d;
  border: 1px solid #222;
  border-radius: 4px;
  padding: 8px;
  font-size: 10px;
  color: #7fc97f;
  max-height: 160px;
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
.kb-status.ok  { color: #27ae60; }
.kb-status.err { color: #e74c3c; }
`;

function injectStyles() {
  if (document.getElementById("kb-tools-styles")) return;
  const s = document.createElement("style");
  s.id = "kb-tools-styles";
  s.textContent = STYLES;
  document.head.appendChild(s);
}

async function pollJob(jobId, outputEl, statusEl, buttons) {
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
        statusEl.className = data.returncode === 0 ? "kb-status ok" : "kb-status err";
        statusEl.textContent = data.returncode === 0 ? "✅ Completado" : `❌ Error (código ${data.returncode})`;
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

async function startJob(url, body, outputEl, statusEl, buttons) {
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body || {})
    });
    const data = await res.json();
    if (data.job_id) {
      await pollJob(data.job_id, outputEl, statusEl, buttons);
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

  // --- Nodes section ---
  const nodesSection = document.createElement("div");
  nodesSection.className = "kb-section";
  const nodesLabel = document.createElement("label");
  nodesLabel.textContent = "🧩 Sync Custom Nodes → Dockerfile → GitHub";
  const nodesBtnRow = document.createElement("div");
  nodesBtnRow.className = "kb-btn-row";
  const updateBtn = document.createElement("button");
  updateBtn.className = "kb-btn kb-btn-primary";
  updateBtn.textContent = "Update Nodes";
  nodesBtnRow.appendChild(updateBtn);
  const nodesOutput = document.createElement("div");
  nodesOutput.className = "kb-output";
  const nodesStatus = document.createElement("div");
  nodesStatus.className = "kb-status";
  updateBtn.addEventListener("click", () => {
    startJob("/kb_tools/update_nodes", {}, nodesOutput, nodesStatus, [updateBtn]);
  });
  nodesSection.append(nodesLabel, nodesBtnRow, nodesStatus, nodesOutput);

  // --- Models section ---
  const modelsSection = document.createElement("div");
  modelsSection.className = "kb-section";
  const modelsLabel = document.createElement("label");
  modelsLabel.textContent = "📦 Sync Modelos ↔ R2";
  const modelsBtnRow = document.createElement("div");
  modelsBtnRow.className = "kb-btn-row";
  const dlBtn   = document.createElement("button");
  dlBtn.className = "kb-btn kb-btn-success";
  dlBtn.textContent = "⬇ Bajar";
  const ulBtn   = document.createElement("button");
  ulBtn.className = "kb-btn kb-btn-warning";
  ulBtn.textContent = "⬆ Subir";
  const bothBtn = document.createElement("button");
  bothBtn.className = "kb-btn kb-btn-info";
  bothBtn.textContent = "⇅ Ambos";
  const dryBtn  = document.createElement("button");
  dryBtn.className = "kb-btn kb-btn-neutral";
  dryBtn.textContent = "👁 Diff";
  modelsBtnRow.append(dlBtn, ulBtn, bothBtn, dryBtn);
  const modelsOutput = document.createElement("div");
  modelsOutput.className = "kb-output";
  const modelsStatus = document.createElement("div");
  modelsStatus.className = "kb-status";
  const allBtns = [dlBtn, ulBtn, bothBtn, dryBtn];
  dlBtn.addEventListener("click",   () => startJob("/kb_tools/sync_models", { mode: "download" }, modelsOutput, modelsStatus, allBtns));
  ulBtn.addEventListener("click",   () => startJob("/kb_tools/sync_models", { mode: "upload"   }, modelsOutput, modelsStatus, allBtns));
  bothBtn.addEventListener("click", () => startJob("/kb_tools/sync_models", { mode: "both"     }, modelsOutput, modelsStatus, allBtns));
  dryBtn.addEventListener("click",  () => startJob("/kb_tools/sync_models", { mode: "dryrun"   }, modelsOutput, modelsStatus, allBtns));
  modelsSection.append(modelsLabel, modelsBtnRow, modelsStatus, modelsOutput);

  panel.append(nodesSection, modelsSection);
  return panel;
}

app.registerExtension({
  name: "KBTools.Panel",
  async setup() {
    if (app.extensionManager?.registerSidebarTab) {
      // ComfyUI 0.16+ nueva API
      app.extensionManager.registerSidebarTab({
        id: "kb-tools",
        icon: "pi pi-wrench",
        title: "KB Tools",
        tooltip: "Sync nodes y modelos",
        type: "custom",
        render(el) {
          el.appendChild(buildPanel());
        }
      });
    } else {
      // Fallback versiones anteriores
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
