# GAME STATE — Aethermoor

> Resumo vivo do estado do jogo, mantido pelo orquestrador (game-master).
> Última atualização: 2026-06-27 (seed inicial, escrito pelo modelo da nuvem).
> Fonte da verdade é o código na `master`; este doc é um mapa, não substitui o código.

## 1. Visão geral
MMORPG 2.5D estilo Ragnarok Online. Cliente em **Godot 4.7**; servidor em
**Python / FastAPI**; **PostgreSQL** (persistência) + **Redis** (estado em tempo
real); **nginx** na frente. Tudo em **Docker**, stack 100% autossuficiente.

## 2. Estrutura do repositório
- `client/` — projeto Godot (cenas em `scenes/`, scripts em `scripts/`).
- `server/` — app FastAPI (`app/api`, `app/ws`, `app/systems`, `app/models`,
  `app/data` = catálogos JSON). Painel admin em `server/admin/index.html`.
- `docker-compose.yml` — postgres-game, redis-game, game-server, nginx-game.

## 3. Sistemas implementados
- **Conta/personagem:** registro+login (JWT); seleção/criação/exclusão de
  personagem; novo personagem começa com 10 pontos de atributo.
- **Mundo/movimento:** câmera 3D ortográfica seguindo o player; movimento por
  clique **em grade** (célula a célula, estilo RO).
- **Mobs / IA:** spawn definido no **cadastro do monstro** (campo `spawns`:
  mapa, quantidade, área, respawn por monstro); estados idle/wander + aggro
  (persegue o 1º alvo, com leash); **não fogem** (lutam até morrer); área de
  spawn degenerada vira box 400×400; **respawn ao vivo** quando o admin salva.
- **Combate:** dirigido por dados (`formulas.json`). Auto-attack com alvo
  travado (clica no mob → persegue e ataca). CRIT em %, perfect dodge.
- **Morte/renascimento:** HP 0 → modal de morte → renasce na cidade segura;
  penalidade de XP (configurável); mobs perdem o alvo ao matar o player.
- **Regeneração:** HP/SP ao longo do tempo; mais rápido **sentado** (Insert).
- **Progressão:** XP, level-up restaura HP/SP 100% no novo máximo; pontos de
  atributo/skill; alocar atributos recalcula derivados (HP sobe com VIT, etc.).
- **Drops:** sorteio na morte; renderizados no chão; **dono = quem deu mais
  dano** (preferência 10s); **somem em 15s**; coleta com **clique esquerdo**;
  jogador pode **largar** itens do inventário.
- **Inventário:** abas Todos/Consumíveis/Equipamentos/Etc; equipar; largar.
- **Chat:** abas Mapa/Global/Party/**Batalha**; log de dano/XP (aba Batalha) e
  de drops pegos (todas as abas); toggles de log no menu Esc.
- **HUD:** barras HP/SP/XP; coordenadas + nome do mapa no topo-direito; menu Esc
  (continuar / voltar à seleção / deslogar / configurações de log).
- **Admin:** CRUD sobre os catálogos JSON com formulários estruturados; dados
  **persistidos via volume**; editar monstro/mapa **re-spawna ao vivo**.
- **Persistência:** Redis AOF + Postgres WAL/checkpoint; checkpoint periódico;
  migrations via **Alembic**.

## 4. Catálogos de dados (`server/app/data/`)
`items.json`, `cards.json`, `monsters.json`, `maps.json`, `skills.json`,
`quests.json`, `classes.json`, `formulas.json`.

Hoje há 2 mapas (`starter_village`, `greenfield_plains`) e 2 monstros
(`poring` passivo, `fabre` agressivo — fabre fora da vila inicial por enquanto).

## 5. Fórmulas (`formulas.json`, editáveis no admin)
max_hp = round(base_hp × (1+VIT/100)); max_sp análogo; atk/ranged_atk/matk,
hit, flee, crit (%), perfect_dodge, def, mdef, hp_regen, sp_regen,
death_xp_penalty, aspd (= 50/(200−aspd_stat)).
**Provisórios:** `base_hp`/`base_sp` (coeficientes só do Novice) e `aspd_stat`
(base/coefs chutados — no RO dependem de classe+arma, ainda não modeladas).

## 6. Pendências / lacunas conhecidas
- **Sprites de itens:** drops no chão usam um placeholder (gema amarela); falta
  arte por item.
- **HP/ASPD por classe:** o motor de fórmulas é global; falta receber classe/arma.
- **ATK/MATK completos:** só a parcela de Status; faltam arma/refino/equip/buff.
- **Skills com cast time:** não implementado.
- **Backlog:** guilds, party real, PvP, crafting, raids, mercado, Wheel of Time.
- **Playtesting:** ainda manual.

## 7. Restrições do projeto (NÃO violar)
- Tudo dentro do Docker; sem portas/volumes compartilhados com outros serviços.
- `.env` nunca é commitado.
- Migrations **sempre** via Alembic (nunca `create_all()` nem SQL manual).
