"""Deterministic make/model/color equivalence used to grade what a recognizer *saw*.

Used to split pipeline errors into misreads (TrafficEye / LLM extraction got the car
wrong) vs comparison failures (the car was read correctly but the match decision was wrong).
"""

from __future__ import annotations

import re

MAKE_ALIASES = {"vw": "volkswagen", "mercedes": "mercedesbenz", "chevy": "chevrolet"}

# Same vehicle sold under a different name in other markets; TrafficEye often returns the
# European name. Each set lists normalized names that refer to one model line.
REGIONAL_MODELS = [
    {"forte", "cerato"},
    {"crosstrek", "xv"},
    {"fusion", "mondeo"},
    {"rogue", "xtrail"},
    {"tucson", "ix35"},
    {"escape", "kuga"},
    {"qx56", "qx80"},
    {"elantratouring", "i30"},
    {"aerio", "liana"},
    {"sonic", "aveo"},
    {"optima", "k5"},
    {"elantra", "avante"},
]

# Distinct models whose names contain one another; containment must not equate them.
NEVER_MATCH = [
    {"cherokee", "grandcherokee"},
]

COLOR_WORDS = {
    "white": "white",
    "black": "black",
    "silver": "gray",
    "gray": "gray",
    "grey": "gray",
    "charcoal": "gray",
    "red": "red",
    "maroon": "red",
    "burgundy": "red",
    "blue": "blue",
    "navy": "blue",
    "green": "green",
    "brown": "brown",
    "beige": "brown",
    "tan": "brown",
    "gold": "brown",
    "champagne": "brown",
    "yellow": "yellow",
    "orange": "orange",
    "purple": "purple",
}


def norm(s: str | None) -> str:
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def make_eq(a: str | None, b: str | None) -> bool:
    na, nb = norm(a), norm(b)
    return bool(na and nb) and MAKE_ALIASES.get(na, na) == MAKE_ALIASES.get(nb, nb)


def _strip_make(model: str, makes: tuple[str | None, ...]) -> str:
    """'mazda3' -> '3' so it compares equal to TrafficEye's bare '3'."""
    for make in makes:
        nm = norm(make)
        if nm and model.startswith(nm) and len(model) > len(nm):
            return model[len(nm) :]
    return model


def model_eq(a: str | None, b: str | None, *makes: str | None) -> bool:
    """Equal if one normalized name contains the other ("Silverado" vs "Silverado 1500") or
    they are regional names for the same model. A leading make ("Mazda3") is ignored."""
    na, nb = _strip_make(norm(a), makes), _strip_make(norm(b), makes)
    if not (na and nb):
        return False
    if na != nb and {na, nb} in NEVER_MATCH:
        return False
    if na == nb or (min(len(na), len(nb)) > 1 and (na in nb or nb in na)):
        return True
    if na.startswith(nb) or nb.startswith(na):  # BMW "3" vs "3 Series"
        return True
    return any(
        any(x in na for x in group) and any(x in nb for x in group)
        for group in REGIONAL_MODELS
    )


def color_group(s: str | None) -> str | None:
    for word in re.findall(r"[a-z]+", (s or "").lower()):
        if word in COLOR_WORDS:
            return COLOR_WORDS[word]
    return None


def color_eq(label: str | None, seen: str | None) -> bool | None:
    """None when either color is unknown; beige/gold may also read as YELLOW."""
    gl, gs = color_group(label), color_group(seen)
    if gl is None or gs is None:
        return None
    return gl == gs or (
        gl == "brown" and gs == "yellow" and norm(label) in {"beige", "gold", "tan"}
    )


def model_alternatives(model: str | None) -> list[str]:
    """TrafficEye returns lookalike groups like 'Golf ~ Jetta'; split them into options."""
    return [m.strip() for m in (model or "").split("~") if m.strip()]


def is_ambiguous(seen: dict) -> bool:
    return len(model_alternatives(seen.get("model"))) > 1


def mentioned_agree(seen: dict, described: dict) -> bool:
    """Do the seen attributes agree with every attribute the description mentions?
    `described` values are None for attributes the description doesn't mention.
    For a '~' group, the model agrees if any option matches."""
    if described.get("make") and not make_eq(seen.get("make"), described["make"]):
        return False
    makes = (described.get("make"), seen.get("make"))
    if described.get("model") and not any(
        model_eq(alt, described["model"], *makes)
        for alt in model_alternatives(seen.get("model"))
    ):
        return False
    if (
        described.get("color")
        and color_eq(described["color"], seen.get("color")) is False
    ):
        return False
    return True
