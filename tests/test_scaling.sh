#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
export RV_APP_ROOT="$ROOT/extensions/RecipeViewer"
export RV_TMP="$TMP_ROOT/recipe-viewer.test"
export RV_LOG="$TMP_ROOT/debug.log"
mkdir -p "$RV_TMP"
: > "$RV_LOG"

. "$RV_APP_ROOT/lib/core.sh"
. "$RV_APP_ROOT/lib/scale.sh"

failures=0
assert_eq() {
    if [[ "$1" != "$2" ]]; then
        echo "FAIL: ${3:-assert_eq}: expected [$2], got [$1]" >&2
        failures=$((failures + 1))
    fi
}

# $1=source ingredient text $2=num $3=den $4=expected text $5=expected flag (default empty)
assert_scaled() {
    local src=$1 num=$2 den=$3 expected=$4 expected_flag=${5:-}
    local fixture="$TMP_ROOT/one.recipe"
    local out="$TMP_ROOT/one.scaled"
    printf 'INGREDIENT\titem\t%s\t\n' "$src" > "$fixture"
    rv_scale_ingredients "$fixture" "$num" "$den" "$out"
    local got_text got_flag
    got_text=$(cut -f3 "$out")
    got_flag=$(cut -f6 "$out")
    assert_eq "$got_text" "$expected" "scale [$src] @$num/$den -> text"
    assert_eq "$got_flag" "$expected_flag" "scale [$src] @$num/$den -> flag"
}

RUN_UNITS=0
RUN_CORPUS=0
case "${1:-}" in
    --only)
        case "${2:-}" in
            units) RUN_UNITS=1 ;;
            corpus) RUN_CORPUS=1 ;;
            *) echo "unknown --only target: ${2:-}" >&2; exit 1 ;;
        esac
        ;;
    "") RUN_UNITS=1; RUN_CORPUS=1 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
esac

if [[ "$RUN_UNITS" -eq 1 ]]; then

# --- User Story 1: amounts scale and read like a cookbook ---
assert_scaled "1 cup whole milk" 2 1 "2 cups whole milk"
assert_scaled "1/2 teaspoon salt" 2 1 "1 teaspoon salt"
assert_scaled "1 1/2 cups whole milk" 1 2 "3/4 cup whole milk"
assert_scaled "2 cups all-purpose flour" 1 3 "2/3 cup all-purpose flour"
assert_scaled "3 green onions, chopped" 2 1 "6 green onions, chopped"
assert_scaled "1-2 cups quality chicken stock" 2 1 "2-4 cups quality chicken stock"
assert_scaled "10 to 12 lasagna noodles" 1 2 "5 to 6 lasagna noodles"
assert_scaled "400g '00' flour" 2 1 "800g '00' flour"

# --- User Story 2: amounts land in the unit a cook would use ---
assert_scaled "1 teaspoon garlic powder" 3 1 "1 tablespoon garlic powder"
assert_scaled "4 tablespoons butter" 2 1 "1/2 cup butter"
assert_scaled "1/3 cup pine nuts" 1 2 "2 2/3 tablespoons pine nuts"
assert_scaled "1/8 cup ketchup" 1 2 "1 tablespoon ketchup"
assert_scaled "1/8 teaspoon garlic powder" 1 2 "a pinch of garlic powder"
assert_scaled "1/3 cup (2 1/3 ounces) sugar" 1 2 \
    "2 2/3 tablespoons (1 1/6 ounces) sugar"
assert_scaled "8 ounces elbow macaroni" 2 1 "1 pound elbow macaroni"
assert_scaled "400g '00' flour" 2 1 "800g '00' flour"

# US2 promotion-rule guards (research decision D4 counter-examples)
assert_scaled "1 teaspoon vanilla" 2 1 "2 teaspoons vanilla"
assert_scaled "2 tablespoons oil" 1 1 "2 tablespoons oil"
assert_scaled "8 ounces cheese" 1 2 "4 ounces cheese"

# --- User Story 3: classification (scaled/approx/unchanged/flagged) ---
# Parenthetical bare-count equivalents scale with the primary amount. The
# second assertion also confirms a halved count uses its singular noun.
assert_scaled "1/2 c. chopped celery (about 2 stalks)" 2 1 "1 c. chopped celery (about 4 stalks)"
assert_scaled "1/2 c. chopped celery (about 2 stalks)" 1 2 "1/4 c. chopped celery (about 1 stalk)"
assert_scaled "1/2 c. chopped red pepper (about 1/2 of a large pepper)" 2 1 \
    "1 c. chopped red pepper (about 1 large pepper)"
assert_scaled "1/2 c. chopped red pepper (about 1/2 of a large pepper)" 3 1 \
    "1 1/2 c. chopped red pepper (about 1 1/2 large peppers)"
# A stick is a defined count measure, including qualified cinnamon sticks.
assert_scaled "1/2 cup (1 stick) butter, softened" 2 1 "1 cup (2 sticks) butter, softened"
assert_scaled "1/2 cup (1 stick) butter, softened" 3 2 "3/4 cup (1 1/2 sticks) butter, softened"
assert_scaled "1 cup cider (1 cinnamon stick)" 2 1 "2 cups cider (2 cinnamon sticks)"
# Each alternative branch scales its concrete quantities, while a relative
# parts formula remains a ratio.
assert_scaled "1/4 teaspoon garlic powder or 2 cloves, finely diced" 2 1 \
    "1/2 teaspoon garlic powder or 4 cloves, finely diced"
assert_scaled "1 teaspoon ground ginger or 2 teaspoons fresh ginger" 3 2 \
    "1/2 tablespoon ground ginger or 1 tablespoon fresh ginger"
assert_scaled "1 1/2 cups tomato juice OR 1 small can tomato sauce and 1/4 cup water" 2 1 \
    "3 cups tomato juice OR 2 small cans tomato sauce and 1/2 cup water"
assert_scaled "2 cups all-purpose flour (or 1 cup wheat flour + 1 cup all-purpose flour)" 2 1 \
    "4 cups all-purpose flour (or 2 cups wheat flour + 2 cups all-purpose flour)"
assert_scaled "2 tablespoons yellow mustard, or 1 part yellow + 1 part dijon" 2 1 \
    "4 tablespoons yellow mustard, or 1 part yellow + 1 part dijon"
assert_scaled "1 dried bay leaf or 2 fresh" 2 1 "2 dried bay leaf or 4 fresh"
assert_scaled "1 cup chopped onion (1 large)" 2 1 "2 cups chopped onion (2 large)"
assert_scaled "5 ounces baby spinach (or 8 cups chopped spinach)" 2 1 \
    "10 ounces baby spinach (or 16 cups chopped spinach)"
assert_scaled "1/4 cup DeLallo extra virgin olive oil , plus 1 tablespoon" 2 1 \
    "1/2 cup DeLallo extra virgin olive oil , plus 2 tablespoons"
assert_scaled "1 small head cauliflower (1 1/2 to 2 pounds), enough for 6 cups florets" 2 1 \
    "2 small head cauliflower (3 to 4 pounds), enough for 12 cups florets"
assert_scaled "4 boneless skinless chicken breasts, about 2 pounds" 2 1 \
    "8 boneless skinless chicken breasts, about 4 pounds"
assert_scaled "1/4 tsp (.5g) cayenne" 2 1 "1/2 tsp (1g) cayenne"
assert_scaled "1/2 cup water (100 degrees F)" 2 1 "1 cup water (100 degrees F)"
assert_scaled "2 large carrots, sliced about 1/16th-inch" 2 1 "4 large carrots, sliced about 1/16th-inch"
assert_scaled "1 (11.2-oz.) pkg. shortbread cookies" 3 2 "1 1/2 (11.2-oz.) pkgs. shortbread cookies"

# FR-013/FR-014: nothing to scale is unchanged and unflagged
assert_scaled "Salt and pepper" 2 1 "Salt and pepper"
assert_scaled "Pinch of salt" 2 1 "Pinch of salt"
assert_scaled "Fresh thyme" 2 1 "Fresh thyme"
assert_scaled "salt, to taste" 2 1 "salt, to taste"

# Section headers pass through verbatim regardless of content.
sec_fixture="$TMP_ROOT/sec.recipe"
sec_out="$TMP_ROOT/sec.scaled"
printf 'INGREDIENT\tsection-header\tSoup:\t\n' > "$sec_fixture"
rv_scale_ingredients "$sec_fixture" 2 1 "$sec_out"
assert_eq "$(cut -f2,3,6 "$sec_out" | tr '\t' '|')" "section-header|Soup:|" "section-header passes through unflagged"

# D7: equipment/cookware lines are never scaled and never flagged.
assert_scaled "5 Quart Sauce Pan" 2 1 "5 Quart Sauce Pan"

# Container/package rule (FR-010): only the leading count scales.
assert_scaled "1 (28-oz) Can Diced Tomatoes" 2 1 "2 (28-oz) Cans Diced Tomatoes"
assert_scaled "1 (28-oz) Can Diced Tomatoes" 1 2 "1/2 (28-oz) Can Diced Tomatoes"
assert_scaled "1 (28-oz) Can Diced Tomatoes" 3 2 "1 1/2 (28-oz) Cans Diced Tomatoes"

echo "unit assertions done"
fi

if [[ "$RUN_CORPUS" -eq 1 ]]; then

CORPUS="$ROOT/tests/fixtures/scaling-corpus.tsv"
[[ -r "$CORPUS" ]] || { echo "FAIL: missing corpus fixture $CORPUS" >&2; exit 1; }

corpus_recipe="$TMP_ROOT/corpus.recipe"
awk -F'\t' '{ print "INGREDIENT\t" $0 "\t" }' "$CORPUS" > "$corpus_recipe"
corpus_lines=$(wc -l < "$corpus_recipe" | tr -d ' ')

sweep_one() {
    # $1=num $2=den; writes $TMP_ROOT/sweep_<num>_<den>.tsv
    rv_scale_ingredients "$corpus_recipe" "$1" "$2" "$TMP_ROOT/sweep_${1}_${2}.tsv"
}

for f in "3 2" "2 1" "3 1" "1 2"; do
    set -- $f
    sweep_one "$1" "$2"
done

# SC-004: at 1x, every scaled INGREDIENT text is byte-identical to source.
sweep_one 1 1
if ! diff -q <(cut -f2 "$CORPUS") <(cut -f3 "$TMP_ROOT/sweep_1_1.tsv") >/dev/null; then
    echo "FAIL: SC-004: 1x did not reproduce the corpus byte-for-byte" >&2
    diff <(cut -f2 "$CORPUS") <(cut -f3 "$TMP_ROOT/sweep_1_1.tsv") | head -20 >&2
    failures=$((failures + 1))
fi

# SC-005: cycling the badge order 2x -> 1/2x -> 3x (each pass re-reads the
# ORIGINAL corpus, since rv_scale_ingredients is never fed a previously-scaled
# file) must land on the same 3x result as computing 3x in the earlier sweep
# above, which exercised a different call order (3/2, 2/1, 3/1, 1/2). If any
# state leaked between calls, these two independently-ordered 3x results
# would diverge even though both target the same factor.
rv_scale_ingredients "$corpus_recipe" 2 1 "$TMP_ROOT/path_2_1.tsv"
rv_scale_ingredients "$corpus_recipe" 1 2 "$TMP_ROOT/path_1_2.tsv"
rv_scale_ingredients "$corpus_recipe" 3 1 "$TMP_ROOT/path_3_1.tsv"
if ! diff -q <(cut -f3,6 "$TMP_ROOT/sweep_3_1.tsv") <(cut -f3,6 "$TMP_ROOT/path_3_1.tsv") >/dev/null; then
    echo "FAIL: SC-005: path-independence check failed" >&2
    diff <(cut -f3,6 "$TMP_ROOT/sweep_3_1.tsv") <(cut -f3,6 "$TMP_ROOT/path_3_1.tsv") | head -20 >&2
    failures=$((failures + 1))
fi

# SC-002: no decimal in any text the scaler itself wrote. Exact reduced
# fractions are deliberately allowed, including uncommon values such as 1/6.
# A decimal already present in untouched pass-through text (for example, a
# "4.3 oz" package size) is exempt.
for f in 3_2 2_1 3_1 1_2; do
    # Compared against the source line so an untouched decimal/odd-fraction
    # substring already present there (e.g. a "4.3 oz" package size) is
    # exempt -- only a decimal/bad fraction the scaler itself introduced
    # counts as a violation.
    paste "$CORPUS" "$TMP_ROOT/sweep_${f}.tsv" | while IFS=$'\t' read -r src_kind src_text out_type out_kind out_text out_link out_res out_flag; do
        [[ "$out_flag" == "flag" ]] && continue
        for dec in $(grep -oE '[0-9]+\.[0-9]+' <<<"$out_text" || true); do
            if ! grep -qF "$dec" <<<"$src_text"; then
                echo "FAIL: SC-002 @${f}: scaler introduced a decimal [$dec] in [$out_text]" >&2
                echo "SC002FAIL"
            fi
        done
    done > "$TMP_ROOT/sc002_${f}.log"
    if grep -q SC002FAIL "$TMP_ROOT/sc002_${f}.log"; then
        grep FAIL "$TMP_ROOT/sc002_${f}.log" >&2
        failures=$((failures + 1))
    fi
done

# SC-006: package sizes are never altered, at any factor.
for f in 3_2 2_1 3_1 1_2; do
    paste "$CORPUS" "$TMP_ROOT/sweep_${f}.tsv" | awk -F'\t' -v f="$f" '
        {
            src = $2; out = $5
            s = src
            while (match(s, /[0-9]+( [0-9]+\/[0-9]+)?-(oz|ounce)/)) {
                tok = substr(s, RSTART, RLENGTH)
                if (index(out, tok) == 0) {
                    print "FAIL: SC-006 @" f ": package size [" tok "] altered -> [" out "]"
                    print "SC006FAIL"
                }
                s = substr(s, RSTART + RLENGTH)
            }
        }
    ' > "$TMP_ROOT/sc006_${f}.log"
    if grep -q SC006FAIL "$TMP_ROOT/sc006_${f}.log"; then
        grep FAIL "$TMP_ROOT/sc006_${f}.log" >&2
        failures=$((failures + 1))
    fi
done

# SC-007: every line resolves to exactly one of scaled/approx/unchanged/
# flagged -- classification here is inferred from the flag column plus
# whether the text changed, and every row must fall into one bucket.
for f in 3_2 2_1 3_1 1_2; do
    awk -F'\t' -v f="$f" '
        $6 != "" && $6 != "approx" && $6 != "flag" {
            print "FAIL: SC-007 @" f ": unclassified flag value [" $6 "] on [" $3 "]"
            print "SC007FAIL"
        }
    ' "$TMP_ROOT/sweep_${f}.tsv" > "$TMP_ROOT/sc007_${f}.log"
    if grep -q SC007FAIL "$TMP_ROOT/sc007_${f}.log"; then
        grep FAIL "$TMP_ROOT/sc007_${f}.log" >&2
        failures=$((failures + 1))
    fi
done

# FR-013/FR-014: a line with nothing to scale is unchanged and unflagged --
# never marked "flag" just because it happens to have no amount.
for f in 3_2 2_1 3_1 1_2; do
    paste "$CORPUS" "$TMP_ROOT/sweep_${f}.tsv" | awk -F'\t' -v f="$f" '
        $2 !~ /[0-9]/ && $8 != "" {
            print "FAIL: FR-013 @" f ": amount-free line unexpectedly flagged: [" $2 "] -> flag=[" $8 "]"
            print "FR013FAIL"
        }
    ' > "$TMP_ROOT/fr013_${f}.log"
    if grep -q FR013FAIL "$TMP_ROOT/fr013_${f}.log"; then
        grep FAIL "$TMP_ROOT/fr013_${f}.log" >&2
        failures=$((failures + 1))
    fi
done

echo "corpus sweep done: $corpus_lines lines x 4 factors"
fi

if (( failures > 0 )); then
    echo "$failures scaling test(s) failed" >&2
    exit 1
fi
echo "scaling tests passed"
