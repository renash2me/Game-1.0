"""Motor de fórmulas de atributos derivados.

As fórmulas ficam em data/formulas.json e são editáveis pelo admin. Cada uma é
uma expressão matemática avaliada com segurança (via AST — NÃO usamos eval()),
recebendo os atributos do personagem como variáveis.

Variáveis disponíveis: level, str, agi, vit, int, dex, luk
Funções permitidas: min, max, abs, round, floor, ceil, sqrt, pow
Operadores: + - * / // % **, unário -, comparações e ternário (a if cond else b).
"""
import ast
import math
import operator

import structlog

from app.data.loader import get_formulas

logger = structlog.get_logger()

_ALLOWED_FUNCS = {
    "min": min, "max": max, "abs": abs, "round": round,
    "floor": math.floor, "ceil": math.ceil, "sqrt": math.sqrt, "pow": pow,
}

_BIN_OPS = {
    ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
    ast.Div: operator.truediv, ast.FloorDiv: operator.floordiv,
    ast.Mod: operator.mod, ast.Pow: operator.pow,
}

_CMP_OPS = {
    ast.Lt: operator.lt, ast.LtE: operator.le, ast.Gt: operator.gt,
    ast.GtE: operator.ge, ast.Eq: operator.eq, ast.NotEq: operator.ne,
}


def _eval(node, env: dict):
    if isinstance(node, ast.Expression):
        return _eval(node.body, env)
    if isinstance(node, ast.Constant):
        if isinstance(node.value, (int, float)) and not isinstance(node.value, bool):
            return node.value
        raise ValueError("constante não permitida")
    if isinstance(node, ast.Name):
        if node.id in env:
            return env[node.id]
        raise ValueError(f"variável desconhecida: {node.id}")
    if isinstance(node, ast.BinOp):
        op = _BIN_OPS.get(type(node.op))
        if op is None:
            raise ValueError("operador não permitido")
        left = _eval(node.left, env)
        right = _eval(node.right, env)
        if op in (operator.truediv, operator.floordiv, operator.mod) and right == 0:
            return 0
        return op(left, right)
    if isinstance(node, ast.UnaryOp):
        val = _eval(node.operand, env)
        if isinstance(node.op, ast.USub):
            return -val
        if isinstance(node.op, ast.UAdd):
            return +val
        raise ValueError("operador unário não permitido")
    if isinstance(node, ast.Call):
        if not isinstance(node.func, ast.Name) or node.func.id not in _ALLOWED_FUNCS:
            raise ValueError("função não permitida")
        args = [_eval(a, env) for a in node.args]
        return _ALLOWED_FUNCS[node.func.id](*args)
    if isinstance(node, ast.IfExp):
        return _eval(node.body, env) if _eval(node.test, env) else _eval(node.orelse, env)
    if isinstance(node, ast.Compare):
        left = _eval(node.left, env)
        for op_node, comparator in zip(node.ops, node.comparators):
            cmp = _CMP_OPS.get(type(op_node))
            if cmp is None:
                raise ValueError("comparação não permitida")
            right = _eval(comparator, env)
            if not cmp(left, right):
                return False
            left = right
        return True
    if isinstance(node, ast.BoolOp):
        vals = [_eval(v, env) for v in node.values]
        if isinstance(node.op, ast.And):
            return all(vals)
        if isinstance(node.op, ast.Or):
            return any(vals)
    raise ValueError("expressão não permitida")


def eval_formula(expr: str, env: dict) -> float:
    """Avalia uma expressão com segurança. Em caso de erro, retorna 0."""
    try:
        tree = ast.parse(expr, mode="eval")
        result = _eval(tree, env)
        return float(result)
    except Exception as e:
        logger.warning("formula_eval_error", expr=expr, error=str(e))
        return 0.0


def _env(level: int, str_: int, agi: int, vit: int, int_: int, dex: int, luk: int) -> dict:
    return {
        "level": level, "str": str_, "agi": agi, "vit": vit,
        "int": int_, "dex": dex, "luk": luk,
    }


def derive_stats(
    level: int = 1, str_: int = 1, agi: int = 1, vit: int = 1,
    int_: int = 1, dex: int = 1, luk: int = 1,
) -> dict:
    """Calcula TODOS os atributos derivados a partir dos atributos base.

    As fórmulas podem referenciar outros atributos derivados (ex.: hp_regen usa
    max_hp, que usa base_hp). Resolvemos isso em múltiplos passes: os ids
    derivados começam em 0 e são reavaliados até estabilizar."""
    base = _env(level, str_, agi, vit, int_, dex, luk)
    formulas = get_formulas()
    results: dict = {fid: 0.0 for fid in formulas}
    for _ in range(5):
        changed = False
        for fid, formula in formulas.items():
            val = eval_formula(formula.get("expr", "0"), {**base, **results})
            if results.get(fid) != val:
                results[fid] = val
                changed = True
        if not changed:
            break
    return results


def apply_derived(character) -> None:
    """Recalcula hp_max/sp_max de um Character (ORM) pelas fórmulas e mantém
    hp/sp dentro do novo teto. Não cura — apenas limita o atual ao máximo."""
    d = derive_stats(
        level=character.level, str_=character.str_stat, agi=character.agi,
        vit=character.vit, int_=character.int_stat, dex=character.dex, luk=character.luk,
    )
    if "max_hp" in d:
        character.hp_max = max(1, int(d["max_hp"]))
        character.hp = min(character.hp, character.hp_max)
    if "max_sp" in d:
        character.sp_max = max(1, int(d["max_sp"]))
        character.sp = min(character.sp, character.sp_max)
