# Aethermoor — Documentação Técnica Completa

## Índice

1. [Visão Geral](#1-visão-geral)
2. [Infraestrutura e Deploy](#2-infraestrutura-e-deploy)
3. [Servidor — Estrutura e Inicialização](#3-servidor--estrutura-e-inicialização)
4. [Banco de Dados](#4-banco-de-dados)
5. [Cache Redis](#5-cache-redis)
6. [Autenticação e Segurança](#6-autenticação-e-segurança)
7. [API REST](#7-api-rest)
8. [WebSocket — Protocolo e Mensagens](#8-websocket--protocolo-e-mensagens)
9. [Sistemas de Jogo](#9-sistemas-de-jogo)
10. [Dados Estáticos](#10-dados-estáticos)
11. [Cliente Godot 4](#11-cliente-godot-4)
12. [Como Rodar](#12-como-rodar)
13. [Backlog](#13-backlog)

---

## 1. Visão Geral

**Aethermoor** é um MMORPG 2D inspirado em Ragnarok Online, construído com:

| Componente | Tecnologia |
|-----------|-----------|
| Servidor | Python 3.12 + asyncio |
| API REST | FastAPI (porta 8000) |
| WebSocket | `websockets` lib (porta 8001) |
| Banco de dados | PostgreSQL 16 |
| Cache | Redis 7 |
| ORM | SQLAlchemy 2.0 async |
| Migrations | Alembic |
| Auth | JWT (python-jose) + bcrypt |
| Proxy reverso | Traefik v3 |
| Cliente | Godot 4.2 (GDScript) |
| Deploy | Docker Compose (ARM64 — Raspberry Pi 5) |

**Princípios arquiteturais:**
- Tudo roda em Docker. Nenhum serviço é instalado diretamente no host.
- O stack do jogo é 100% isolado: rede, volumes e portas são exclusivos.
- Dados voláteis (posição, HP em batalha, mobs, drops) ficam no Redis.
- Dados persistentes (level, inventário, quests) ficam no PostgreSQL.
- Catálogos estáticos (monstros, itens, mapas) são JSON carregados em memória na inicialização — nunca consultados em banco durante gameplay.
- Migrations sempre via Alembic. Nunca `create_all()` manual.

---

## 2. Infraestrutura e Deploy

### Topologia Docker

```
Host (DonaOdete — Raspberry Pi 5, ARM64)
│
└── porta 7080 ──► traefik-game (Traefik v3)
                        │
                        ├── /api/* ──► game-server :8000 (FastAPI)
                        └── /ws     ──► game-server :8001 (WebSocket)

Rede interna: aethermoor_net (bridge)
  ├── aethermoor_postgres (PostgreSQL 16)
  ├── aethermoor_redis    (Redis 7)
  ├── aethermoor_server   (servidor do jogo)
  └── aethermoor_traefik  (proxy)
```

A porta **7080** foi escolhida para não conflitar com OMV7 (que usa 80/443).

### `docker-compose.yml`

Quatro serviços:

**`postgres-game`**
- Imagem `postgres:16`
- Volume persistente `aethermoor_pgdata`
- Healthcheck: `pg_isready`
- Credenciais via `.env`

**`redis-game`**
- Imagem `redis:7-alpine`
- Volume persistente `aethermoor_redis_data`
- Healthcheck: `redis-cli ping`

**`game-server`**
- Build local via `server/Dockerfile`
- `platform: linux/arm64` (nativo no Raspberry Pi)
- Depende de postgres e redis (com `condition: service_healthy`)
- Labels Traefik para roteamento duplo (porta 8000 e 8001)

**`traefik-game`**
- Imagem `traefik:v3`
- Expõe apenas `:7080` no host
- Descobre serviços via Docker labels
- Roteamento por prefixo de path:
  - `PathPrefix(/api)` → `game-server:8000`
  - `PathPrefix(/ws)` → `game-server:8001`

### `docker-compose.dev.yml`

Arquivo de desenvolvimento (overlay). Diferenças em relação ao produção:
- Bind mount `./server:/app` (hot reload sem rebuild)
- Expõe 8000 e 8001 diretamente no host
- Dashboard Traefik na porta 7088

### Dockerfile (multi-stage)

```
Stage 1 (builder): python:3.12-slim + gcc
  → instala dependências com compilação nativa (asyncpg, bcrypt, hiredis)

Stage 2 (runtime): python:3.12-slim
  → copia apenas o virtualenv do builder
  → EXPOSE 8000 8001
  → CMD: python entrypoint.py
```

### Variáveis de Ambiente (`.env`)

```
POSTGRES_USER=...
POSTGRES_PASSWORD=...
POSTGRES_DB=aethermoor
DATABASE_URL=postgresql+asyncpg://...
REDIS_URL=redis://redis-game:6379/0
JWT_SECRET=...
JWT_EXPIRE_HOURS=24
GAME_API_PORT=8000
GAME_WS_PORT=8001
```

O `.env` é ignorado pelo git (`.gitignore`). O `.env.example` com placeholders é versionado.

---

## 3. Servidor — Estrutura e Inicialização

### Árvore de arquivos

```
server/
├── entrypoint.py               # Ponto de entrada: inicia API + WS juntos
├── requirements.txt
├── alembic.ini
├── alembic/
│   ├── env.py                  # Configuração async do Alembic
│   └── versions/
│       ├── 001_create_players_and_characters.py
│       ├── 002_create_inventory.py
│       └── 003_create_quests.py
└── app/
    ├── config.py               # Settings via pydantic-settings
    ├── database.py             # Engine async, sessão, Base ORM
    ├── redis_client.py         # Singleton de conexão Redis
    ├── main.py                 # FastAPI app + lifespan
    ├── api/                    # Routers REST
    │   ├── auth.py
    │   ├── characters.py
    │   ├── inventory.py
    │   └── quests.py
    ├── core/
    │   ├── security.py         # JWT + bcrypt
    │   └── deps.py             # Dependency injection (get_current_player)
    ├── models/                 # SQLAlchemy ORM
    │   ├── player.py
    │   ├── character.py
    │   ├── inventory.py
    │   └── quest.py
    ├── schemas/                # Pydantic v2 (request/response)
    │   ├── auth.py
    │   ├── character.py
    │   ├── inventory.py
    │   └── quest.py
    ├── data/                   # Catálogos estáticos JSON
    │   ├── loader.py
    │   ├── maps.json
    │   ├── monsters.json
    │   ├── items.json
    │   ├── cards.json
    │   ├── classes.json
    │   ├── quests.json
    │   └── skills.json
    ├── systems/                # Lógica de jogo
    │   ├── combat.py
    │   ├── drop_system.py
    │   ├── mob_ai.py
    │   ├── mob_spawn.py
    │   ├── quest_engine.py
    │   ├── refinement.py
    │   ├── xp_level.py
    │   └── aptitude.py
    └── ws/                     # WebSocket
        ├── server.py           # Aceita conexões e orquestra auth/dispatch
        ├── handlers.py         # Lógica de cada mensagem
        ├── connection_manager.py
        ├── manager.py          # Singleton do ConnectionManager
        └── broadcaster.py
```

### `entrypoint.py`

Inicia FastAPI (uvicorn) e o servidor WebSocket em paralelo com `asyncio.gather`:

```python
asyncio.gather(
    start_api(),        # uvicorn na porta 8000
    start_websocket()   # websockets.serve na porta 8001
)
```

### Ciclo de vida da aplicação (`main.py`)

No startup via `lifespan`:
1. `load_all()` — carrega todos os JSONs estáticos em dicionários Python
2. `initialize_all_maps()` — faz spawn inicial dos mobs e inicia tasks de IA por mapa

No shutdown:
- Cancela todas as tasks asyncio de IA de mobs

---

## 4. Banco de Dados

### Modelos ORM

#### `Player` (tabela `players`)

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| id | UUID PK | Gerado automaticamente |
| username | String(32) unique | Login |
| email | String(256) unique | E-mail |
| password_hash | String | bcrypt hash |
| created_at | DateTime TZ | |
| last_login | DateTime TZ | |
| is_active | Boolean | default True |

Relacionamento: `characters` (um-para-muitos)

#### `Character` (tabela `characters`)

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| id | UUID PK | |
| player_id | UUID FK | |
| name | String(64) unique | Nome no jogo |
| class_id | String(32) | `novice`, `warrior`, etc. |
| class_tier | Integer | 0 = Novice, 1 = 1ª classe |
| level | Integer | 1-99 |
| xp / xp_to_next | BigInteger | |
| str_stat | Integer | coluna SQL: `"str"` |
| agi, vit, dex, luk | Integer | |
| int_stat | Integer | coluna SQL: `"int_"` |
| stat_points / skill_points | Integer | Pontos a distribuir |
| hp / hp_max | Integer | |
| sp / sp_max | Integer | |
| void_gauge / void_gauge_max | Integer | Para sistema futuro de classes secretas |
| current_map | String(64) | |
| pos_x / pos_y | Float | |
| zeny | BigInteger | Moeda do jogo |
| aptitude_data | JSONB | Rastreamento silencioso do Novice |

> **Nota sobre colunas reservadas:** `str` e `int` são palavras reservadas em SQL/Python. O ORM usa `str_stat` e `int_stat` como atributos Python, mas persiste nas colunas `"str"` e `"int_"`.

#### `InventoryItem` (tabela `inventory_items`)

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| id | UUID PK | |
| character_id | UUID FK | |
| item_id | String | ID do catálogo |
| quantity | Integer | ≥ 1 |
| slot_index | Integer nullable | null = item não organizado em slot |
| is_equipped | Boolean | |
| equip_slot | String nullable | `weapon`, `head`, `body`, etc. |
| refinement | Integer | 0-7 |
| cards | JSONB | Lista de card_ids encaixados |
| enchants | JSONB | Lista de encantamentos |

#### `Quest` (tabela `quests`)

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| id | UUID PK | |
| character_id | UUID FK | |
| quest_id | String | ID do catálogo |
| status | String | `active`, `ready_to_deliver`, `completed` |
| progress | JSONB | Objetivos com progresso atual |
| accepted_at | DateTime TZ | |
| completed_at | DateTime TZ nullable | |
| daily_streak | Integer | Sequência de dias consecutivos |

Constraint única: `(character_id, quest_id)` — um personagem não pode ter a mesma quest duas vezes ativa.

### Migrations (Alembic)

O `env.py` usa engine async e importa todos os modelos para registrar a metadata no `Base`. As migrations são aplicadas manualmente:

```bash
docker compose exec game-server alembic upgrade head
```

Nunca use `Base.metadata.create_all()` — isso ignoraria o histórico de migrations.

---

## 5. Cache Redis

Redis é a camada de dados **volátil** do jogo. Nenhum dado crítico de gameplay fica exclusivamente aqui — tudo persistido em PG no momento certo.

### Chaves e estruturas

| Chave | Tipo Redis | Conteúdo |
|-------|-----------|---------|
| `char_stats:{char_id}` | Hash | Todos os atributos do personagem (level, hp, stats, mapa atual, etc.) |
| `pos:{char_id}` | Hash | `{map_id, x, y}` — posição em tempo real |
| `online_players:{map_id}` | Set | IDs dos personagens online no mapa |
| `mob:{instance_id}` | Hash | Estado completo de uma instância de mob (hp, pos, state, target, etc.) |
| `map_mobs:{map_id}` | Set | IDs das instâncias de mob ativas no mapa |
| `drop:{drop_id}` | Hash | `{item_id, quantity, x, y, map_id}` — TTL 300s |
| `map_drops:{map_id}` | Set | IDs dos drops ativos no mapa |

### Por que Redis e não só PostgreSQL?

Durante combat loop e mob AI (300ms tick), cada tick lê e escreve posição, HP e estado de cada mob. Consultar o banco a cada 300ms por mob seria inviável. Redis mantém esses dados em memória com latência de sub-milissegundo.

Quando algo precisa persistir (level up, quest completa, pickup de item), o servidor escreve no PostgreSQL de forma assíncrona sem bloquear o game loop.

---

## 6. Autenticação e Segurança

### Fluxo de registro

1. `POST /api/auth/register` com `{username, email, password}`
2. Valida: username alfanumérico 3-20 chars; password mínimo 6 chars
3. Gera hash bcrypt da senha
4. Persiste `Player` no banco
5. Retorna `TokenResponse{access_token, token_type, expires_in}`

### Fluxo de login

1. `POST /api/auth/login` com `{username, password}`
2. Busca player por username
3. `bcrypt.checkpw(password, hash)` — timing-safe
4. Gera JWT com `sub = player_id`
5. Retorna `TokenResponse`

### JWT

- Algoritmo: HS256
- Payload: `{sub: player_id_str, exp: timestamp}`
- Expiração: 24h (configurável via `JWT_EXPIRE_HOURS`)
- Secret: variável de ambiente `JWT_SECRET`

### Proteção de rotas (REST)

`get_current_player` em `core/deps.py`:
1. Extrai Bearer token do header `Authorization`
2. `decode_token(token)` → `player_id: str`
3. Busca `Player` no banco
4. Retorna o objeto Player para a rota usar

### Proteção WebSocket

A primeira mensagem deve ser do tipo `AUTH` com `{token, character_id}`. O servidor tem timeout de 10 segundos para receber essa mensagem. Se não receber, fecha a conexão com código 4002. Após auth válida, envia `AUTH_OK` e registra o personagem no mapa.

---

## 7. API REST

Base URL (produção): `http://donaodete.local:7080`

Documentação Swagger: `http://donaodete.local:7080/api/docs`

### Auth

| Método | Endpoint | Autenticação | Descrição |
|--------|----------|-------------|-----------|
| POST | `/api/auth/register` | Não | Cria conta + retorna token |
| POST | `/api/auth/login` | Não | Login + retorna token |

### Personagens

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/api/characters` | Lista personagens da conta (máx 9) |
| POST | `/api/characters` | Cria personagem (só `class_id: "novice"`) |
| GET | `/api/characters/{id}` | Detalhes de um personagem |

### Inventário

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/api/inventory/{char_id}` | Lista itens do inventário |
| POST | `/api/inventory/{char_id}/equip` | Equipa um item |
| POST | `/api/inventory/{char_id}/unequip` | Desequipa um item |
| POST | `/api/inventory/{char_id}/refine` | Tenta refinamento |
| POST | `/api/inventory/{char_id}/socket-card` | Encaixa carta em slot |

**Empilhamento de itens:** Materials e consumables são empilhados automaticamente (incrementa `quantity`). Equipamentos não são empilháveis — cada peça gera uma linha nova.

### Quests

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/api/quests/{char_id}` | Catálogo com status: available/active/completed/locked |
| POST | `/api/quests/{char_id}/accept` | Aceita uma quest |
| POST | `/api/quests/{char_id}/deliver` | Entrega quest concluída |

---

## 8. WebSocket — Protocolo e Mensagens

URL: `ws://donaodete.local:7080/ws`

### Formato de mensagem (JSON)

```json
{
  "type": "TIPO_DA_MENSAGEM",
  "payload": { ... },
  "timestamp": 1719000000000
}
```

### Fluxo de conexão

```
Cliente                         Servidor
   |                               |
   |──── connect ──────────────────►|
   |                               | (inicia timer 10s)
   |──── AUTH {token, char_id} ───►|
   |                               | valida JWT + busca personagem no banco
   |                               | popula char_stats no Redis
   |◄─── AUTH_OK {map_id, pos} ────|
   |                               | registra no mapa + envia estado inicial
   |◄─── MAP_PLAYERS {...} ─────────|
   |◄─── MOB_SPAWN {...} ───────────|
   |                               |
   | (gameplay loop)               |
   |──── MOVE {x, y, map_id} ─────►|
   |──── ATTACK {target_id} ──────►|
   |──── PICKUP {drop_id} ─────────►|
   |──── CHAT {channel, content} ──►|
```

### Mensagens Cliente → Servidor

| Tipo | Payload | Descrição |
|------|---------|-----------|
| `AUTH` | `{token, character_id}` | Primeira mensagem obrigatória |
| `MOVE` | `{x, y, map_id}` | Atualiza posição |
| `ATTACK` | `{target_id}` | Ataca instância de mob |
| `PICKUP` | `{drop_id}` | Pega item do chão |
| `CHAT` | `{channel, content}` | Envia mensagem de chat |

### Mensagens Servidor → Cliente

| Tipo | Descrição |
|------|-----------|
| `AUTH_OK` | Conexão autenticada com sucesso |
| `MAP_PLAYERS` | Lista de jogadores no mapa ao entrar |
| `MOB_SPAWN` | Lista de mobs ativos ao entrar |
| `PLAYER_MOVE` | Outro jogador se moveu |
| `PLAYER_JOIN` | Jogador entrou no mapa |
| `PLAYER_LEAVE` | Jogador saiu do mapa |
| `MOB_MOVE` | Mob se moveu (emitido pelo AI loop) |
| `MOB_DEATH` | Mob morreu + lista de drops |
| `DROP_PICKED` | Drop foi coletado por alguém |
| `DAMAGE` | Ataque aconteceu (player→mob ou mob→player) |
| `LEVEL_UP` | Personagem subiu de nível |
| `QUEST_UPDATE` | Status de quest mudou |
| `CHAT_MESSAGE` | Mensagem de chat recebida |

### Canais de chat

`global`, `local` (mesmo mapa), `party`, `guild`, `whisper`

### Broadcaster

`broadcaster.py` oferece três funções:
- `send_to(manager, char_id, msg)` — envia para um personagem específico
- `broadcast_map(manager, map_id, msg, exclude=None)` — envia para todos no mapa
- `broadcast_global(manager, msg)` — envia para todos conectados

Todas usam `asyncio.gather(..., return_exceptions=True)` para não falhar se um cliente desconectou.

---

## 9. Sistemas de Jogo

### 9.1 XP e Nível (`xp_level.py`)

**Fórmula de XP por nível:**
```
xp_necessário(level) = int(10 × level^1.6)
```

Exemplos: Lv1→2: 10 XP | Lv10→11: 251 XP | Lv50→51: 3.195 XP

- Level cap: **99**
- Por level: **+3 stat points**, **+1 skill point**
- Level up em cadeia é suportado (matar um mob forte pode subir múltiplos levels)

### 9.2 Combate (`combat.py`)

**Stats derivados dos atributos:**

| Stat | Fórmula |
|------|---------|
| ATK | `STR + (STR // 10)²` |
| DEF | `VIT // 2` |
| HIT | `DEX + level` |
| FLEE | `AGI + level` |
| CRIT | `LUK × 30` (em unidades 1/10000) |

**Resolução de ataque físico:**
1. **Miss:** `chance = max(5%, min(95%, (FLEE_def - HIT_atk) / 200 + 0.2))`
2. **Crítico:** roll em `1..10000 ≤ CRIT` (500 = 5%)
3. **Dano base:** `ATK × random(0.9, 1.1)`
4. Se crítico: `dano × 1.5` (ignora defesa)
5. Se normal: `dano × (1 - min(90%, DEF_def / 100))`
6. Mínimo 1 de dano

**Stats de mob:**
- ATK é rolado em `[attack_min, attack_max]` a cada ataque
- HIT, FLEE e CRIT usam os atributos do JSON de monstros

### 9.3 IA de Mobs (`mob_ai.py`)

Loop por mapa com tick de **300ms** (asyncio task). A cada tick, lê todos os mobs do mapa via Redis e processa a máquina de estados:

```
IDLE ──────────────────────────────► AGGRO
  │   (jogador entra no aggro_range)   │
  │                                    │
  │ (wander aleatório dentro de        │ (persegue + ataca quando em range)
  │  150px do centro do spawn)         │
  │                                    │
  └───────────────────────────────◄────┘
         (HP < 20%)    FLEE
                         │
                    (foge do alvo em
                     velocidade ×1.5)
```

**Detalhes de cada estado:**

**IDLE:**
- Mobs agressivos verificam se há jogador no `aggro_range` a cada tick
- Wandering: a cada 3s (±0.5s) escolhe um destino aleatório dentro de 150px do spawn
- Move na metade da velocidade ao vagar

**AGGRO:**
- A cada tick move em direção ao alvo
- Quando a distância ≤ `attack_range` (50px): ataca com cooldown de 1500ms
- Se o alvo desconectar, volta a IDLE

**FLEE:**
- Ativado quando HP < 20%
- Move na direção oposta ao alvo com velocidade ×1.5
- Se HP se recuperar ≥ 20%, volta a AGGRO

### 9.4 Spawn e Respawn de Mobs (`mob_spawn.py`)

**Na inicialização** (`initialize_all_maps`):
- Para cada mapa → para cada `spawn_point` → gera N instâncias de mob
- Cada instância recebe um UUID único, é escrita no Redis (`mob:{id}` hash e `map_mobs:{map_id}` set)
- Inicia uma task asyncio de IA por mapa

**Respawn:** Quando um mob morre, `respawn_mob_later(mob_id, map_id, area, seconds)` agenda um `asyncio.sleep` com o tempo configurado no JSON do mapa. Após o sleep, cria nova instância e faz broadcast de `MOB_SPAWN`.

### 9.5 Sistema de Drops (`drop_system.py`)

- Cada mob tem uma lista de drops com `item_id` e `chance` (0.0–1.0)
- Cada item é rolado **independentemente** (não é exclusivo)
- Cartas têm chance adicional de `0.0001` (1 em 10.000)
- Drops ficam no Redis com **TTL de 300 segundos**
- Quando coletado: remove do Redis → adiciona ao inventário no PostgreSQL

### 9.6 Refinamento (`refinement.py`)

Equipamentos podem ser refinados de +0 a **+7**:

| Nível atual | Custo (zeny) | Taxa de sucesso |
|-------------|-------------|-----------------|
| +0 | 100 | 100% |
| +1 | 300 | 100% |
| +2 | 600 | 100% |
| +3 | 1.200 | 100% |
| +4 | 2.500 | 95% |
| +5 | 5.000 | 85% |
| +6 | 10.000 | 70% |

**Falha:** perde o zeny mas o item **não é destruído** (o nível não aumenta).

**Bônus por nível:**
- Arma: `+2 ATK` por nível de refinamento
- Armadura/proteções: `+1 DEF` por nível de refinamento

### 9.7 Sistema de Quests (`quest_engine.py`)

Quests são definidas em `quests.json` e têm objetivos do tipo:
- `kill_mob` — matar N mobs de um tipo específico
- `visit_map` — visitar um mapa

**Fluxo:**
1. Jogador aceita quest via `POST /api/quests/{char_id}/accept`
2. Durante gameplay, `update_kill_progress` e `update_map_progress` são chamados de forma assíncrona (fire-and-forget) a cada kill/troca de mapa
3. Quando todos objetivos estão completos, o status muda para `ready_to_deliver`
4. Servidor envia `QUEST_UPDATE` ao cliente
5. Jogador entrega via `POST /api/quests/{char_id}/deliver` → recebe XP, zeny e itens

**Progresso em JSONB:**
```json
{
  "objectives": [
    {"type": "kill_mob", "mob_id": "poring", "count": 10, "current": 7}
  ]
}
```

**Daily streak:** Quests diárias têm contador de `daily_streak`. Completar no dia seguinte incrementa a streak; quebrar a sequência reseta para 0.

### 9.8 Sistema de Aptidão (`aptitude.py`)

Exclusivo para personagens `class_id = "novice"`. Rastreia comportamentos **silenciosamente** (o jogador não vê) para uso futuro no sistema de Void Gauge e classes secretas.

Dados acumulados em `character.aptitude_data` (JSONB):

| Campo | Descrição |
|-------|-----------|
| `combat_kills` | Total de mobs abatidos |
| `damage_dealt` | Dano total causado |
| `damage_taken` | Dano total recebido |
| `maps_explored` | Lista de mapas visitados |
| `zeny_looted` | Total de zeny coletado |

A atualização é feita via `asyncio.ensure_future` para não bloquear o game loop. Se o personagem evoluir de Novice, o tracking para automaticamente.

---

## 10. Dados Estáticos

Todos os JSONs ficam em `server/app/data/`. São carregados em dicionários `{id: entry}` na inicialização pelo `loader.py` e nunca mais consultados via banco.

### `maps.json`

| Campo | Descrição |
|-------|-----------|
| `id` | Identificador do mapa |
| `width/height` | Dimensões em pixels |
| `is_safe` | Se true, mobs não podem atacar jogadores |
| `music` | Identificador da trilha sonora |
| `spawn_points` | Lista de spawns: `{mob_id, count, respawn_seconds, area}` |
| `portals` | Teleportes: `{dest_map, dest_x, dest_y, trigger_x, trigger_y, radius}` |

**Mapas existentes:**

| ID | Nome | Tamanho | Mobs |
|----|------|---------|------|
| `starter_village` | Vila Inicial | 800×600 | Nenhum (zona segura) |
| `greenfield_plains` | Planícies de Greenfield | 1200×900 | 8 Porings (30s) + 5 Fabres (45s) |

### `monsters.json`

| Campo | Descrição |
|-------|-----------|
| `hp_max, base_xp, job_xp` | Valores base |
| `str, agi, vit, int_, dex, luk` | Atributos |
| `attack_min/max` | Range de dano |
| `move_speed` | Pixels por segundo |
| `attack_range` | Distância de ataque em pixels |
| `aggro_range` | Raio de detecção de jogadores (0 = passivo) |
| `ai_type` | `passive` ou `aggressive` |
| `drops` | `[{item_id, chance}]` |

**Monstros existentes:**

| ID | Nome | HP | XP | Tipo | Aggro range |
|----|------|----|----|------|------------|
| `poring` | Poring | 50 | 2 | Passivo | 0 |
| `fabre` | Fabre | 80 | 4 | Agressivo | 90px |

### `items.json`

Três tipos de itens:

| Tipo | Stackable | Tem equip_slot | Pode refinar |
|------|-----------|----------------|-------------|
| Material | Sim | Não | Não |
| Consumable | Sim | Não | Não |
| Equipment | Não | Sim | Sim (se slot correto) |
| Card | Sim | Não | Não |

### `classes.json`

| ID | Tier | Evolui de | Evolui para |
|----|------|-----------|------------|
| novice | 0 | — | warrior, mage, archer, acolyte, merchant, thief |
| warrior | 1 | novice | — |
| mage | 1 | novice | — |
| archer | 1 | novice | — |
| acolyte | 1 | novice | — |
| merchant | 1 | novice | — |
| thief | 1 | novice | — |

Todos exigem **nível 10** para evoluir do Novice.

### Limite de personagens

Máximo de **9 personagens por conta**. Novos personagens só podem ser criados como `novice`.

---

## 11. Cliente Godot 4

### Configuração do projeto (`project.godot`)

- Motor: Godot 4.2
- Cena principal: `res://scenes/main_menu.tscn`
- **Autoloads (singletons):**

| Nome | Arquivo | Responsabilidade |
|------|---------|-----------------|
| `GameState` | `scripts/systems/game_state.gd` | Token JWT, dados do player e personagem selecionado |
| `CharacterData` | `scripts/systems/character_data.gd` | Cache local de HP/SP/XP/zeny com signals |
| `MapManager` | `scripts/systems/map_manager.gd` | Mapa atual, signal `map_changed` |
| `ApiClient` | `scripts/network/api_client.gd` | HTTP REST (wrapper de HTTPRequest) |
| `WsClient` | `scripts/network/ws_client.gd` | Conexão WebSocket com reconexão automática |

- **Inputs mapeados:**
  - `attack` → clique esquerdo do mouse
  - `inventory` → tecla `I`
  - `chat_focus` → tecla `Enter`

### Estrutura de cenas

```
scenes/
├── main_menu.tscn          → scripts/ui/main_menu.gd
├── character_select.tscn   → scripts/ui/character_select.gd
├── game_world.tscn         → scripts/ui/game_world.gd
└── ui/
    ├── hud.tscn            → scripts/ui/hud.gd
    ├── chat.tscn           → scripts/ui/chat.gd
    └── inventory_ui.tscn   → scripts/ui/inventory_ui.gd
```

A cena `game_world.tscn` embute `hud.tscn`, `chat.tscn` e `inventory_ui.tscn` como filhos de um `CanvasLayer`.

### `GameState` (singleton)

```gdscript
var token: String       # JWT
var player_id: String   # UUID do player
var character: Dictionary  # dados completos do personagem selecionado
```

### `CharacterData` (singleton)

Mantém cache local dos atributos em combate e emite signals para a HUD atualizar sem polling:

```gdscript
signal hp_changed(current, maximum)
signal sp_changed(current, maximum)
signal xp_changed(current, to_next)
signal level_changed(new_level)
signal zeny_changed(amount)

func init_from_character(char: Dictionary)  # chamado ao entrar no jogo
func apply_damage(new_hp, new_max_hp)
func apply_xp(new_xp, new_xp_to_next)
func apply_level_up(new_level, stat_pts, skill_pts)
func apply_zeny(new_zeny)
```

### `ApiClient` (singleton)

```gdscript
const BASE_URL = "http://donaodete.local:7080"

func post(path, body, callback)
func get_req(path, callback)
func put(path, body, callback)
```

Cria um `HTTPRequest` node temporário por requisição (add_child → queue_free após resposta). O callback recebe `(code: int, data: Variant)`.

### `WsClient` (singleton)

```gdscript
const WS_URL = "ws://donaodete.local:7080/ws"
const RECONNECT_DELAY = 3.0  # segundos

signal message_received(type: String, payload: Dictionary)
signal ws_connected     # emitido após AUTH_OK
signal ws_disconnected

func authenticate(character_id: String)  # conecta e envia AUTH
func send(data: Dictionary)
func disconnect_ws()
```

Reconexão automática: se a conexão cair e `_should_reconnect` for true, tenta reconectar após 3 segundos. A autenticação é reenviada automaticamente quando o socket abre.

### Fluxo de telas

```
main_menu.tscn
  ├── Aba "Login" → POST /api/auth/login → GameState.token = ... → character_select.tscn
  └── Aba "Registro" → POST /api/auth/register → character_select.tscn

character_select.tscn
  ├── GET /api/characters → grade 3×3 de personagens (máx 9)
  ├── Botão "Jogar" → WsClient.authenticate(char_id)
  │                 → await WsClient.ws_connected
  │                 → game_world.tscn
  ├── Botão "Novo personagem" → painel flutuante → POST /api/characters
  └── Botão "< Voltar" → main_menu.tscn

game_world.tscn
  ├── Click esquerdo → move personagem (click-to-move)
  ├── Click esquerdo + tecla attack → ataca mob mais próximo (80px)
  ├── Click direito → tenta pegar drop mais próximo (60px)
  ├── Tecla I → abre/fecha inventário
  └── Desconexão WS → main_menu.tscn
```

### `game_world.gd` — Renderização

Todos os elementos visuais são construídos com primitivos (sem assets externos):

| Elemento | Visual |
|----------|--------|
| Jogador local | `ColorRect` ciano 16×24px + label com nome |
| Jogadores remotos | `ColorRect` branco 16×24px + label com nome |
| Mobs | `ColorRect` vermelho 16×16px + label com nome |
| Drops | `ColorRect` amarelo 8×8px |
| Número de dano | Label com tween de subida + fade out |

Layers de renderização (ordem z):
1. `Drops` (fundo)
2. `Mobs`
3. `Players` (frente)

### HUD (`hud.gd`)

Barras na cantos superior-esquerdo, conectadas aos signals de `CharacterData`:
- HP (vermelho) — `hp_changed`
- SP (azul) — `sp_changed`
- XP (amarelo) — `xp_changed`
- Nível e zeny como Labels

Notificações flutuantes centralizadas com fade automático de 2.8s.

### Chat (`chat.gd`)

- 3 canais: **Mapa** (local), **Global**, **Party**
- BBCode colorido por canal:
  - Mapa: branco | Global: verde | Party: azul | Sistema: amarelo
- Histórico limitado a 200 linhas (auto-trim)
- Envia mensagem com `CHAT` via WsClient

### Inventário (`inventory_ui.gd`)

- Grid 5 colunas com botões por item
- Painel de detalhe ao clicar: nome, quantidade, slot, refinamento, status equipado
- Ações disponíveis conforme tipo e estado do item: Equipar / Desequipar / Refinar
- Recarrega automaticamente ao receber `DROP_TAKEN` ou `LEVEL_UP` via WS

---

## 12. Como Rodar

### Pré-requisitos

- Docker + Docker Compose no host (DonaOdete)
- Godot 4.2 na máquina do desenvolvedor (para o cliente)

### Primeira vez

```bash
# 1. Copiar e preencher as credenciais
cp .env.example .env
nano .env

# 2. Subir a infraestrutura
cd /home/claude-monitor/mmorpg
docker compose up -d

# 3. Aplicar as migrations do banco de dados
docker compose exec game-server alembic upgrade head

# 4. Verificar que tudo está saudável
docker compose ps
curl http://localhost:7080/api/health
```

### Desenvolvimento (hot reload)

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

A pasta `./server` é montada dentro do container. Basta salvar um arquivo Python para o uvicorn recarregar.

### Cliente

1. Abrir a pasta `client/` no Godot 4.2
2. Verificar que `api_client.gd` e `ws_client.gd` apontam para o host correto (`donaodete.local:7080`)
3. Rodar no editor ou exportar para Windows/macOS

### Logs

```bash
# Logs do servidor
docker compose logs -f game-server

# Logs do Traefik
docker compose logs -f traefik-game
```

### Parar

```bash
docker compose down          # para os containers
docker compose down -v       # para e apaga volumes (CUIDADO: apaga o banco)
```

---

## 13. Backlog

Ver `TODO.md` para a lista completa. Resumo dos itens adiados:

- **Refinamento avançado:** nível além de +7, revisão dos percentuais
- **Guilds e War of Territory**
- **PvP**
- **Crafting**
- **Void Gauge e classes secretas** (usa dados de `aptitude_data`)
- **Raids**
- **Mercado de jogadores**
- **Sprites e TileMap reais** (substituir primitivos do cliente)
- **Sons e música**
- **Testes automatizados**
