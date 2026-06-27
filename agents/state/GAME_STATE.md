# GAME STATE — Aethermoor

> Resumo vivo do estado do jogo, mantido pelo orquestrador (game-master).
> Última atualização: 2026-06-27.
> A fonte da verdade é o código na `master`; este doc é um mapa.
> As seções 4, 5 e 8 são geradas automaticamente; o resto é prosa estável.

## 1. Visão geral
MMORPG 2.5D estilo Ragnarok Online. Cliente em **Godot 4.7**; servidor em
**Python / FastAPI**; **PostgreSQL** (persistência) + **Redis** (estado em tempo
real); **nginx** na frente. Tudo em **Docker**, stack 100% autossuficiente.

## 2. Estrutura do repositório
- `client/` — projeto Godot (cenas em `scenes/`, scripts em `scripts/`).
- `server/` — app FastAPI (`app/api`, `app/ws`, `app/systems`, `app/models`,
  `app/data` = catálogos JSON). Painel admin em `server/admin/index.html`.
- `agents/` — braço de agentes (este branch).
- `docker-compose.yml` — postgres-game, redis-game, game-server, nginx-game.

## 3. Sistemas implementados
- **Conta/personagem:** registro+login (JWT); seleção/criação/exclusão; novo
  personagem começa com 10 pontos de atributo.
- **Mundo/movimento:** câmera 3D ortográfica seguindo o player; movimento por
  clique **em grade** (estilo RO).
- **Mobs / IA:** spawn no **cadastro do monstro** (`spawns`: mapa, quantidade,
  área, respawn); idle/wander + aggro (1º alvo, com leash); **não fogem**;
  área degenerada vira box 400×400; **respawn ao vivo** ao salvar no admin.
- **Combate:** dirigido por dados (`formulas.json`); auto-attack com alvo
  travado; CRIT em %, perfect dodge.
- **Morte/renascimento:** HP 0 → modal → renasce na cidade segura; penalidade
  de XP (configurável); mobs perdem o alvo ao matar o player.
- **Regeneração:** HP/SP no tempo; mais rápido **sentado** (Insert).
- **Progressão:** XP; level-up restaura HP/SP 100% no novo máximo; pontos de
  atributo/skill; alocar atributos recalcula derivados.
- **Drops:** sorteio na morte; no chão; **dono = quem deu mais dano** (10s);
  somem em 15s; coleta com **clique esquerdo**; jogador pode **largar** itens.
- **Inventário:** abas Todos/Consumíveis/Equipamentos/Etc; equipar; largar.
- **Chat:** abas Mapa/Global/Party/**Batalha**; log de dano/XP e de drops;
  toggles no menu Esc.
- **HUD:** barras HP/SP/XP; coordenadas + nome do mapa no topo-direito; menu Esc.
- **Admin:** CRUD sobre os catálogos JSON; dados **persistidos via volume**;
  editar monstro/mapa **re-spawna ao vivo**.
- **Persistência:** Redis AOF + Postgres WAL/checkpoint; migrations via **Alembic**.

## 4. Catálogos de dados (`server/app/data/`)
Contagens: items: 18 · cards: 3 · monsters: 3 · maps: 2 · skills: 2 · quests: 2 · classes: 75 · formulas: 19

- **Monstros:** Poring (`poring`, passive), Fabre (`fabre`, aggressive), Lobo Filhote (`lobo_filhote`, passive)
- **Mapas:** Vila Inicial (`starter_village`), Planícies de Greenfield (`greenfield_plains`)

## 5. Fórmulas (`formulas.json`, editáveis no admin)
- `base_hp` = `35 + level * 5`
- `base_sp` = `10 + level * 3`
- `max_hp` = `round(base_hp * (1 + vit / 100))`
- `max_sp` = `round(base_sp * (1 + int / 100))`
- `atk` = `str + floor(dex / 5) + floor(luk / 3) + floor(level / 4)`
- `ranged_atk` = `dex + floor(str / 5) + floor(luk / 3) + floor(level / 4)`
- `matk` = `floor(level / 4) + int + floor(int / 2) + floor(dex / 5) + floor(luk / 3)`
- `hit` = `level + dex + floor(luk / 3)`
- `flee` = `level + agi + floor(luk / 5)`
- `crit` = `1 + luk * 0.3`
- `perfect_dodge` = `floor(luk / 10)`
- `max_weight` = `2000 + str * 30`
- `def` = `floor(vit / 2) + floor(agi / 5)`
- `mdef` = `floor(int / 2) + floor(vit / 5) + floor(dex / 5)`
- `hp_regen` = `max_hp / 200 + vit / 5`
- `sp_regen` = `max_sp / 100 + int / 6`
- `death_xp_penalty` = `5`
- `aspd_stat` = `min(193, 156 + agi * 0.4 + dex * 0.1)`
- `aspd` = `50 / (200 - aspd_stat)`

**Provisórios:** `base_hp`/`base_sp` (coeficientes só do Novice) e `aspd_stat`
(base/coefs chutados — no RO dependem de classe+arma, ainda não modeladas).

## 6. Pendências / lacunas conhecidas
- **Sprites de itens:** drops no chão usam placeholder (gema); falta arte por item.
- **HP/ASPD por classe:** o motor de fórmulas é global; falta receber classe/arma.
- **ATK/MATK completos:** só a parcela de Status; faltam arma/refino/equip/buff.
- **Skills com cast time:** não implementado.
- **Backlog:** guilds, party real, PvP, crafting, raids, mercado.
- **Playtesting:** ainda manual.

## 7. Restrições do projeto (NÃO violar)
- Tudo dentro do Docker; sem portas/volumes compartilhados com outros serviços.
- `.env` nunca é commitado.
- Migrations **sempre** via Alembic (nunca `create_all()` nem SQL manual).

## 8. Mudanças recentes (resumo do game-master)
Resumo automático dos commits recentes: refactor(data): padroniza IDs com underscore (card_lobo-filhote -> card_lobo_filhote); feat(data): novo monstro Lobo Filhote + carta Card Lobo Filhote (criados no admin); fix: mobs sumidos (área 0,0,0,0), inventário não mostrava itens e travava o andar; fix: pegar drop com clique esquerdo, persistir dados do admin, refresh do inventário; feat: coords no topo-direito + mapa, aba de batalha no chat e toggles de log; feat: drops com dono (mais dano, 10s), expiração 15s e sistema de largar item.

Commits recentes:
- ca89163 refactor(data): padroniza IDs com underscore (card_lobo-filhote -> card_lobo_filhote)
- 4ae47f6 feat(data): novo monstro Lobo Filhote + carta Card Lobo Filhote (criados no admin)
- f5a02c3 fix: mobs sumidos (área 0,0,0,0), inventário não mostrava itens e travava o andar
- b2ddb55 fix: pegar drop com clique esquerdo, persistir dados do admin, refresh do inventário
- a514067 feat: coords no topo-direito + mapa, aba de batalha no chat e toggles de log
- 1874f96 feat: drops com dono (mais dano, 10s), expiração 15s e sistema de largar item
- 8d2914c fix: drops não apareciam (cliente ignorava os drops do MOB_DEATH)
- aac69e3 feat: CD de respawn por monstro no admin + fix seletor de mapas + Enter no login
- a9cc389 fix: mob perde o alvo quando o jogador morre + limpa mobs antigos no boot
- ce7e99c fix: HP não subia ao alocar VIT (cache Redis defasado + floor no level baixo)
- 6b40c7c fix: restaura HP/SP 100% ao subir de level + corrige flag 'dead' presa
- 65689c9 feat: menu Esc (voltar/deslogar), seleção de personagem por slot e exclusão
