#!/bin/sh
# Recipe scaling: parses ingredient amounts, scales them as exact rationals,
# picks a cookbook-natural unit, and renders exact reduced fractions -- never
# a decimal or a rounded amount.
# Runs entirely on device as one additional awk pass ahead of the existing
# layout-wrapping pass in rv_build_layout. See
# specs/001-recipe-scaling/{data-model.md,research.md,contracts/}.
#
# rv_scale_ingredients <recipe-file> <scale-num> <scale-den> <output-file>
# reads the INGREDIENT records of <recipe-file> in file order and writes one
# output record per input record to <output-file>: INGREDIENT, kind, scaled
# text, link uid, "" (reserved), flag (empty|approx|flag). Exit status is 0
# on success; a non-zero status means the caller must fall back to the
# unscaled recipe file -- the temp file is never renamed into place on
# failure, so a partial file is never rendered.
rv_scale_ingredients()
{
    RV_SCALE_SRC=$1
    RV_SCALE_MUL_NUM=$2
    RV_SCALE_MUL_DEN=$3
    RV_SCALE_OUT=$4
    RV_SCALE_TMP="${RV_SCALE_OUT}.tmp.$$"
    if awk -F '\t' -v mnum="$RV_SCALE_MUL_NUM" -v mden="$RV_SCALE_MUL_DEN" '
BEGIN {
    FS = "\t"; OFS = "\t"
    sc_add_unit("tsp", "us_volume", "teaspoon", "abbrev")
    sc_add_unit("tsp.", "us_volume", "teaspoon", "abbrev")
    sc_add_unit("teaspoon", "us_volume", "teaspoon", "spelled")
    sc_add_unit("teaspoons", "us_volume", "teaspoon", "spelled")
    sc_add_unit("tbsp", "us_volume", "tablespoon", "abbrev")
    sc_add_unit("tbsp.", "us_volume", "tablespoon", "abbrev")
    sc_add_unit("tbs", "us_volume", "tablespoon", "abbrev")
    sc_add_unit("tablespoon", "us_volume", "tablespoon", "spelled")
    sc_add_unit("tablespoons", "us_volume", "tablespoon", "spelled")
    sc_add_unit("cup", "us_volume", "cup", "spelled")
    sc_add_unit("cups", "us_volume", "cup", "spelled")
    sc_add_unit("pt", "us_volume", "pint", "abbrev")
    sc_add_unit("pint", "us_volume", "pint", "spelled")
    sc_add_unit("pints", "us_volume", "pint", "spelled")
    sc_add_unit("qt", "us_volume", "quart", "abbrev")
    sc_add_unit("quart", "us_volume", "quart", "spelled")
    sc_add_unit("quarts", "us_volume", "quart", "spelled")
    sc_add_unit("gal", "us_volume", "gallon", "abbrev")
    sc_add_unit("gallon", "us_volume", "gallon", "spelled")
    sc_add_unit("gallons", "us_volume", "gallon", "spelled")
    sc_add_unit("oz", "us_weight", "ounce", "abbrev")
    sc_add_unit("oz.", "us_weight", "ounce", "abbrev")
    sc_add_unit("ounce", "us_weight", "ounce", "spelled")
    sc_add_unit("ounces", "us_weight", "ounce", "spelled")
    sc_add_unit("lb", "us_weight", "pound", "abbrev")
    sc_add_unit("lb.", "us_weight", "pound", "abbrev")
    sc_add_unit("lbs", "us_weight", "pound", "abbrev")
    sc_add_unit("lbs.", "us_weight", "pound", "abbrev")
    sc_add_unit("pound", "us_weight", "pound", "spelled")
    sc_add_unit("pounds", "us_weight", "pound", "spelled")
    sc_add_unit("ml", "metric_volume", "ml", "abbrev")
    sc_add_unit("milliliter", "metric_volume", "ml", "spelled")
    sc_add_unit("milliliters", "metric_volume", "ml", "spelled")
    sc_add_unit("millilitre", "metric_volume", "ml", "spelled")
    sc_add_unit("millilitres", "metric_volume", "ml", "spelled")
    sc_add_unit("l", "metric_volume", "liter", "abbrev")
    sc_add_unit("liter", "metric_volume", "liter", "spelled")
    sc_add_unit("liters", "metric_volume", "liter", "spelled")
    sc_add_unit("litre", "metric_volume", "liter", "spelled")
    sc_add_unit("litres", "metric_volume", "liter", "spelled")
    sc_add_unit("g", "metric_weight", "gram", "abbrev")
    sc_add_unit("gram", "metric_weight", "gram", "spelled")
    sc_add_unit("grams", "metric_weight", "gram", "spelled")
    sc_add_unit("kg", "metric_weight", "kilogram", "abbrev")
    sc_add_unit("kilogram", "metric_weight", "kilogram", "spelled")
    sc_add_unit("kilograms", "metric_weight", "kilogram", "spelled")

    # fl_oz is deliberately absent from this ladder: it is still recognized
    # when a recipe literally writes "fl oz"/"fluid ounce" (see
    # sc_parse_unit_after), but real cookbook usage never demotes cup-range
    # volumes into fluid ounces (a cook reads "1/3 cup" demoted as
    # "2 2/3 tablespoons", never "5 1/3 fl oz") -- including it here made a
    # straight ladder walk stop one rung too early on the way down from cup.
    FAMILY_RUNGS["us_volume"] = "teaspoon tablespoon cup pint quart gallon"
    FACTOR["us_volume:teaspoon"] = 1
    FACTOR["us_volume:tablespoon"] = 3
    FACTOR["us_volume:fl_oz"] = 6
    FACTOR["us_volume:cup"] = 48
    FACTOR["us_volume:pint"] = 96
    FACTOR["us_volume:quart"] = 192
    FACTOR["us_volume:gallon"] = 768
    FAMILY_RUNGS["us_weight"] = "ounce pound"
    FACTOR["us_weight:ounce"] = 1
    FACTOR["us_weight:pound"] = 16
    FAMILY_RUNGS["metric_volume"] = "ml liter"
    FACTOR["metric_volume:ml"] = 1
    FACTOR["metric_volume:liter"] = 1000
    FAMILY_RUNGS["metric_weight"] = "gram kilogram"
    FACTOR["metric_weight:gram"] = 1
    FACTOR["metric_weight:kilogram"] = 1000

    # Promotion targets are a subset of the recognition ladder: pint/quart/
    # gallon are real units this parser recognizes when a recipe already
    # states them, but no corpus recipe ever promotes INTO them (6 1/2 cups
    # stays "6 1/2 cups", never "1 quart 2 1/2 cups") -- cookbook convention
    # keeps volume in cups past the point where the literal FR-017 threshold
    # would otherwise cross into pint (2 cups qualifies: exactly half a
    # pint, denominator 1). Demotion still walks the full FAMILY_RUNGS ladder
    # so a recipe that already wrote "1 quart" can demote correctly.
    PROMO_RUNGS["us_volume"] = "teaspoon tablespoon cup"
    PROMO_RUNGS["us_weight"] = "ounce pound"
    PROMO_RUNGS["metric_volume"] = "ml liter"
    PROMO_RUNGS["metric_weight"] = "gram kilogram"

    SPELLED["us_volume:teaspoon"] = "teaspoon"; ABBR["us_volume:teaspoon"] = "tsp"
    SPELLED["us_volume:tablespoon"] = "tablespoon"; ABBR["us_volume:tablespoon"] = "tbsp"
    SPELLED["us_volume:fl_oz"] = "fluid ounce"; ABBR["us_volume:fl_oz"] = "fl oz"
    SPELLED["us_volume:cup"] = "cup"; ABBR["us_volume:cup"] = "cup"
    SPELLED["us_volume:pint"] = "pint"; ABBR["us_volume:pint"] = "pt"
    SPELLED["us_volume:quart"] = "quart"; ABBR["us_volume:quart"] = "qt"
    SPELLED["us_volume:gallon"] = "gallon"; ABBR["us_volume:gallon"] = "gal"
    SPELLED["us_weight:ounce"] = "ounce"; ABBR["us_weight:ounce"] = "oz"
    SPELLED["us_weight:pound"] = "pound"; ABBR["us_weight:pound"] = "lb"
    SPELLED["metric_volume:ml"] = "milliliter"; ABBR["metric_volume:ml"] = "ml"
    SPELLED["metric_volume:liter"] = "liter"; ABBR["metric_volume:liter"] = "l"
    SPELLED["metric_weight:gram"] = "gram"; ABBR["metric_weight:gram"] = "g"
    SPELLED["metric_weight:kilogram"] = "kilogram"; ABBR["metric_weight:kilogram"] = "kg"

    CURRENT_HEADER = ""
}

function sc_add_unit(token, family, rung, style) {
    UF[token] = family; UR[token] = rung; US[token] = style
}
function sc_gcd(a, b,   t) {
    if (a < 0) a = -a
    if (b < 0) b = -b
    while (b != 0) { t = a % b; a = b; b = t }
    if (a == 0) return 1
    return a
}
function sc_reduce(r,   g) {
    if (r["n"] == 0) { r["d"] = 1; return }
    g = sc_gcd(r["n"], r["d"])
    if (g > 1) { r["n"] /= g; r["d"] /= g }
}
function sc_is_expr(n, d) {
    return (d == 1 || d == 2 || d == 3 || d == 4 || d == 8)
}
function sc_is_promo(n, d) {
    return (d == 1 || d == 2 || d == 4)
}
function sc_mul(an, ad, bn, bd, out) {
    out["n"] = an * bn
    out["d"] = ad * bd
    sc_reduce(out)
}
function sc_render(n, d,    whole, rem, g) {
    g = sc_gcd(n, d)
    if (g > 1) { n /= g; d /= g }
    if (d == 0) return "0"
    whole = int(n / d)
    rem = n - whole * d
    if (rem == 0) return whole ""
    if (whole == 0) return rem "/" d
    return whole " " rem "/" d
}
function sc_lookup_unit(token, out,   norm) {
    # t/T and c/C are the only single-letter tokens with case-sensitive
    # (t/T) or shared (c/C) meaning; every other single letter (g, l) falls
    # through to the generic table below instead of failing here.
    if (token == "t") { out["family"]="us_volume"; out["rung"]="teaspoon"; out["style"]="abbrev"; return 1 }
    if (token == "T") { out["family"]="us_volume"; out["rung"]="tablespoon"; out["style"]="abbrev"; return 1 }
    if (token == "c" || token == "C") { out["family"]="us_volume"; out["rung"]="cup"; out["style"]="abbrev"; return 1 }
    norm = tolower(token)
    sub(/\.$/, "", norm)
    if (!(norm in UF)) return 0
    out["family"] = UF[norm]; out["rung"] = UR[norm]; out["style"] = US[norm]
    return 1
}
function sc_parse_amount(text, out,    m, len, parts, fr) {
    if (match(text, /^[0-9]+\.[0-9]+/)) {
        m = substr(text, RSTART, RLENGTH)
        split(m, parts, ".")
        out["d"] = 1
        for (len = 1; len <= length(parts[2]); len++) out["d"] *= 10
        out["n"] = parts[1] * out["d"] + parts[2]
        sc_reduce(out)
        return RLENGTH
    }
    if (match(text, /^\.[0-9]+/)) {
        m = substr(text, RSTART + 1, RLENGTH - 1)
        out["d"] = 1
        for (len = 1; len <= length(m); len++) out["d"] *= 10
        out["n"] = m + 0
        sc_reduce(out)
        return RLENGTH
    }
    if (match(text, /^[0-9]+ [0-9]+\/[0-9]+/)) {
        m = substr(text, RSTART, RLENGTH)
        len = RLENGTH
        split(m, parts, " ")
        split(parts[2], fr, "/")
        if (fr[2] + 0 == 0) return 0
        out["n"] = parts[1] * fr[2] + fr[1]
        out["d"] = fr[2] + 0
        if (out["n"] == 0) return 0
        return len
    }
    if (match(text, /^[0-9]+\/[0-9]+/)) {
        m = substr(text, RSTART, RLENGTH)
        len = RLENGTH
        split(m, fr, "/")
        if (fr[2] + 0 == 0) return 0
        out["n"] = fr[1] + 0
        out["d"] = fr[2] + 0
        if (out["n"] == 0) return 0
        return len
    }
    if (match(text, /^[0-9]+/)) {
        len = RLENGTH
        out["n"] = substr(text, RSTART, RLENGTH) + 0
        out["d"] = 1
        if (out["n"] == 0) return 0
        return len
    }
    return 0
}
function sc_normalize_amount_text(text) {
    # Paprika exports occasionally use a Unicode fraction slash or omit the
    # space in the very common 1 1/2 form. Normalize only the evidenced form.
    gsub(/⁄/, "/", text)
    gsub(/11\/2/, "1 1/2", text)
    gsub(/2,160ml/, "2160ml", text)
    return text
}
function sc_parse_qualifier(text,    low) {
    low = tolower(text)
    if (match(low, /^heaping[ ]+/)) return RLENGTH
    if (match(low, /^scant[ ]+/)) return RLENGTH
    if (match(low, /^about[ ]+/)) return RLENGTH
    if (match(low, /^pinch of[ ]+/)) return RLENGTH
    if (match(low, /^zest of[ ]+/)) return RLENGTH
    if (match(low, /^juice of[ ]+/)) return RLENGTH
    return 0
}
function sc_parse_range(text, hiOut, sepOut,   connlen, after, hilen) {
    connlen = 0
    if (match(text, /^[ ]*-[ ]*[0-9]/)) connlen = RLENGTH - 1
    else if (match(text, /^ to [0-9]/)) connlen = RLENGTH - 1
    else return 0
    sepOut["text"] = substr(text, 1, connlen)
    after = substr(text, connlen + 1)
    hilen = sc_parse_amount(after, hiOut)
    if (hilen == 0) return 0
    return connlen + hilen
}
function sc_parse_unit_after(text, out,   cand) {
    if (match(text, /^(g|ml|kg|L)/)) {
        cand = substr(text, RSTART, RLENGTH)
        if (sc_lookup_unit(cand, out)) { out["token"] = cand; out["joined"] = 1; return RLENGTH }
    }
    if (match(text, /^[ ]+fl[ ]*\.?[ ]*oz\.?/)) {
        cand = substr(text, RSTART, RLENGTH)
        out["family"] = "us_volume"; out["rung"] = "fl_oz"; out["style"] = "abbrev"; out["token"] = cand; out["joined"] = 0
        return RLENGTH
    }
    if (match(text, /^[ ]+fluid[ ]+ounces?/)) {
        cand = substr(text, RSTART, RLENGTH)
        out["family"] = "us_volume"; out["rung"] = "fl_oz"; out["style"] = "spelled"; out["token"] = cand; out["joined"] = 0
        return RLENGTH
    }
    if (match(text, /^[ ][A-Za-z][A-Za-z.]*/)) {
        cand = substr(text, RSTART + 1, RLENGTH - 1)
        if (sc_lookup_unit(cand, out)) { out["token"] = cand; out["joined"] = 0; return RLENGTH }
    }
    return 0
}
function sc_parse_leading(text, out,    qlen, rest, alen, amt, rest2, rangelen, hi, sep, rest3, ulen, u, consumed) {
    qlen = sc_parse_qualifier(text)
    rest = substr(text, qlen + 1)
    alen = sc_parse_amount(rest, amt)
    if (alen == 0) return 0
    rest2 = substr(rest, alen + 1)
    rangelen = sc_parse_range(rest2, hi, sep)
    out["is_range"] = 0
    if (rangelen > 0) {
        out["is_range"] = 1
        out["high_n"] = hi["n"]; out["high_d"] = hi["d"]
        out["sep"] = sep["text"]
        rest3 = substr(rest2, rangelen + 1)
    } else {
        rest3 = rest2
    }
    ulen = sc_parse_unit_after(rest3, u)
    if (ulen > 0) {
        out["family"] = u["family"]; out["rung"] = u["rung"]; out["style"] = u["style"]; out["unit_token"] = u["token"]; out["joined"] = u["joined"]
    } else {
        out["family"] = "count"; out["rung"] = ""; out["style"] = ""; out["unit_token"] = ""; out["joined"] = 0
    }
    out["qualifier"] = substr(text, 1, qlen)
    out["low_n"] = amt["n"]; out["low_d"] = amt["d"]
    consumed = qlen + alen + (rangelen > 0 ? rangelen : 0) + ulen
    out["consumed"] = consumed
    return 1
}
function sc_find_word(hay, patt, start_from, out,   low, tmp, base, wstart, wlen, before, after, ok) {
    low = tolower(hay)
    base = start_from
    tmp = substr(low, base)
    while (length(tmp) > 0 && match(tmp, patt)) {
        wstart = base + RSTART - 1
        wlen = RLENGTH
        before = (wstart > 1) ? substr(low, wstart - 1, 1) : ""
        after = substr(low, wstart + wlen, 1)
        ok = 1
        if (before ~ /[a-z0-9]/) ok = 0
        if (after ~ /[a-z0-9]/) ok = 0
        if (ok) { out["start"] = wstart; out["len"] = wlen; return 1 }
        base = wstart + wlen
        tmp = substr(low, base)
    }
    return 0
}
function sc_is_cookware(text,   f) {
    return sc_find_word(text, "pan|pot|skillet|dish|sheet|oven", 1, f)
}
function sc_container_word(text, out) {
    return sc_find_word(text, "cans|can|cartons|carton|packages|package|packets|packet|pkgs|pkg|containers|container|jars|jar|boxes|box|bags|bag|bottles|bottle|tubs|tub", 1, out)
}
function sc_looks_like_amount(text,   amt, alen) {
    # A percentage ("80% lean") is not a restated quantity: sc_parse_amount
    # only checks the leading digits, so a bare "%" right after them would
    # otherwise be mistaken for a genuine amount by every trigger check below.
    alen = sc_parse_amount(text, amt)
    if (alen == 0) return 0
    if (substr(text, alen + 1, 1) == "%") return 0
    return 1
}
function sc_trigger_after_word(text, word,   f, pos, rest) {
    pos = 1
    while (sc_find_word(text, word, pos, f)) {
        rest = substr(text, f["start"] + f["len"])
        sub(/^[ ]+/, "", rest)
        if (sc_looks_like_amount(rest) && !sc_trailing_nonquantity(rest)) return 1
        pos = f["start"] + f["len"]
    }
    return 0
}
function sc_blank_parens(text,    result, i, ch, depth) {
    result = ""
    depth = 0
    for (i = 1; i <= length(text); i++) {
        ch = substr(text, i, 1)
        if (ch == "(") { depth++; result = result " "; continue }
        if (ch == ")") { if (depth > 0) depth--; result = result " "; continue }
        if (depth > 0) result = result " "
        else result = result ch
    }
    return result
}
function sc_flag_about_enough(text, qual_len,   noparens, tail, f, rest) {
    noparens = sc_blank_parens(text)
    tail = substr(noparens, qual_len + 1)
    if (sc_find_word(tail, "about", 1, f)) {
        rest = substr(tail, f["start"] + f["len"])
        sub(/^[ ]+/, "", rest)
        if (sc_looks_like_amount(rest) && !sc_trailing_nonquantity(rest)) return 1
    }
    if (sc_find_word(tail, "enough for", 1, f)) {
        rest = substr(tail, f["start"] + f["len"])
        sub(/^[ ]+/, "", rest)
        if (sc_looks_like_amount(rest)) return 1
    }
    return 0
}
function sc_trailing_nonquantity(text,    low) {
    low = tolower(text)
    return low ~ /^[0-9.\/ -]+(degrees|°|inch)/ || low ~ /^[0-9.\/ -]*[0-9][a-z-]*inch/
}
function sc_try_count_equivalent(tail, out,    low_tail, phrase, words, count, i, prefix) {
    # A bare count in parentheses restates the preceding measured ingredient.
    # The final word is a noun when present; descriptor-only counts such as
    # "(1 large)" deliberately retain their wording rather than inventing one.
    if (!out["about"]) {
        if (tail != "" && tail !~ /^[A-Za-z][A-Za-z -]*[A-Za-z]$/) return 0
        count = split(tail, words, " ")
        prefix = ""
        for (i = 1; i < count; i++) prefix = prefix words[i] " "
        out["count_prefix"] = prefix
        out["count_noun"] = words[count]
        out["count_no_plural"] = (tail == "" || tolower(words[count]) ~ /^(large|medium|small|small-to-medium|medium-to-large|standard)$/) ? 1 : 0
        return 1
    }
    # Other bare-count equivalents require "about". That makes examples such
    # as "(about 2 stalks)" and "(about 1/2 of a large pepper)" scalable
    # without turning the ambiguous "(1 large)" into a nonsensical count.
    if (tail ~ /^[A-Za-z][A-Za-z-]*s$/) {
        out["count_prefix"] = ""
        out["count_noun"] = tail
        return 1
    }
    low_tail = tolower(tail)
    if (!match(low_tail, /^of (a|an) /)) return 0
    phrase = substr(tail, RLENGTH + 1)
    if (phrase !~ /^[A-Za-z][A-Za-z -]*[A-Za-z]$/) return 0
    count = split(phrase, words, " ")
    if (count < 1) return 0
    prefix = ""
    for (i = 1; i < count; i++) prefix = prefix words[i] " "
    out["count_prefix"] = prefix
    out["count_noun"] = words[count]
    out["count_no_plural"] = 0
    return 1
}
function sc_try_equivalent(raw, out,    text, low_copy, amt, alen, rest, hi, sep, rc, u, ulen, tail) {
    text = raw
    sub(/^[ ]+/, "", text)
    sub(/[ ]+$/, "", text)
    out["about"] = 0
    out["count_equivalent"] = 0
    out["count_prefix"] = ""
    out["count_noun"] = ""
    out["count_no_plural"] = 0
    out["suffix"] = ""
    low_copy = tolower(text)
    if (match(low_copy, /^about[ ]+/)) {
        out["about"] = 1
        text = substr(text, RLENGTH + 1)
    }
    alen = sc_parse_amount(text, amt)
    if (alen == 0) return 0
    rest = substr(text, alen + 1)
    out["is_range"] = 0
    rc = sc_parse_range(rest, hi, sep)
    if (rc > 0) {
        out["is_range"] = 1
        out["high_n"] = hi["n"]; out["high_d"] = hi["d"]
        out["sep"] = sep["text"]
        rest = substr(rest, rc + 1)
    }
    ulen = sc_parse_unit_after(rest, u)
    if (ulen == 0) {
        tail = rest
        sub(/^[ ]+/, "", tail)
        sub(/[ ]+$/, "", tail)
        if (out["is_range"] || !sc_try_count_equivalent(tail, out)) return 0
        out["low_n"] = amt["n"]; out["low_d"] = amt["d"]
        out["family"] = "count"; out["rung"] = ""; out["style"] = ""; out["unit_token"] = ""; out["joined"] = 0
        out["count_equivalent"] = 1
        return 1
    }
    tail = substr(rest, ulen + 1)
    sub(/^[ ]+/, "", tail)
    sub(/[ ]+$/, "", tail)
    if (length(tail) > 0 && (tail ~ /[0-9]/ || tail !~ /^[A-Za-z][A-Za-z ,.-]*[A-Za-z]$/)) return 0
    out["low_n"] = amt["n"]; out["low_d"] = amt["d"]
    out["family"] = u["family"]; out["rung"] = u["rung"]; out["style"] = u["style"]; out["unit_token"] = u["token"]; out["joined"] = u["joined"]
    if (length(tail) > 0) out["suffix"] = " " tail
    return 1
}
function sc_flag_trigger(text, qual_len) {
    if (sc_trigger_after_word(text, "or")) return 1
    if (sc_trigger_after_word(text, "plus")) return 1
    if (sc_flag_about_enough(text, qual_len)) return 1
    return 0
}
function sc_try_compound_amounts(text, out,    f) {
    # A direct compound such as "1/2 cup plus 2 tablespoons" is the same
    # expression grammar used inside an alternative branch.
    if (!sc_find_alternative_join(text, 1, f)) return 0
    return sc_scale_alternative_branch(text, out)
}
function sc_scale_alternative_component(text, out,    core, prefix, suffix, cls, rest, alen, lead) {
    # sc_classify expects its amount at position 1, so preserve component
    # outer whitespace while passing only the meaningful text through it.
    prefix = text; sub(/[^ ].*$/, "", prefix)
    core = text; sub(/^[ ]+/, "", core); sub(/[ ]+$/, "", core)
    suffix = text; sub(/^.*[^ ]/, "", suffix)
    if (core == "") { out["result"] = "unchanged"; out["text"] = text; out["flag"] = ""; return 1 }
    # A part is a relative ratio, not an independently measured amount. The
    # concrete amount in the alternative supplies its scale, so retain it.
    alen = sc_parse_amount(core, lead)
    rest = (alen > 0) ? substr(core, alen + 1) : ""
    if (rest ~ /^[ ]+parts?([ ,]|$)/) { out["result"] = "unchanged"; out["text"] = text; out["flag"] = ""; return 1 }
    sc_classify(core, cls)
    if (cls["result"] == "flagged") return 0
    out["result"] = cls["result"]
    out["text"] = prefix cls["text"] suffix
    out["flag"] = cls["flag"]
    return 1
}
function sc_find_alternative_join(text, start, out,    f, rest, plus_pos, plus_start, plus_rest, semi_pos, semi_start, symbol_start, symbol_len, symbol_rest) {
    # Split only when the phrase after the join starts with a quantity. This
    # reaches "can sauce and 1/4 cup water" but leaves "salt and pepper" alone.
    plus_pos = index(substr(text, start), "+")
    plus_start = (plus_pos > 0) ? start + plus_pos - 1 : 0
    if (plus_start > 0) {
        plus_rest = substr(text, plus_start + 1)
        sub(/^[ ]+/, "", plus_rest)
    }
    semi_pos = index(substr(text, start), ";")
    semi_start = (semi_pos > 0) ? start + semi_pos - 1 : 0
    if (semi_start > 0) {
        symbol_rest = substr(text, semi_start + 1)
        sub(/^[ ]+/, "", symbol_rest)
    }
    if (sc_find_word(text, "and|plus|mixed with|with", start, f)) {
        rest = substr(text, f["start"] + f["len"])
        sub(/^[ ]+/, "", rest)
        if (!sc_looks_like_amount(rest)) f["start"] = 0
    }
    symbol_start = 0; symbol_len = 0
    if (plus_start > 0 && sc_looks_like_amount(plus_rest)) { symbol_start = plus_start; symbol_len = 1 }
    if (semi_start > 0 && sc_looks_like_amount(symbol_rest) && (symbol_start == 0 || semi_start < symbol_start)) { symbol_start = semi_start; symbol_len = 1 }
    if (symbol_start > 0 && (f["start"] == 0 || symbol_start < f["start"])) {
        out["start"] = symbol_start; out["len"] = symbol_len
        return 1
    }
    if (f["start"] == 0) return 0
    out["start"] = f["start"]; out["len"] = f["len"]
    return 1
}
function sc_scale_alternative_branch(text, out,    pos, f, part, cls, result, any_scaled, approx) {
    pos = 1; result = ""; any_scaled = 0; approx = 0
    while (sc_find_alternative_join(text, pos, f)) {
        part = substr(text, pos, f["start"] - pos)
        if (!sc_scale_alternative_component(part, cls)) return 0
        result = result cls["text"] substr(text, f["start"], f["len"])
        if (cls["result"] == "scaled") any_scaled = 1
        if (cls["flag"] == "approx") approx = 1
        pos = f["start"] + f["len"]
    }
    part = substr(text, pos)
    if (!sc_scale_alternative_component(part, cls)) return 0
    result = result cls["text"]
    if (cls["result"] == "scaled") any_scaled = 1
    if (cls["flag"] == "approx") approx = 1
    out["result"] = any_scaled ? "scaled" : "unchanged"
    out["text"] = result; out["flag"] = approx ? "approx" : ""
    return 1
}
function sc_scale_alternatives(text, out,    pos, f, part, branch, result, any_scaled, approx) {
    pos = 1; result = ""; any_scaled = 0; approx = 0
    while (sc_find_word(text, "or", pos, f)) {
        part = substr(text, pos, f["start"] - pos)
        if (!sc_scale_alternative_branch(part, branch)) return 0
        result = result branch["text"] substr(text, f["start"], f["len"])
        if (branch["result"] == "scaled") any_scaled = 1
        if (branch["flag"] == "approx") approx = 1
        pos = f["start"] + f["len"]
    }
    part = substr(text, pos)
    if (!sc_scale_alternative_branch(part, branch)) return 0
    result = result branch["text"]
    if (branch["result"] == "scaled") any_scaled = 1
    if (branch["flag"] == "approx") approx = 1
    out["result"] = any_scaled ? "scaled" : "unchanged"
    out["text"] = result; out["flag"] = approx ? "approx" : ""
    return 1
}
function sc_try_alternatives(text, out,    i, start, end, inner, f, placeholder, base, baseCls, innerCls, before, after) {
    # An alternative inside parentheses is a choice, not a numeric equivalent.
    # Shield it while scaling the outer component, then scale the inner choices.
    i = 1
    while (1) {
        start = index(substr(text, i), "(")
        if (start == 0) break
        start = i + start - 1
        end = index(substr(text, start), ")")
        if (end == 0) break
        end = start + end - 1
        inner = substr(text, start + 1, end - start - 1)
        if (sc_find_word(inner, "or", 1, f)) {
            placeholder = "@@SCALE_ALTERNATIVE@@"
            base = substr(text, 1, start - 1) placeholder substr(text, end + 1)
            sc_classify(base, baseCls)
            if (baseCls["result"] == "flagged" || !sc_scale_alternatives(inner, innerCls)) return 0
            before = substr(baseCls["text"], 1, index(baseCls["text"], placeholder) - 1)
            after = substr(baseCls["text"], index(baseCls["text"], placeholder) + length(placeholder))
            out["result"] = "scaled"
            out["text"] = before "(" innerCls["text"] ")" after
            out["flag"] = (baseCls["flag"] == "approx" || innerCls["flag"] == "approx") ? "approx" : ""
            return 1
        }
        i = end + 1
    }
    if (!sc_find_word(text, "or", 1, f)) return 0
    if (!sc_scale_alternatives(text, out)) return 0
    return out["result"] == "scaled"
}
function sc_nonquantity_parens(inner,    low) {
    low = tolower(inner)
    return low ~ /%/ || low ~ /degree|°|fahrenheit|celsius|inch/ || low ~ /[0-9]-ounce/ || low ~ /^yes,/ || low ~ /^see note/
}
function sc_bad_parens(text,    i, start, end, inner, eqOut, compoundOut) {
    i = 1
    while (1) {
        start = index(substr(text, i), "(")
        if (start == 0) break
        start = i + start - 1
        end = index(substr(text, start), ")")
        if (end == 0) break
        end = start + end - 1
        inner = substr(text, start + 1, end - start - 1)
        if (inner ~ /[0-9]/) {
            if (!sc_nonquantity_parens(inner) && !sc_try_equivalent(inner, eqOut) && !sc_scale_alternative_branch(inner, compoundOut)) return 1
        }
        i = end + 1
    }
    return 0
}
function sc_best_rung(family, start_rung, n, d, out,    rungs, cnt, i, startIdx, promo, pcnt, promoStartIdx, promoIdx, cn, cd, g, idx) {
    cnt = split(FAMILY_RUNGS[family], rungs, " ")
    startIdx = 0
    for (i = 1; i <= cnt; i++) if (rungs[i] == start_rung) startIdx = i
    if (startIdx == 0) startIdx = 1

    pcnt = split(PROMO_RUNGS[family], promo, " ")
    promoStartIdx = 0
    for (i = 1; i <= pcnt; i++) if (promo[i] == start_rung) promoStartIdx = i
    promoIdx = promoStartIdx
    if (promoStartIdx > 0) {
        for (i = promoStartIdx + 1; i <= pcnt; i++) {
            cn = n * FACTOR[family ":" start_rung]
            cd = d * FACTOR[family ":" promo[i]]
            g = sc_gcd(cn, cd)
            if (g > 1) { cn /= g; cd /= g }
            if (2 * cn < cd) break
            if (sc_is_promo(cn, cd)) promoIdx = i
        }
    }
    if (promoIdx != promoStartIdx) {
        out["n"] = n * FACTOR[family ":" start_rung]
        out["d"] = d * FACTOR[family ":" promo[promoIdx]]
        sc_reduce(out)
        out["rung"] = promo[promoIdx]
        out["expr"] = sc_is_expr(out["n"], out["d"]) ? 1 : 0
        return
    }
    out["n"] = n; out["d"] = d
    sc_reduce(out)
    if (sc_is_expr(out["n"], out["d"])) { out["rung"] = start_rung; out["expr"] = 1; return }
    for (i = startIdx - 1; i >= 1; i--) {
        cn = n * FACTOR[family ":" start_rung]
        cd = d * FACTOR[family ":" rungs[i]]
        g = sc_gcd(cn, cd)
        if (g > 1) { cn /= g; cd /= g }
        if (sc_is_expr(cn, cd)) { out["n"] = cn; out["d"] = cd; out["rung"] = rungs[i]; out["expr"] = 1; return }
    }
    out["rung"] = rungs[1]
    cn = n * FACTOR[family ":" start_rung]
    cd = d * FACTOR[family ":" rungs[1]]
    g = sc_gcd(cn, cd)
    if (g > 1) { cn /= g; cd /= g }
    out["n"] = cn; out["d"] = cd
    out["expr"] = 0
}
function sc_convert(family, from_rung, to_rung, n, d, out) {
    out["n"] = n * FACTOR[family ":" from_rung]
    out["d"] = d * FACTOR[family ":" to_rung]
    sc_reduce(out)
}
function sc_plural_word(token, n, d,   base) {
    base = token
    sub(/s$/, "", base)
    if (n > d) return base "s"
    return base
}
function sc_render_unit(family, rung, style, raw_token, joined, unchanged, n, d,   word) {
    if (unchanged) {
        if (style == "abbrev") return (joined ? "" : " ") raw_token
        word = sc_plural_word(raw_token, n, d)
        return " " word
    }
    if (style == "abbrev") return " " ABBR[family ":" rung]
    word = SPELLED[family ":" rung]
    if (n > d) word = word "s"
    return " " word
}
function sc_render_count_equivalent(n, d, eq,    rendered, noun) {
    rendered = sc_render(n, d)
    if (!eq["count_equivalent"]) return rendered
    if (eq["count_noun"] == "") return rendered
    noun = eq["count_no_plural"] ? eq["count_noun"] : sc_plural_word(eq["count_noun"], n, d)
    return rendered " " eq["count_prefix"] noun
}
function sc_scale_equivalents(text,    i, start, end, inner, eq, lo, hi, best, loConv, rendered, before, after, result, complex) {
    result = text
    i = 1
    while (1) {
        start = index(substr(result, i), "(")
        if (start == 0) break
        start = i + start - 1
        end = index(substr(result, start), ")")
        if (end == 0) break
        end = start + end - 1
        inner = substr(result, start + 1, end - start - 1)
        if (inner ~ /[0-9]/ && !sc_nonquantity_parens(inner) && sc_try_equivalent(inner, eq)) {
            lo["n"] = eq["low_n"] * mnum; lo["d"] = eq["low_d"] * mden
            sc_reduce(lo)
            if (eq["family"] == "count") {
                rendered = sc_render_count_equivalent(lo["n"], lo["d"], eq)
                if (eq["is_range"]) {
                    hi["n"] = eq["high_n"] * mnum; hi["d"] = eq["high_d"] * mden
                    sc_reduce(hi)
                    rendered = rendered eq["sep"] sc_render_count_equivalent(hi["n"], hi["d"], eq)
                }
            } else if (!eq["is_range"]) {
                sc_best_rung(eq["family"], eq["rung"], lo["n"], lo["d"], best)
                lo["n"] = best["n"]; lo["d"] = best["d"]
                rendered = sc_render(lo["n"], lo["d"]) sc_render_unit(eq["family"], best["rung"], eq["style"], eq["unit_token"], eq["joined"], (best["rung"] == eq["rung"]), lo["n"], lo["d"]) eq["suffix"]
            } else {
                hi["n"] = eq["high_n"] * mnum; hi["d"] = eq["high_d"] * mden
                sc_reduce(hi)
                sc_best_rung(eq["family"], eq["rung"], hi["n"], hi["d"], best)
                hi["n"] = best["n"]; hi["d"] = best["d"]
                sc_convert(eq["family"], eq["rung"], best["rung"], lo["n"], lo["d"], loConv)
                rendered = sc_render(loConv["n"], loConv["d"]) eq["sep"] sc_render(hi["n"], hi["d"]) sc_render_unit(eq["family"], best["rung"], eq["style"], eq["unit_token"], eq["joined"], (best["rung"] == eq["rung"]), hi["n"], hi["d"])
            }
            if (eq["about"]) rendered = "about " rendered
            before = substr(result, 1, start)
            after = substr(result, end)
            result = before rendered after
            i = start + 1 + length(rendered) + 1
        } else if (inner ~ /[0-9]/ && !sc_nonquantity_parens(inner) && sc_scale_alternative_branch(inner, complex)) {
            before = substr(result, 1, start)
            after = substr(result, end)
            result = before complex["text"] after
            i = start + 1 + length(complex["text"]) + 1
        } else {
            i = end + 1
        }
    }
    return result
}
function sc_scale_equivalent_text(raw, out,    eq, lo, hi, best, loConv, rendered) {
    if (!sc_try_equivalent(raw, eq)) return 0
    lo["n"] = eq["low_n"] * mnum; lo["d"] = eq["low_d"] * mden
    sc_reduce(lo)
    if (eq["family"] == "count") {
        rendered = sc_render_count_equivalent(lo["n"], lo["d"], eq)
    } else if (!eq["is_range"]) {
        sc_best_rung(eq["family"], eq["rung"], lo["n"], lo["d"], best)
        lo["n"] = best["n"]; lo["d"] = best["d"]
        rendered = sc_render(lo["n"], lo["d"]) sc_render_unit(eq["family"], best["rung"], eq["style"], eq["unit_token"], eq["joined"], (best["rung"] == eq["rung"]), lo["n"], lo["d"]) eq["suffix"]
    } else {
        hi["n"] = eq["high_n"] * mnum; hi["d"] = eq["high_d"] * mden
        sc_reduce(hi)
        sc_best_rung(eq["family"], eq["rung"], hi["n"], hi["d"], best)
        hi["n"] = best["n"]; hi["d"] = best["d"]
        sc_convert(eq["family"], eq["rung"], best["rung"], lo["n"], lo["d"], loConv)
        rendered = sc_render(loConv["n"], loConv["d"]) eq["sep"] sc_render(hi["n"], hi["d"]) sc_render_unit(eq["family"], best["rung"], eq["style"], eq["unit_token"], eq["joined"], (best["rung"] == eq["rung"]), hi["n"], hi["d"]) eq["suffix"]
    }
    if (eq["about"]) rendered = "about " rendered
    out["text"] = rendered
    return 1
}
function sc_try_trailing_equivalent(text, out,    qlen, noparens, tail, f, raw_start, raw, base, baseCls, eqCls, join) {
    qlen = sc_parse_qualifier(text)
    noparens = sc_blank_parens(text)
    tail = substr(noparens, qlen + 1)
    if (sc_find_word(tail, "about", 1, f)) {
        raw_start = qlen + f["start"]
        raw = substr(text, raw_start)
        base = substr(text, 1, raw_start - 1)
    } else if (sc_find_word(tail, "enough for", 1, f)) {
        raw_start = qlen + f["start"] + f["len"]
        raw = substr(text, raw_start)
        base = substr(text, 1, raw_start - 1)
    } else return 0
    sub(/^[ ]+/, "", raw)
    if (sc_trailing_nonquantity(raw) || !sc_scale_equivalent_text(raw, eqCls)) return 0
    sc_classify(base, baseCls)
    if (baseCls["result"] == "flagged") return 0
    join = (baseCls["text"] ~ /[ ]$/) ? "" : " "
    out["result"] = "scaled"
    out["text"] = baseCls["text"] join eqCls["text"]
    out["flag"] = ""
    return 1
}
function sc_classify(text, out,    lead, ok, qlen, is_container, cwrd, cwrd2, rest0, amt0, alen0, remainder, noun, base, singular, newnoun, newn, newd, g, best, slowN, slowD, shighN, shighD, primaryText, unitText, dispN, dispD, hiN, hiD, loConv) {
    text = sc_normalize_amount_text(text)
    if (sc_is_cookware(text) || (CURRENT_HEADER != "" && index(tolower(CURRENT_HEADER), "equipment") > 0)) {
        out["result"] = "unchanged"; out["text"] = text; out["flag"] = ""
        return
    }
    ok = sc_parse_leading(text, lead)
    if (!ok) {
        out["result"] = "unchanged"; out["text"] = text; out["flag"] = ""
        return
    }
    qlen = sc_parse_qualifier(text)
    if (sc_try_alternatives(text, out)) return
    if (sc_try_compound_amounts(text, out)) return
    if (sc_try_trailing_equivalent(text, out)) return
    if (sc_flag_trigger(text, qlen)) {
        out["result"] = "flagged"; out["text"] = text; out["flag"] = "flag"
        return
    }
    is_container = sc_container_word(text, cwrd)
    if (is_container) {
        rest0 = substr(text, qlen + 1)
        alen0 = sc_parse_amount(rest0, amt0)
        if (alen0 == 0) {
            out["result"] = "unchanged"; out["text"] = text; out["flag"] = ""
            return
        }
        newn = amt0["n"] * mnum
        newd = amt0["d"] * mden
        g = sc_gcd(newn, newd)
        if (g > 1) { newn /= g; newd /= g }
        remainder = substr(rest0, alen0 + 1)
        if (sc_find_word(remainder, "cans|can|cartons|carton|packages|package|packets|packet|pkgs|pkg|containers|container|jars|jar|boxes|box|bags|bag|bottles|bottle|tubs|tub", 1, cwrd2)) {
            noun = substr(remainder, cwrd2["start"], cwrd2["len"])
            base = tolower(noun)
            if (base == "box" || base == "boxes") singular = "box"
            else { singular = base; sub(/s$/, "", singular) }
            if (newn <= newd) newnoun = singular
            else newnoun = (singular == "box") ? singular "es" : singular "s"
            if (substr(noun, 1, 1) ~ /[A-Z]/) newnoun = toupper(substr(newnoun, 1, 1)) substr(newnoun, 2)
            remainder = substr(remainder, 1, cwrd2["start"] - 1) newnoun substr(remainder, cwrd2["start"] + cwrd2["len"])
        }
        out["result"] = "scaled"; out["text"] = sc_render(newn, newd) remainder; out["flag"] = ""
        return
    }
    if (!is_container && sc_bad_parens(text)) {
        out["result"] = "flagged"; out["text"] = text; out["flag"] = "flag"
        return
    }
    if (lead["family"] == "count") {
        # Bare counts have no unit ladder to promote/demote onto, so retain
        # their exact reduced fraction (for example, 1/2 onion at 1/3x is
        # 1/6 onion) instead of rounding it to another amount.
        slowN = lead["low_n"] * mnum; slowD = lead["low_d"] * mden
        g = sc_gcd(slowN, slowD); if (g > 1) { slowN /= g; slowD /= g }
        primaryText = sc_render(slowN, slowD)
        unitText = ""
        if (lead["is_range"]) {
            shighN = lead["high_n"] * mnum; shighD = lead["high_d"] * mden
            g = sc_gcd(shighN, shighD); if (g > 1) { shighN /= g; shighD /= g }
            primaryText = primaryText lead["sep"] sc_render(shighN, shighD)
        }
    } else if (!lead["is_range"]) {
        slowN = lead["low_n"] * mnum; slowD = lead["low_d"] * mden
        sc_best_rung(lead["family"], lead["rung"], slowN, slowD, best)
        dispN = best["n"]; dispD = best["d"]
        primaryText = sc_render(dispN, dispD)
        unitText = sc_render_unit(lead["family"], best["rung"], lead["style"], lead["unit_token"], lead["joined"], (best["rung"] == lead["rung"]), dispN, dispD)
    } else {
        shighN = lead["high_n"] * mnum; shighD = lead["high_d"] * mden
        sc_best_rung(lead["family"], lead["rung"], shighN, shighD, best)
        hiN = best["n"]; hiD = best["d"]
        slowN = lead["low_n"] * mnum; slowD = lead["low_d"] * mden
        sc_convert(lead["family"], lead["rung"], best["rung"], slowN, slowD, loConv)
        primaryText = sc_render(loConv["n"], loConv["d"]) lead["sep"] sc_render(hiN, hiD)
        unitText = sc_render_unit(lead["family"], best["rung"], lead["style"], lead["unit_token"], lead["joined"], (best["rung"] == lead["rung"]), hiN, hiD)
    }
    remainder = substr(text, lead["consumed"] + 1)
    remainder = sc_scale_equivalents(remainder)
    if (!lead["is_range"] && lead["family"] == "us_volume" && best["rung"] == "teaspoon" && dispN == 1 && dispD == 16) {
        out["result"] = "scaled"
        out["text"] = lead["qualifier"] "a pinch of" remainder
        out["flag"] = ""
        return
    }
    out["result"] = "scaled"
    out["text"] = lead["qualifier"] primaryText unitText remainder
    out["flag"] = ""
}

$1 == "INGREDIENT" {
    kind = $2; text = $3; linkuid = $4
    if (kind == "section-header") {
        CURRENT_HEADER = text
        print "INGREDIENT", kind, text, linkuid, "", ""
        next
    }
    # A factor of 1 is a caller error in production (rv_load_recipe bypasses
    # this function entirely at index 0, per contracts/scale-ladder.md), but
    # the corpus sweep in tests/test_scaling.sh calls it directly to check
    # SC-004 mechanically. Guaranteeing identity here too -- rather than
    # relying solely on the caller never asking -- is what makes that
    # direct-call test meaningful instead of vacuous.
    if (mnum == mden) {
        print "INGREDIENT", kind, text, linkuid, "", ""
        next
    }
    sc_classify(text, cls)
    print "INGREDIENT", kind, cls["text"], linkuid, "", cls["flag"]
}
' "$RV_SCALE_SRC" > "$RV_SCALE_TMP" 2>>"$RV_LOG"
    then
        mv -f "$RV_SCALE_TMP" "$RV_SCALE_OUT"
        return 0
    else
        rm -f "$RV_SCALE_TMP"
        return 1
    fi
}

rv_apply_scale()
{
    # Rescales from the ORIGINAL recipe file (never a previous scaled file --
    # FR-004/SC-005), rebuilds only the ingredient layout, and re-anchors the
    # ingredient scroll to the record that was on screen before the rescale
    # (row indices are not stable across a rescale; record indices are).
    RV_SCALE_ANCHOR_RECORD=1
    if [ "$RV_INGREDIENT_ROWS" -gt 0 ] 2>/dev/null; then
        RV_SCALE_ANCHOR_RECORD=$(awk -F "$RV_TAB" -v scroll="$RV_INGREDIENT_SCROLL" '
            NR > scroll { print $1; exit }
        ' "$RV_TMP/ingredients.layout")
        [ -n "$RV_SCALE_ANCHOR_RECORD" ] || RV_SCALE_ANCHOR_RECORD=1
    fi
    if [ "$RV_SCALE_INDEX" -eq 0 ]; then
        rv_build_layout "$RV_ACTIVE_RECIPE" INGREDIENT "$RV_INGREDIENT_WRAP" "$RV_TMP/ingredients.layout"
    elif rv_scale_ingredients "$RV_ACTIVE_RECIPE" "$RV_SCALE_NUM" "$RV_SCALE_DEN" "$RV_TMP/ingredients.scaled"; then
        rv_build_layout "$RV_TMP/ingredients.scaled" INGREDIENT "$RV_INGREDIENT_WRAP" "$RV_TMP/ingredients.layout"
    else
        rv_log "failure scale factor=$RV_SCALE_NUM/$RV_SCALE_DEN; falling back to unscaled recipe"
        rv_build_layout "$RV_ACTIVE_RECIPE" INGREDIENT "$RV_INGREDIENT_WRAP" "$RV_TMP/ingredients.layout"
    fi
    RV_INGREDIENT_ROWS=$(wc -l < "$RV_TMP/ingredients.layout" | tr -d ' ')
    RV_INGREDIENT_GAP_ROWS=$(((RV_INGREDIENT_ITEMS * RV_INGREDIENT_ITEM_GAP + RV_INGREDIENT_LINE_H - 1) / RV_INGREDIENT_LINE_H))
    RV_INGREDIENT_MAX_SCROLL=$((RV_INGREDIENT_ROWS + RV_INGREDIENT_GAP_ROWS - RV_INGREDIENT_VISIBLE)); [ "$RV_INGREDIENT_MAX_SCROLL" -lt 0 ] && RV_INGREDIENT_MAX_SCROLL=0
    RV_SCALE_ANCHOR_ROW=$(awk -F "$RV_TAB" -v rec="$RV_SCALE_ANCHOR_RECORD" '
        $1 == rec && $4 == 1 { print NR - 1; exit }
    ' "$RV_TMP/ingredients.layout")
    [ -n "$RV_SCALE_ANCHOR_ROW" ] || RV_SCALE_ANCHOR_ROW=0
    rv_clamp "$RV_SCALE_ANCHOR_ROW" 0 "$RV_INGREDIENT_MAX_SCROLL"
    RV_INGREDIENT_SCROLL=$RV_CLAMPED
    rv_log "scale applied factor=$RV_SCALE_NUM/$RV_SCALE_DEN label=$RV_SCALE_LABEL anchor_record=$RV_SCALE_ANCHOR_RECORD scroll=$RV_INGREDIENT_SCROLL rows=$RV_INGREDIENT_ROWS"
}
