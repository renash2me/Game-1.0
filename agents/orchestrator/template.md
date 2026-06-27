# GAME STATE — Aethermoor

> Resumo vivo do estado do jogo, mantido pelo orquestrador (game-master).
> Última atualização: {{DATE}}.
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
Contagens: {{COUNTS}}

- **Monstros:** {{MONSTERS}}
- **Mapas:** {{MAPS}}

## 5. Fórmulas (`formulas.json`, editáveis no admin)
{{FORMULAS}}

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
{{NARRATIVE}}

Commits recentes:
{{RECENT_COMMITS}}
