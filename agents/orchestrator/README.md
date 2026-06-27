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
Sem dependências externas — só Python 3 (+ Ollama quando usar o modelo).

```bash
# gerar o GAME_STATE.md SEM o modelo (narrativa de fallback) — bom p/ testar:
python3 agents/orchestrator/run.py --no-llm

# gerar com o modelo (não commita):
python3 agents/orchestrator/run.py

# gerar e também commitar no branch agents:
python3 agents/orchestrator/run.py --commit
```

Config por variável de ambiente:
- `OLLAMA_HOST` (default `http://localhost:11434`)
- `GM_MODEL` (default `qwen3:4b`)

**Design (robusto p/ modelo pequeno em 4GB):** a estrutura e os fatos
(contagens, monstros, mapas, fórmulas, commits) são montados
**deterministicamente** a partir de `template.md` — sempre corretos. O modelo
faz **apenas o parágrafo de "mudanças recentes"** (seção 8), tarefa pequena e
confiável. Se o modelo falhar/voltar vazio, um **fallback** automático assume.
Resultado: o documento **sempre sai válido**.

**Guardrails:** ver `agents/README.md`. Não altera código nem dados do jogo —
apenas resume e coordena.
