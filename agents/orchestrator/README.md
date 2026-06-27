# Orquestrador (Game Master)

**Papel.** Coordenar a rodada do time e manter o resumo vivo do jogo.

**Modelo sugerido.** Qwen3 8B (mais raciocínio) — ou 4B se o 8B ficar lento demais.

## O que faz
1. Lê o repositório (código + dados) e os outputs dos outros agentes.
2. Atualiza **`agents/state/GAME_STATE.md`** com o estado atual do jogo.
3. Define a **ordem da rodada** (ex.: docs → balance → lore → tests).
4. Faz um **sanity check leve** antes de fechar a rodada:
   - todos os JSON em `server/app/data/` ainda parseiam;
   - os testes em `agents/tests/` (se houver) passam;
   - nenhum agente escreveu fora da própria pasta.
5. Escreve um resumo curto da rodada (o que cada agente mudou).

## Lê
- Todo o repo, com foco em `server/app/data/*.json`, `server/app/systems/*`,
  `client/scripts/*` e os outputs de `agents/*`.

## Escreve
- `agents/state/GAME_STATE.md`
- `agents/state/CHANGELOG.md` (1 entrada por rodada)

## Definição de pronto
- `GAME_STATE.md` reflete a `master` atual, com seção de "pendências/provisórios".
- Sanity check passou; resumo da rodada registrado.

## Como rodar (`run.py`)
Sem dependências externas — só Python 3 + Ollama rodando.

```bash
# ver os fatos coletados e o prompt, SEM chamar o modelo:
python3 agents/orchestrator/run.py --dry-run

# gerar e escrever o GAME_STATE.md (não commita):
python3 agents/orchestrator/run.py

# gerar e também commitar no branch agents:
python3 agents/orchestrator/run.py --commit
```

Config por variável de ambiente:
- `OLLAMA_HOST` (default `http://localhost:11434`)
- `GM_MODEL` (default `qwen3:8b`; use `qwen3:4b` se o 8B ficar lento no 3050)

**Robustez:** os fatos (contagens, monstros, mapas, fórmulas, commits) são
coletados deterministicamente; o modelo só faz a prosa. A saída só sobrescreve o
`GAME_STATE.md` se passar num **sanity check** (seções certas, cita todos os
monstros, sem `<think>` solto). Se falhar, o doc anterior é **preservado** e a
rejeição vai pro `CHANGELOG.md`.

**Guardrails:** ver `agents/README.md`. Não altera código nem dados do jogo —
apenas resume e coordena.
