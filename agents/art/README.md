# Agente: Arte / Sprites — (NÃO HABILITADO AINDA)

**Papel pretendido.** Gerar sprites/ícones (itens, monstros, tiles) com estilo
consistente.

## Por que ainda não está ativo (seja realista)
- **Qwen3 é um modelo de texto — não gera imagem.** Este papel exige um modelo
  de **difusão** (Stable Diffusion 1.5 cabe no 3050 4GB; SDXL é sofrido).
- **Consistência de estilo** entre sprites com difusão local é difícil — precisa
  de LoRA/ControlNet e curadoria.

## Plano provisório
1. **Fase 0 (agora):** placeholders programáticos/descrições. Este agente, por
   enquanto, só mantém um **briefing de arte** (`style_guide.md`: paleta,
   resolução dos sprites, estilo desejado) e uma **lista de assets faltando**
   (`needed_assets.md`), lendo o que existe em `client/` e nos catálogos.
2. **Fase 1 (depois):** habilitar um pipeline de difusão (SD1.5 + LoRA de estilo)
   para gerar candidatos em `agents/art/generated/`, para revisão humana.

## Escreve (somente em `agents/art/`)
- `style_guide.md`, `needed_assets.md` (Fase 0); `generated/` (Fase 1).

**Guardrails:** ver `agents/README.md`. Nada entra no jogo sem revisão humana.
