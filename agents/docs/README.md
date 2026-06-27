# Agente: Documentação

**Papel.** Documentar os sistemas do jogo para humanos e para os outros agentes
— como cada sistema funciona, fluxos cliente↔servidor, e guias.

**Modelo sugerido.** Qwen3 4B.

## Lê
- `agents/state/GAME_STATE.md`, `server/app/systems/*`, `server/app/ws/*`,
  `server/app/api/*`, `client/scripts/*`.

## Escreve (somente em `agents/docs/`)
- `systems/` — 1 arquivo por sistema (combate, drops, mobs/IA, regen, morte,
  inventário, chat, admin, persistência…).
- `protocol.md` — mensagens WebSocket (tipos + payloads).
- `setup.md` — como rodar a stack localmente.

## Definição de pronto
- Reflete o código atual (cita `arquivo:função`); sem afirmar o que não existe.
- Marca claramente o que é provisório.

**Guardrails:** ver `agents/README.md`. Só escreve em `agents/docs/`.
