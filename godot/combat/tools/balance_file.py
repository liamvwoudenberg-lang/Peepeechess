"""Shared helpers for tools that rewrite ONE top-level block of config/balance.json and nothing else.

`replace_block(text, key, new_block)` finds the top-level `"key": { ... }` block (string- and nesting-aware, so braces inside
strings or other blocks never confuse it) and swaps only that text. Every other block, comment key and byte stays as it was, so
blocks that sit after it (e.g. "hit_stun") are never dropped. `render_edge_block(...)` writes attacker_edge in the compact matrix
form the loader reads (one attacker row per line).
"""
import json

ROLES = "pnbrq"
DEFAULT_PATH = "godot/config/balance.json"


def find_block(text: str, key: str):
    """Returns (start, end) of the `\t"key": {...}` block at top level (end is just after the closing brace), or None."""
    marker = f'\t"{key}": {{'
    start = text.find("\n" + marker)
    if start < 0:
        if not text.startswith(marker):
            return None
        start = 0
    else:
        start += 1
    depth, i, in_str, esc = 0, start + len(marker) - 1, False, False
    while i < len(text):
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return start, i + 1
        i += 1
    raise ValueError(f'unterminated block "{key}"')


def replace_block(text: str, key: str, new_block: str) -> str:
    """Swaps the top-level block `key` for `new_block` (which must start with a tab and `"key": {` and end with `}`)."""
    found = find_block(text, key)
    if found is None:
        # append before the final closing brace, keeping everything else untouched
        body = text.rstrip()
        assert body.endswith("}"), "unexpected end of file"
        out = body[:-1].rstrip() + ",\n" + new_block + "\n}\n"
    else:
        start, end = found
        out = text[:start] + new_block + text[end:]
    json.loads(out)  # the result must stay valid JSON
    return out


def num(v: float) -> str:
    return f"{v:.2f}".rstrip("0").rstrip(".") if v != 1 else "1.0"


def render_edge_block(target, stamina, pairs: dict) -> str:
    """attacker_edge in matrix form: matrix[attacker_role][defender_role] = [attacker_mult, defender_mult]."""
    lines = ['\t"attacker_edge": {', f'\t\t"target": {target},',
             '\t\t"stamina": {',
             f'\t\t\t"attacker_cost": {num(stamina[0]) if stamina[0] else "0.0"},',
             f'\t\t\t"defender_cost": {num(stamina[1])},',
             f'\t\t\t"defender_regen": {num(stamina[2])}',
             '\t\t},',
             '\t\t"_matrix": "rows = the ATTACKING role, columns = the DEFENDING role; each cell is [attacker damage x, defender damage x]; at most one side is boosted",',
             '\t\t"matrix": {']
    for ri, a in enumerate(ROLES):
        cells = []
        for d in ROLES:
            p = pairs[a + d]
            am, dm = max(1.0, p["attacker_mult"]), max(1.0, p["defender_mult"])
            if am > 1.0001 and dm > 1.0001:
                am, dm = (am, 1.0) if am >= dm else (1.0, dm)
            cells.append(f'"{d}": [{num(am)}, {num(dm)}]')
        lines.append(f'\t\t\t"{a}": {{{", ".join(cells)}}}' + ("," if ri < len(ROLES) - 1 else ""))
    lines += ["\t\t}", "\t}"]
    return "\n".join(lines)
