"""Conversión de workflow UI -> formato API de ComfyUI (implementación propia).

Investigación previa (2026-10-15, WebSearch): no hay conversor servidor oficial en ComfyUI.
Lo que existe: SethRobinson/comfyui-workflow-to-api-converter-endpoint (custom node que
expone /workflow/convert; requiere instalarlo en ComfyUI), ComfyScript (Chaoses-Ib) y
comfy-commander (este último depende del custom node anterior). Ninguno es un conversor
Python offline y mantenido que se pueda fijar como dependencia, así que se implementa aquí
usando GET /object_info.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

FRONTEND_ONLY = {
    "Note", "MarkdownNote", "Label (rgthree)", "Fast Groups Muter (rgthree)",
    "Fast Groups Bypasser (rgthree)", "Fast Muter (rgthree)", "Fast Bypasser (rgthree)",
    "Fast Actions Button (rgthree)", "Bookmark (rgthree)",
}
VIRTUAL = {"Reroute", "PrimitiveNode", "SetNode", "GetNode"}
CONTROL_VALUES = {"fixed", "increment", "decrement", "randomize"}
SEED_NAMES = {"seed", "noise_seed"}
WIDGET_TYPES = {"INT", "FLOAT", "STRING", "BOOLEAN", "COMBO"}
UPLOAD_KEYS = ("image_upload", "video_upload", "audio_upload")
MAX_DEPTH = 300


class ConversionError(Exception):
    pass


@dataclass(frozen=True)
class Ref:
    node: str
    slot: int


@dataclass(frozen=True)
class Val:
    value: Any


def _link_tuple(l: Any) -> tuple:
    """Enlace UI (lista) o de subgrafo (dict) -> (id, origin_id, origin_slot, target_id, target_slot)."""
    if isinstance(l, dict):
        return (l["id"], l["origin_id"], l["origin_slot"], l["target_id"], l["target_slot"])
    return (l[0], l[1], l[2], l[3], l[4])


class Scope:
    def __init__(self, nodes: list, links: list, prefix: str = "", sg: dict | None = None,
                 parent: "tuple[Scope, dict] | None" = None):
        self.nodes = {n["id"]: n for n in nodes}
        self.links = {}
        for l in links or []:
            t = _link_tuple(l)
            self.links[t[0]] = t
        self.prefix = prefix
        self.sg = sg
        self.parent = parent
        self.in_id = (sg.get("inputNode") or {}).get("id", -10) if sg else None
        self.out_id = (sg.get("outputNode") or {}).get("id", -20) if sg else None


def _types_match(a: Any, b: Any) -> bool:
    return a == b or a == "*" or b == "*" or a is None or b is None


def _spec_parts(spec: Any) -> tuple[Any, dict]:
    t = spec[0] if isinstance(spec, (list, tuple)) and spec else spec
    o = spec[1] if isinstance(spec, (list, tuple)) and len(spec) > 1 and isinstance(spec[1], dict) else {}
    return t, o


def _is_widget(spec: Any) -> bool:
    t, o = _spec_parts(spec)
    if o.get("forceInput"):
        return False
    return isinstance(t, list) or t in WIDGET_TYPES


def _ordered_inputs(info: dict) -> list[tuple[str, Any]]:
    inp = info.get("input") or {}
    order = info.get("input_order") or {}
    out: list[tuple[str, Any]] = []
    for sect in ("required", "optional"):
        specs = inp.get(sect) or {}
        names = order.get(sect) or list(specs.keys())
        for n in names:
            if n in specs:
                out.append((n, specs[n]))
    return out


class Converter:
    def __init__(self, wf: dict, object_info: dict):
        self.oi = object_info
        self.sgs = {sg["id"]: sg for sg in (wf.get("definitions") or {}).get("subgraphs", []) or []}
        self.root = Scope(wf.get("nodes", []), wf.get("links", []))
        self.api: dict[str, dict] = {}
        self.warnings: list[str] = []
        self._inner: dict[tuple, Scope] = {}

    # ---- navegación de enlaces -------------------------------------------------
    def _inner_scope(self, scope: Scope, inst: dict) -> Scope:
        key = (id(scope), inst["id"])
        if key not in self._inner:
            sg = self.sgs[inst["type"]]
            self._inner[key] = Scope(sg.get("nodes", []), sg.get("links", []),
                                     prefix=f"{scope.prefix}{inst['id']}:", sg=sg, parent=(scope, inst))
        return self._inner[key]

    def _follow_input(self, scope: Scope, node: dict, entry: dict | None, depth: int):
        if not entry or entry.get("link") is None:
            return None
        lk = scope.links.get(entry["link"])
        if lk is None:
            raise ConversionError(f"nodo {node['id']} ({node.get('type')}): enlace {entry['link']} inexistente")
        return self.resolve(scope, lk[1], lk[2], depth + 1)

    def resolve(self, scope: Scope, nid: Any, slot: int, depth: int = 0):
        """Resuelve la salida (nid, slot) a Ref (nodo real) / Val (literal) / None (nada)."""
        if depth > MAX_DEPTH:
            raise ConversionError(f"ciclo o cadena demasiado larga cerca del nodo {nid}")
        if scope.sg is not None and nid == scope.in_id:
            return self._subgraph_input(scope, slot, depth)
        node = scope.nodes.get(nid)
        if node is None:
            raise ConversionError(f"enlace a nodo inexistente {scope.prefix}{nid}")
        t = node.get("type")
        mode = node.get("mode", 0)
        if t in FRONTEND_ONLY or mode == 2:
            return None
        if mode == 4:
            return self._bypass(scope, node, slot, depth)
        if t == "Reroute":
            ins = node.get("inputs") or []
            return self._follow_input(scope, node, ins[0] if ins else None, depth)
        if t == "PrimitiveNode":
            wv = node.get("widgets_values") or []
            return Val(wv[0]) if wv else None
        if t == "GetNode":
            return self._get_node(scope, node, depth)
        if t == "SetNode":
            ins = node.get("inputs") or []
            return self._follow_input(scope, node, ins[0] if ins else None, depth)
        if t in self.sgs:
            return self._subgraph_output(scope, node, slot, depth)
        return Ref(f"{scope.prefix}{nid}", slot)

    def _get_node(self, scope: Scope, node: dict, depth: int):
        name = (node.get("widgets_values") or [None])[0]
        for n in scope.nodes.values():
            if n.get("type") == "SetNode" and (n.get("widgets_values") or [None])[0] == name and n.get("mode", 0) != 2:
                return self.resolve(scope, n["id"], 0, depth + 1)
        raise ConversionError(f"nodo {node['id']} (GetNode '{name}'): no hay SetNode con ese nombre")

    def _bypass(self, scope: Scope, node: dict, slot: int, depth: int):
        outs = node.get("outputs") or []
        otype = outs[slot].get("type") if slot < len(outs) else None
        ins = node.get("inputs") or []
        pick = None
        if slot < len(ins) and _types_match(ins[slot].get("type"), otype):
            pick = ins[slot]
        else:
            for e in ins:
                if e.get("link") is not None and _types_match(e.get("type"), otype):
                    pick = e
                    break
        return self._follow_input(scope, node, pick, depth)

    def _subgraph_input(self, scope: Scope, slot: int, depth: int):
        pscope, inst = scope.parent
        sg_in = scope.sg.get("inputs") or []
        if slot >= len(sg_in):
            return None
        name = sg_in[slot].get("name")
        entry = next((e for e in inst.get("inputs", []) if e.get("name") == name), None)
        return self._follow_input(pscope, inst, entry, depth)

    def _subgraph_output(self, scope: Scope, inst: dict, slot: int, depth: int):
        inner = self._inner_scope(scope, inst)
        for lk in inner.links.values():
            if lk[3] == inner.out_id and lk[4] == slot:
                return self.resolve(inner, lk[1], lk[2], depth + 1)
        return None

    # ---- emisión --------------------------------------------------------------
    def run(self) -> dict:
        self._emit_scope(self.root)
        return self.api

    def _emit_scope(self, scope: Scope) -> None:
        for node in scope.nodes.values():
            t = node.get("type")
            if node.get("mode", 0) in (2, 4) or t in FRONTEND_ONLY or t in VIRTUAL:
                continue
            if t in self.sgs:
                self._emit_scope(self._inner_scope(scope, node))
                continue
            self._emit_node(scope, node)

    def _ref(self, r: Any):
        return [r.node, r.slot] if isinstance(r, Ref) else r.value

    def _emit_node(self, scope: Scope, node: dict) -> None:
        t = node["type"]
        nid = f"{scope.prefix}{node['id']}"
        info = self.oi.get(t)
        if info is None:
            raise ConversionError(f"nodo {nid} ({t}): clase ausente en /object_info (custom node no instalado)")
        entries = {e["name"]: e for e in node.get("inputs") or [] if e.get("name")}
        wv = node.get("widgets_values")
        order = _ordered_inputs(info)
        names = {n for n, _ in order}
        inputs: dict[str, Any] = {}
        pos = 0
        for name, spec in order:
            literal: Any = None
            has_literal = False
            if _is_widget(spec):
                if isinstance(wv, list):
                    if pos < len(wv):
                        literal, has_literal = wv[pos], True
                        pos += 1
                        _t, opts = _spec_parts(spec)
                        is_seed_like = (_t == "INT" and name in SEED_NAMES) or opts.get("control_after_generate")
                        if is_seed_like and pos < len(wv) and wv[pos] in CONTROL_VALUES:
                            pos += 1  # pseudo-widget control_after_generate
                        for k in UPLOAD_KEYS:
                            if opts.get(k) and pos < len(wv) and wv[pos] in ("image", "video", "audio"):
                                pos += 1
                elif isinstance(wv, dict) and name in wv:
                    literal, has_literal = wv[name], True
            e = entries.get(name)
            if e is not None and e.get("link") is not None:
                r = self._follow_input(scope, node, e, 0)
                if r is not None:
                    inputs[name] = self._ref(r)
                    continue
                if not has_literal:
                    self.warnings.append(f"nodo {nid} ({t}): entrada '{name}' enlazada a un nodo omitido (mute/frontend); se deja vacía")
                    continue
            if has_literal:
                inputs[name] = literal
        # entradas enlazadas que object_info no declara (nodos dinámicos)
        for name, e in entries.items():
            if name in names or e.get("link") is None:
                continue
            r = self._follow_input(scope, node, e, 0)
            if r is not None:
                inputs[name] = self._ref(r)
        self.api[nid] = {"class_type": t, "inputs": inputs,
                         "_meta": {"title": node.get("title") or info.get("display_name") or t}}


def convert_ui_to_api(wf: dict, object_info: dict) -> tuple[dict, list[str]]:
    """UI -> API. Si ya es API, la devuelve igual."""
    from .workflows import is_api_format
    if is_api_format(wf):
        return wf, []
    if "nodes" not in wf:
        raise ConversionError("el JSON no es ni formato UI (sin 'nodes') ni formato API")
    c = Converter(wf, object_info)
    return c.run(), c.warnings
