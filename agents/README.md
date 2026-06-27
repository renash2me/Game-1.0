# Aethermoor — Braço de Agentes

Este branch (`agents`) é o **braço de suporte** do projeto, operado por um time de
agentes locais (Ollama). Eles NÃO escrevem features de gameplay — esse trabalho
continua na `master` (humano + modelo da nuvem). O time aqui cuida de **lore,
documentação, balanceamento (por simulação), validação/testes e arte**.

## Como funciona

- **Branch único, mesmo repo.** Este branch = `master` + a pasta `agents/`. Nada
  fica "fora" — para ver o trabalho do time: `git checkout agents` (ou olhe o
  branch no GitHub).
- **Sincronização.** Antes de cada rodada, a pipeline traz a `master` para cá
  (`merge`/`rebase`), para os agentes trabalharem sempre sobre o código mais novo.
- **Disparo.** Um *daemon de polling* na máquina host faz `git fetch` a cada X
  minutos; havendo commit novo na `master`, dispara a rodada.
- **Host.** Ollama rodando localmente (notebook RTX 3050 4GB ou Mac mini). A
  arquitetura é agnóstica de host — trocar o host não muda mais nada.
  Modelo padrão: **Qwen3 4B** (cavalo de batalha); **8B** para tarefas mais
  pesadas (ex.: orquestrador), com a ressalva de ser lento em 4GB de VRAM.
- **Um agente por vez.** Em 4GB de VRAM não há paralelismo real — a pipeline roda
  os agentes em sequência, trocando o modelo carregado.
- **Revisão.** Os agentes commitam direto neste branch (é o staging). A "porteira"
  é o merge **`agents` → `master`**, revisado de tempos em tempos por humano +
  modelo da nuvem.

## Guardrails (valem para TODO agente)

- Empurram **somente** para o branch `agents`. **Nunca** para `master`.
- **Nunca** tocam em `.env`, segredos, credenciais, migrations ou infra (Docker).
- **Nada destrutivo** (sem deletar dados, sem `force push`, sem mexer no banco).
- Cada agente escreve **só na sua pasta**. Commits limpos e escopados (1 commit
  por agente por rodada).
- Em dúvida, **propõem** (escrevem um rascunho/relatório) em vez de alterar o jogo.

## Pastas

| Pasta            | Papel                                              |
|------------------|----------------------------------------------------|
| `orchestrator/`  | Game-master: mantém o `state/GAME_STATE.md`, ordena a rodada e faz o sanity check. |
| `state/`         | `GAME_STATE.md` — resumo vivo do estado do jogo.   |
| `lore/`          | Desenvolve a lore (mundo, história, facções, NPCs).|
| `docs/`          | Documentação do jogo e dos sistemas.               |
| `balance/`       | Balanceamento por **simulação** (scripts sobre as fórmulas/dados). |
| `art/`           | Arte/sprites — **requer modelo de imagem separado** (difusão), ainda não habilitado. |
| `tests/`         | Validação de dados e testes da lógica do servidor. |
