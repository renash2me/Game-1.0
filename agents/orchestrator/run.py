#!/usr/bin/env python3
"""Game-master agent — gera agents/state/GAME_STATE.md.

Design robusto para hardware fraco (Qwen3 4B em 4GB de VRAM):
- a ESTRUTURA e os FATOS (contagens, monstros, mapas, fórmulas, commits) são
  renderizados DETERMINISTICAMENTE a partir de `template.md`;
- o modelo (Ollama) faz APENAS o parágrafo de "mudanças recentes" — tarefa
  pequena e confiável. Se o modelo falhar ou voltar vazio, usa um FALLBACK
  determinístico. Resultado: o documento SEMPRE sai válido.

Uso:
  python run.py --no-llm      # não chama o modelo (narrativa de fallback) — bom p/ testar
  python run.py               # gera com o modelo (não commita)
  python run.py --commit      # também commita no branch atual (agents)

Config por env: OLLAMA_HOST (default http://localhost:11434), GM_MODEL (default qwen3:4b).
Sem dependências externas — só Python 3 (+ Ollama quando não for --no-llm).
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DATA_DIR = REPO / "server" / "app" / "data"
STATE = REPO / "agents" / "state" / "GAME_STATE.md"
CHANGELOG = REPO / "agents" / "state" / "CHANGELOG.md"
DEBUG = REPO / "agents" / "state" / "_last_output.md"
TEMPLATE = Path(__file__).parent / "template.md"

OLLAMA = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
MODEL = os.environ.get("GM_MODEL", "qwen3:4b")
CATALOGS = ["items", "cards", "monsters", "maps", "skills", "quests", "classes", "formulas"]


def git(*args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(REPO), *args],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    ).stdout.strip()


def _recent_commits() -> list[str]:
    for ref in ("origin/master", "master", "HEAD"):
        out = git("log", "--oneline", "-12", ref)
        if out:
            return out.splitlines()
    return []


def gather_facts() -> dict:
    facts: dict = {"date": datetime.date.today().isoformat(), "errors": []}
    cat: dict = {}
    for name in CATALOGS:
        try:
            cat[name] = json.loads((DATA_DIR / f"{name}.json").read_text(encoding="utf-8"))
        except Exception as exc:
            facts["errors"].append(f"{name}.json: {exc}")
            cat[name] = []
    facts["counts"] = {k: len(v) for k, v in cat.items()}
    facts["monsters"] = [
        {"id": m.get("id"), "name": m.get("name"), "ai_type": m.get("ai_type")}
        for m in cat["monsters"]
    ]
    facts["maps"] = [{"id": m.get("id"), "name": m.get("name")} for m in cat["maps"]]
    facts["formulas"] = [{"id": f.get("id"), "expr": f.get("expr")} for f in cat["formulas"]]
    facts["recent_commits"] = _recent_commits()
    return facts


def call_ollama(prompt: str, timeout: int = 600) -> str:
    body = json.dumps(
        {
            "model": MODEL,
            "prompt": prompt,
            "stream": False,
            "think": False,  # desliga o raciocínio do Qwen3 (senão ele gasta o orçamento pensando)
            "options": {"temperature": 0.3, "num_ctx": 4096, "num_predict": 1024},
        }
    ).encode()
    req = urllib.request.Request(
        f"{OLLAMA}/api/generate", data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode()).get("response", "")


def strip_think(text: str) -> str:
    return re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()


def llm_narrative(facts: dict) -> str | None:
    """Pede ao modelo um parágrafo curto sobre os commits recentes. Tarefa
    pequena e bem escopada. Retorna None se a saída não for plausível."""
    commits = "\n".join(facts["recent_commits"])
    prompt = (
        "Você é o game-master de um MMORPG chamado Aethermoor. Em 2 a 4 frases "
        "curtas, em português do Brasil, resuma o que estes commits recentes "
        "indicam sobre a evolução do jogo. Seja factual, não invente, não use "
        "listas nem markdown. Responda APENAS com o parágrafo.\n\nCommits:\n"
        f"{commits}"
    )
    try:
        out = strip_think(call_ollama(prompt))
    except Exception as exc:
        print(f"[gm] modelo indisponível ({exc}); usando fallback.", file=sys.stderr)
        return None
    if 40 <= len(out) <= 1500 and "<think>" not in out:
        return out
    print(f"[gm] saída do modelo implausível (len={len(out)}); usando fallback.", file=sys.stderr)
    return None


def fallback_narrative(facts: dict) -> str:
    subs = [c.split(" ", 1)[1] if " " in c else c for c in facts["recent_commits"][:6]]
    if not subs:
        return "Sem commits recentes para resumir."
    return "Resumo automático dos commits recentes: " + "; ".join(subs) + "."


def render(facts: dict, narrative: str) -> str:
    tpl = TEMPLATE.read_text(encoding="utf-8")
    counts = " · ".join(f"{k}: {v}" for k, v in facts["counts"].items())
    monsters = ", ".join(
        f"{m['name']} (`{m['id']}`, {m['ai_type']})" for m in facts["monsters"]
    ) or "—"
    maps = ", ".join(f"{m['name']} (`{m['id']}`)" for m in facts["maps"]) or "—"
    formulas = "\n".join(f"- `{f['id']}` = `{f['expr']}`" for f in facts["formulas"]) or "—"
    commits = "\n".join(f"- {c}" for c in facts["recent_commits"]) or "—"
    return (
        tpl.replace("{{DATE}}", facts["date"])
        .replace("{{COUNTS}}", counts)
        .replace("{{MONSTERS}}", monsters)
        .replace("{{MAPS}}", maps)
        .replace("{{FORMULAS}}", formulas)
        .replace("{{NARRATIVE}}", narrative)
        .replace("{{RECENT_COMMITS}}", commits)
    )


def _commit(paths: list[str], msg: str) -> None:
    subprocess.run(["git", "-C", str(REPO), "add", *paths], check=False)
    subprocess.run(["git", "-C", str(REPO), "commit", "-m", msg], check=False)


def _changelog(msg: str) -> None:
    head = f"## {datetime.date.today().isoformat()} — {msg}\n\n"
    prev = CHANGELOG.read_text(encoding="utf-8") if CHANGELOG.exists() else "# Changelog do braço de agentes\n\n"
    lines = prev.splitlines(keepends=True)
    if lines and lines[0].startswith("#"):
        new = lines[0] + "\n" + head + "".join(lines[1:]).lstrip("\n")
    else:
        new = head + prev
    CHANGELOG.write_text(new, encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description="Game-master agent")
    ap.add_argument("--no-llm", action="store_true", help="não chama o modelo (narrativa de fallback)")
    ap.add_argument("--commit", action="store_true", help="commita o resultado no branch atual")
    args = ap.parse_args()

    facts = gather_facts()
    if facts["errors"]:
        print("SANITY FAIL — algum JSON não parseou:", facts["errors"], file=sys.stderr)
        sys.exit(1)

    narrative = None
    if not args.no_llm:
        print(f"[gm] pedindo o resumo ao {MODEL} em {OLLAMA} ...", file=sys.stderr)
        narrative = llm_narrative(facts)
    used_llm = narrative is not None
    if narrative is None:
        narrative = fallback_narrative(facts)

    DEBUG.write_text(narrative + "\n", encoding="utf-8")
    STATE.write_text(render(facts, narrative).rstrip() + "\n", encoding="utf-8")

    tag = "modelo" if used_llm else "fallback"
    _changelog(f"GAME_STATE.md atualizado (narrativa: {tag})")
    print(f"[gm] GAME_STATE.md atualizado (narrativa via {tag}).", file=sys.stderr)

    if args.commit:
        _commit(
            ["agents/state/GAME_STATE.md", "agents/state/CHANGELOG.md", "agents/state/_last_output.md"],
            "chore(agents): game-master atualiza GAME_STATE",
        )
        print("[gm] commitado no branch atual.", file=sys.stderr)


if __name__ == "__main__":
    main()
