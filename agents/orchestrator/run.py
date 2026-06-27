#!/usr/bin/env python3
"""Game-master agent — atualiza agents/state/GAME_STATE.md a partir do repositório
e de um modelo local (Ollama).

Projetado para ser robusto com modelos pequenos (Qwen3 4B/8B):
- os FATOS são coletados deterministicamente (contagens, listas, commits);
- o modelo só faz a SÍNTESE em prosa;
- o documento só é sobrescrito se a saída passar num sanity check — senão o
  doc anterior é preservado (não destruímos o bom seed por uma rodada ruim).

Uso:
  python run.py --dry-run        # só mostra fatos + prompt (não chama o modelo)
  python run.py                  # gera e escreve GAME_STATE.md (não commita)
  python run.py --commit         # também commita no branch atual (agents)

Config por env: OLLAMA_HOST (default http://localhost:11434), GM_MODEL (default qwen3:8b).
Sem dependências externas — só Python 3 + Ollama rodando.
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
PROMPT = Path(__file__).parent / "prompt.md"

OLLAMA = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
MODEL = os.environ.get("GM_MODEL", "qwen3:8b")

CATALOGS = ["items", "cards", "monsters", "maps", "skills", "quests", "classes", "formulas"]


def git(*args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(REPO), *args], capture_output=True, text=True
    ).stdout.strip()


def _recent_commits() -> list[str]:
    for ref in ("origin/master", "master", "HEAD"):
        out = git("log", "--oneline", "-15", ref)
        if out:
            return out.splitlines()
    return []


def gather_facts() -> dict:
    facts: dict = {"date": datetime.date.today().isoformat(), "errors": []}
    cat: dict = {}
    for name in CATALOGS:
        path = DATA_DIR / f"{name}.json"
        try:
            cat[name] = json.loads(path.read_text(encoding="utf-8"))
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
    facts["systems"] = sorted(
        p.stem for p in (REPO / "server" / "app" / "systems").glob("*.py") if p.stem != "__init__"
    )
    facts["recent_commits"] = _recent_commits()
    return facts


def call_ollama(prompt: str, timeout: int = 900) -> str:
    body = json.dumps(
        {"model": MODEL, "prompt": prompt, "stream": False, "options": {"temperature": 0.2}}
    ).encode()
    req = urllib.request.Request(
        f"{OLLAMA}/api/generate", data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())["response"]


def strip_think(text: str) -> str:
    return re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()


def sanity_ok(out: str, facts: dict) -> tuple[bool, str]:
    if len(out) < 800:
        return False, "saída muito curta"
    for header in ("# GAME STATE", "## 1.", "## 7."):
        if header not in out:
            return False, f"faltou a seção '{header}'"
    if "<think>" in out:
        return False, "sobrou bloco <think>"
    for mob in facts["monsters"]:
        mid, name = mob.get("id") or "", mob.get("name") or ""
        if mid and mid not in out and name not in out:
            return False, f"monstro '{mid}' não aparece no documento"
    return True, "ok"


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
    ap.add_argument("--dry-run", action="store_true", help="coleta fatos e mostra o prompt, sem chamar o modelo")
    ap.add_argument("--commit", action="store_true", help="commita o resultado no branch atual")
    args = ap.parse_args()

    facts = gather_facts()
    if facts["errors"]:
        print("SANITY FAIL — algum JSON não parseou:", facts["errors"], file=sys.stderr)
        sys.exit(1)

    previous = STATE.read_text(encoding="utf-8") if STATE.exists() else ""
    template = PROMPT.read_text(encoding="utf-8")
    prompt = template.replace("<<FACTS>>", json.dumps(facts, ensure_ascii=False, indent=2)).replace("<<PREVIOUS>>", previous)

    if args.dry_run:
        print(json.dumps(facts, ensure_ascii=False, indent=2))
        print(f"\n----- PROMPT ({len(prompt)} chars) -----\n{prompt[:1800]}\n...[truncado]")
        return

    print(f"[gm] chamando {MODEL} em {OLLAMA} ...", file=sys.stderr)
    out = strip_think(call_ollama(prompt))

    ok, why = sanity_ok(out, facts)
    if not ok:
        _changelog(f"rodada REJEITADA (sanity: {why}) — GAME_STATE preservado")
        print(f"[gm] saída rejeitada ({why}); documento anterior preservado.", file=sys.stderr)
        sys.exit(2)

    STATE.write_text(out.rstrip() + "\n", encoding="utf-8")
    _changelog("GAME_STATE.md atualizado pelo game-master")
    print("[gm] GAME_STATE.md atualizado.", file=sys.stderr)

    if args.commit:
        git("add", str(STATE.relative_to(REPO)), str(CHANGELOG.relative_to(REPO)))
        subprocess.run(
            ["git", "-C", str(REPO), "commit", "-m", "chore(agents): game-master atualiza GAME_STATE"],
            check=False,
        )
        print("[gm] commitado no branch atual.", file=sys.stderr)


if __name__ == "__main__":
    main()
