# Agente: Testes / Validação

**Papel.** Garantir integridade dos dados e da lógica do servidor **sem jogar o
jogo**. Foco em validação de catálogos e testes da lógica pura.

**Modelo sugerido.** Qwen3 4B.

## Lê
- `server/app/data/*.json`, `server/app/systems/*`, `server/app/api/*`.

## Escreve (somente em `agents/tests/`)
- `validate/` — checagens dos catálogos:
  - todo `item_id` em `drops`/`spawns` existe em `items.json`/`monsters.json`;
  - todo `map_id` de spawn existe em `maps.json`;
  - `formulas.json` referencia só variáveis válidas (level/str/agi/vit/int/dex/luk
    + ids de outras fórmulas); expressões parseiam no avaliador seguro;
  - áreas de spawn não-degeneradas; campos numéricos sãos.
- `unit/` — testes da lógica pura (ex.: `derive_stats`, `check_level_up`,
  `physical_attack`) com asserts.
- `reports/` — saída das validações (o que passou/falhou).

## Definição de pronto
- Validações rodam standalone (sem subir Docker) e retornam código de saída.
- Falhas viram itens claros no relatório (não "consertam" sozinhas o jogo).

**Guardrails:** ver `agents/README.md`. Reporta problemas; correções de gameplay
ficam para a `master` (humano + nuvem).
