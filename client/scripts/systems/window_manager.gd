extends RefCounted
class_name WindowManager

# Snap/clamp centralizado para todos os painéis flutuantes.
# Sem autoload — acesso via WindowManager.metodo() por causa do class_name.

const SNAP_DIST : float = 16.0   # px para ativar snap
const SIZE_SNAP : float = 8.0    # grid de snap ao soltar resize
const MIN_TITLE : float = 26.0   # px mínimos da barra de título visíveis

static var _panels : Array = []  # PanelContainers registrados

# ── Registro ──────────────────────────────────────────────────────────────────

static func register(panel: PanelContainer) -> void:
	if panel not in _panels:
		_panels.append(panel)

static func unregister(panel: PanelContainer) -> void:
	_panels.erase(panel)

# ── Snap de posição (arrastar) ────────────────────────────────────────────────

static func snap_move(moving: PanelContainer, raw: Vector2) -> Vector2:
	_clean()
	var vp  := _vp()
	var sz  := moving.size
	var pos := raw

	# Clamp — barra de título sempre visível
	pos.x = clamp(pos.x, 0.0, max(0.0, vp.x - 40.0))
	pos.y = clamp(pos.y, 0.0, max(0.0, vp.y - MIN_TITLE))

	# Snap bordas da viewport
	pos.x = _s(pos.x, 0.0,         SNAP_DIST)
	pos.y = _s(pos.y, 0.0,         SNAP_DIST)
	pos.x = _s(pos.x, vp.x - sz.x, SNAP_DIST)
	pos.y = _s(pos.y, vp.y - sz.y, SNAP_DIST)

	# Snap bordas dos outros painéis visíveis
	for p in _panels:
		if p == moving or not p.is_visible_in_tree():
			continue
		var op  := p.position
		var osz := p.size
		pos.x = _s(pos.x, op.x,         SNAP_DIST)
		pos.x = _s(pos.x, op.x - sz.x,  SNAP_DIST)
		pos.x = _s(pos.x, op.x + osz.x, SNAP_DIST)
		pos.y = _s(pos.y, op.y,         SNAP_DIST)
		pos.y = _s(pos.y, op.y - sz.y,  SNAP_DIST)
		pos.y = _s(pos.y, op.y + osz.y, SNAP_DIST)

	return pos

# ── Snap de tamanho (soltar resize) ──────────────────────────────────────────

static func snap_size(sz: Vector2, min_sz: Vector2) -> Vector2:
	return Vector2(
		max(roundf(sz.x / SIZE_SNAP) * SIZE_SNAP, min_sz.x),
		max(roundf(sz.y / SIZE_SNAP) * SIZE_SNAP, min_sz.y)
	)

# ── Internos ──────────────────────────────────────────────────────────────────

static func _s(val: float, target: float, dist: float) -> float:
	return target if absf(val - target) < dist else val

static func _clean() -> void:
	var valid : Array = []
	for p in _panels:
		if is_instance_valid(p):
			valid.append(p)
	_panels = valid

static func _vp() -> Vector2:
	return Vector2(DisplayServer.window_get_size())
