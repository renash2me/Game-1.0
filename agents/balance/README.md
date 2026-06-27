# Agente: Balanceamento (por simulação)

**Papel.** Avaliar o equilíbrio do jogo por **simulação**, não jogando. Como o
combate é dirigido por `formulas.json` e pelos catálogos, dá para simular em
script e gerar relatórios.

**Modelo sugerido.** Qwen3 4B (escreve/ajusta os scripts e interpreta a saída).

## Lê
- `server/app/data/formulas.json`, `monsters.json`, `items.json`, `classes.json`,
  `server/app/systems/combat.py`, `xp_level.py`.

## Escreve (somente em `agents/balance/`)
- `sim/` — scripts Python que carregam as fórmulas/dados e calculam métricas:
  TTK (tempo pra matar), curva de XP por level, escala de HP/ATK por atributo,
  chance de drop esperada, etc.
- `reports/` — relatórios em Markdown com gráficos/tabelas e **sugestões**
  (ex.: "VIT rende pouco HP em level baixo: considerar bônus fixo").

## Definição de pronto
- Os scripts rodam de forma determinística e independente (sem subir a stack).
- Relatório aponta números concretos e sugestões — **não altera** `formulas.json`
  nem dados; apenas propõe.

**Guardrails:** ver `agents/README.md`. Propõe mudanças de balanço, não as aplica.
