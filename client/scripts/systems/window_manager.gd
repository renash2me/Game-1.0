extends RefCounted
class_name WindowManager

# Snap/clamp centralizado para todos os painéis flutuantes.
# Usa Engine.set_meta para manter o array de painéis sem depender de static var
# (compatível com Godot 4.0+; static var só existe a partir do 4.1).

const SNAP_DIST : float = 16.0
const SIZE_SNAP : float = 8.0
const MIN_TITLE : float = 26.0

const _META_KEY := "_wm_panels"

# ── Registro ──────────────────────────────────────────────────────────────────

static func register(panel: PanelContainer) -> void:
	var arr := _panels()
	if panel not in arr:
		arr.append(panel)

static func unregister(panel: PanelContainer) -> void:
	_panels().erase(panel)

# ── Snap de posição (arrastar) ────────────────────────────────────────────────

static func snap_move(moving: PanelContainer, raw: Vector2) -> Vector2:
	_clean()
	var arr := _panels()
	var vp  := _vp()
	var sz  := moving.size
	var pos := raw

	pos.x = clamp(pos.x, 0.0, max(0.0, vp.x - 40.0))
	pos.y = clamp(pos.y, 0.0, max(0.0, vp.y - MIN_TITLE))

	pos.x = _s(pos.x, 0.0,         SNAP_DIST)
	pos.y = _s(pos.y, 0.0,         SNAP_DIST)
	pos.x = _s(pos.x, vp.x - sz.x, SNAP_DIST)
	pos.y = _s(pos.y, vp.y - sz.y, SNAP_DIST)

	for p in arr:
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

static func _panels() -> Array:
	if not Engine.has_meta(_META_KEY):
		Engine.set_meta(_META_KEY, [])
	return Engine.get_meta(_META_KEY)

static func _s(val: float, target: float, dist: float) -> float:
	return target if absf(val - target) < dist else val

static func _clean() -> void:
	var arr := _panels()
	var i := arr.size() - 1
	while i >= 0:
		if not is_instance_valid(arr[i]):
			arr.remove_at(i)
		i -= 1

static func _vp() -> Vector2:
	return Vector2(DisplayServer.window_get_size())
