# Feature Specification: Recipe Scaling

**Feature Branch**: `main` (no branch hook configured; spec directory is `specs/001-recipe-scaling`)

**Created**: 2026-08-30

**Status**: Draft

**Input**: User description: "I want to be able to scale a recipe while I cook. Ingredients should scale to fractions common to cooking (e.g. 1/2, 1/3, 1/4, NOT 2/5, etc.). Measurements values should scale appropriately as well, for example, 3 teaspoons should become 1 Tablespoon, 8 tablespoons should correctly show 1/2 cup, etc."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Scale the ingredient list while cooking (Priority: P1)

A cook has a recipe open and needs a different quantity than the recipe was
written for — half a batch because they are cooking for two, or a double batch
for guests. Without leaving the recipe, they choose a scale factor and every
ingredient amount on screen changes to the scaled quantity, written the way a
cookbook would write it (whole numbers and common cooking fractions), not as a
decimal.

**Why this priority**: This is the entire feature request. Without it there is
nothing to deliver. Scaled amounts must be rendered as cook-friendly fractions
from the very first increment, because a raw decimal result such as
"0.6666666 cup" is unusable at the counter and would make the feature actively
worse than doing the arithmetic by hand.

**Independent Test**: Open a recipe with a mix of whole, fraction, and mixed
amounts, choose a scale factor, and confirm every recognized amount changes to
the correct scaled value expressed in whole numbers and common fractions. Fully
deliverable on its own.

**Acceptance Scenarios**:

1. **Given** a recipe listing "1 cup whole milk" and "1/2 teaspoon salt", **When** the cook scales to 2x, **Then** the pane shows "2 cups whole milk" and "1 teaspoon salt".
2. **Given** a recipe listing "1 1/2 cups whole milk", **When** the cook scales to 1/2x, **Then** the pane shows "3/4 cup whole milk".
3. **Given** a recipe listing "2 cups all-purpose flour", **When** the cook scales to 1/3x, **Then** the pane shows "2/3 cup all-purpose flour".
4. **Given** a recipe listing "3 green onions, chopped" (a bare count with no unit), **When** the cook scales to 2x, **Then** the pane shows "6 green onions, chopped".
5. **Given** a recipe scaled to 2x, **When** the cook returns the scale to 1x, **Then** every ingredient line reads exactly as it did before any scaling was applied.
6. **Given** a recipe listing "1-2 cups quality chicken stock" (a range), **When** the cook scales to 2x, **Then** both ends of the range scale, showing "2-4 cups quality chicken stock".

---

### User Story 2 - Amounts land in the unit a cook would actually use (Priority: P2)

Scaling frequently pushes an amount out of the unit it was written in. A cook
who reads "6 teaspoons" has to stop and convert; a cook who reads "2
tablespoons" does not. When a scaled amount is more naturally expressed in a
neighbouring unit of the same measuring family, the app presents it in that
unit instead.

**Why this priority**: Delivers the second half of the user's request. User
Story 1 is usable without it (the amounts are already correct and readable as
fractions), but unit normalization is what makes the results feel like a
properly written recipe rather than mechanical arithmetic. It also rescues
awkward results that fractions alone cannot fix, such as 1/6 cup.

**Independent Test**: Scale recipes containing teaspoon, tablespoon, cup,
ounce, and pound amounts by factors that cross unit boundaries, and confirm
each result is presented in the most idiomatic unit of its family.

**Acceptance Scenarios**:

1. **Given** a recipe listing "1 teaspoon garlic powder", **When** the cook scales to 3x, **Then** the pane shows "1 tablespoon garlic powder", not "3 teaspoons".
2. **Given** a recipe listing "4 tablespoons butter", **When** the cook scales to 2x, **Then** the pane shows "1/2 cup butter", not "8 tablespoons".
3. **Given** a recipe listing "1/3 cup pine nuts", **When** the cook scales to 1/2x, **Then** the pane shows an amount expressed in a common fraction — "2 2/3 tablespoons" — rather than the uncommon "1/6 cup".
4. **Given** a recipe listing "8 ounces elbow macaroni", **When** the cook scales to 2x, **Then** the pane shows "1 pound elbow macaroni".
5. **Given** a recipe listing "2 tablespoons olive oil", **When** the cook scales to 1x, **Then** the amount stays "2 tablespoons" and is not rewritten as "1/8 cup" — promotion only happens when the larger unit reads more naturally.
6. **Given** a recipe listing "400g '00' flour" (metric), **When** the cook scales to 2x, **Then** the pane shows "800g '00' flour" and the amount stays in metric.

---

### User Story 3 - Know what is scaled and what is not (Priority: P3)

Some ingredient lines cannot be scaled safely — "Salt and pepper", "Pinch of
red pepper flakes", a "5 Quart Sauce Pan" listed under equipment, or a line
whose amount the app cannot confidently interpret. A cook working from a scaled
list needs to see at a glance that the numbers on screen are scaled, and needs
the lines that were left alone to be visibly distinct so they know to do those
few by hand.

**Why this priority**: A quality and trust layer over Stories 1 and 2. The
feature is functional without it, but a cook who cannot tell whether a number
was scaled will second-guess every line, which erodes the value of the whole
feature. It also prevents the worst failure mode: silently leaving one
ingredient unscaled in an otherwise scaled list.

**Independent Test**: Open a recipe containing both scalable and unscalable
lines, apply a scale factor, and confirm the active factor is visible on screen
and every line the app did not scale is visually distinguishable from the lines
it did.

**Acceptance Scenarios**:

1. **Given** any scale factor other than 1x is active, **When** the cook looks at the recipe, **Then** the active factor is visible on screen without any further interaction.
2. **Given** a recipe listing "Salt and pepper" (no amount at all), **When** the cook scales to 2x, **Then** the line is unchanged and is **not** flagged — there is nothing to scale and nothing to warn about.
3. **Given** a recipe listing "1 small head cauliflower (1 1/2 to 2 pounds), enough for 6 cups florets" (an amount the app cannot confidently scale in full), **When** the cook scales to 2x, **Then** the line is marked as needing manual attention rather than being silently or partially rewritten.
4. **Given** a scaled amount that had to be rounded to reach a common fraction, **When** the cook reads it, **Then** it is presented as an approximation rather than as an exact value.
5. **Given** a recipe with an equipment line such as "5 Quart Sauce Pan", **When** the cook scales to 2x, **Then** the line is unchanged — a doubled batch does not need a 10 quart pan stated as fact.

---

### User Story 4 - Scaling does not disturb cooking progress (Priority: P3)

A cook part-way through a recipe — several ingredients already checked off, both
panes scrolled to where they are working — decides to change the scale. Changing
the scale must not throw away that progress or move them somewhere else in the
recipe.

**Why this priority**: A correctness-of-experience concern rather than new
capability. It only matters once Stories 1-3 exist, but getting it wrong makes
the feature feel unsafe to touch mid-cook, which is exactly when it is used.

**Independent Test**: Check several ingredients, scroll both panes, change the
scale factor, and confirm the checked ingredients remain checked and both panes
remain at the same reading position.

**Acceptance Scenarios**:

1. **Given** four ingredients are checked off, **When** the cook changes the scale factor, **Then** those same four ingredients remain checked.
2. **Given** the ingredient pane is scrolled part-way down, **When** the cook changes the scale factor, **Then** the pane still shows the region the cook was reading.
3. **Given** a scaled recipe, **When** the cook ends the recipe and opens a different one, **Then** the new recipe opens at its original, unscaled amounts.

---

### Edge Cases

Drawn from the ingredient text actually present in the sample library.

- **Package and container sizes must not scale.** "1 (28-oz) Can Diced Tomatoes" at 2x is "2 (28-oz) Cans Diced Tomatoes" — you buy two of the same can, you do not buy a 56 oz can. Same for "3 (4.3 oz) packages dry ramen" and "1 15-ounce container ricotta cheese".
- **Stated equivalents must stay consistent with the amount they restate.** "1 cup (236 ml) whole milk" at 2x must not become "2 cups (236 ml) whole milk" — either both numbers move together or the line is flagged as needing attention.
- **Trailing equivalents.** "8 ounces whole-milk mozzarella cheese, shredded (about 2 cups)" and "4 ounces Parmesan cheese, grated (about 2 cups)" restate the leading amount later in the line.
- **Ranges written two ways.** "1-2 cups", "4-5 garlic cloves", and "10 to 12 lasagna noodles" all express ranges.
- **Uncommon fractions produced by division.** 1/3 cup at 1/2x is 1/6 cup; 1/4 teaspoon at 1/3x is 1/12 teaspoon. What does the cook see?
- **Amounts too small to express.** 1/8 teaspoon at 1/2x. There is no smaller unit and no smaller common fraction in ordinary use.
- **Amounts with no unit but a size adjective.** "1 small onion, finely diced", "1 large egg", "1/2 yellow onion, diced" — 1/2 an onion at 2x is 1 onion; 1 large egg at 1/2x is half an egg, which is not a thing a cook can measure.
- **Non-food lines that look measured.** "5 Quart Sauce Pan" under an "EQUIPMENT" section header.
- **Lines with no amount at all.** "Salt and pepper", "Fresh thyme", "Lemon zest", "salt, to taste", "Pinch of salt", "freshly ground black pepper, to taste".
- **Section headers.** "For the Sauce:", "Toppings", "Cheese Filling and Pasta" — never scaled, never flagged.
- **Amounts embedded mid-line.** "1/4 cup DeLallo extra virgin olive oil, plus 1 tablespoon" and "3 medium garlic cloves, minced or pressed through a garlic press (about 1 tablespoon)" contain a second amount after the leading one.
- **The word "divided".** "2 cups beef stock divided", "1 cup shredded Parmesan cheese, divided" — the total scales; the split described later in the instructions does not.
- **Scaled text is longer than the original.** The ingredient pane is narrow; "1 tablespoon" becoming "3 tablespoons" or "2 2/3 tablespoons" changes how the line wraps and how many lines fit on screen.
- **Recipes with an empty or amount-free ingredient list.** Scaling must remain a safe no-op rather than an error.
- **A cook who scales, scrolls, and scales again** without ever returning to 1x — repeated scaling must always be computed from the original amounts, never compounded from the amounts currently on screen.

## Requirements *(mandatory)*

### Functional Requirements

**Choosing a scale**

- **FR-001**: Cooks MUST be able to change the scale of the open recipe without leaving the recipe they are cooking from.
- **FR-002**: The system MUST offer a fixed set of scale factors (enumerated in FR-029) rather than free numeric entry.
- **FR-003**: The system MUST allow the cook to return to the original amounts at any time, and returning to the original scale MUST restore every ingredient line to its exact original text.
- **FR-004**: Every scaled amount MUST be computed from the recipe's original amount, never from a previously scaled result, so that repeated scale changes never accumulate rounding error.
- **FR-005**: The active scale factor MUST be visible on screen whenever it is not the original scale.
- **FR-006**: The scale factor MUST return to the original scale when the cook opens a different recipe or ends the current one.

**Scaling amounts**

- **FR-007**: The system MUST scale amounts written as whole numbers ("2 cups"), common fractions ("1/2 teaspoon"), and mixed numbers ("1 1/2 cups").
- **FR-008**: The system MUST scale bare counts that carry no unit ("3 green onions", "4 large eggs", "2 cloves garlic").
- **FR-009**: The system MUST scale both endpoints of an amount written as a range, whether written with a hyphen ("1-2 cups", "4-5 garlic cloves") or the word "to" ("10 to 12 lasagna noodles").
- **FR-010**: The system MUST NOT scale a package or container size — a measurement that describes the unit the ingredient is sold in rather than the quantity used ("1 (28-oz) Can", "3 (4.3 oz) packages", "1 15-ounce container"). The count of packages MUST still scale.
- **FR-011**: The system MUST NOT scale numbers that are not quantities of an ingredient: oven temperatures, times, percentages ("93% lean"), and equipment sizes ("5 Quart Sauce Pan").
- **FR-012**: When a line states the same quantity twice in different units ("1 cup (236 ml) whole milk", "8 ounces ... (about 2 cups)"), the system MUST either scale both statements consistently or leave the line unscaled and flag it (FR-020). It MUST NOT scale one statement and leave the other.
- **FR-013**: Lines containing no scalable amount MUST be left exactly as written, and MUST NOT be flagged.
- **FR-014**: Section headers MUST never be scaled or flagged.

**How amounts are written**

- **FR-015**: Scaled amounts MUST be presented as whole numbers, common cooking fractions, or mixed numbers. Decimal amounts MUST never be shown as the result of scaling.
- **FR-016**: The fractions the system may produce are limited to halves, thirds, quarters, and eighths — 1/2, 1/3, 2/3, 1/4, 3/4, 1/8, 3/8, 5/8, 7/8. Fractions outside this set (1/5, 2/5, 1/6, 1/7, 1/9, 1/16, and so on) MUST never appear.
- **FR-017**: When a scaled amount reads more naturally in a neighbouring unit of the same measuring family, the system MUST present it in that unit. Specifically, an amount MUST be promoted to the larger unit when the result is at least half of that larger unit and is expressible under FR-016 (3 teaspoons → 1 tablespoon; 8 tablespoons → 1/2 cup; 16 ounces → 1 pound), and MUST be demoted to a smaller unit when the amount is not expressible under FR-016 in its current unit but is in the smaller one (1/6 cup → 2 2/3 tablespoons).
- **FR-018**: An amount MUST NOT be rewritten into a unit that reads less naturally than the one it was written in — "2 tablespoons" MUST stay "2 tablespoons" rather than becoming "1/8 cup".
- **FR-019**: Metric amounts MUST scale within metric units and MUST NOT be converted into US customary units, or vice versa.
- **FR-020**: When no combination of unit and common fraction expresses a scaled amount exactly, the system MUST present the nearest expressible amount and MUST mark it as an approximation.
- **FR-021**: The system MUST preserve the unit spelling and abbreviation style used by the recipe ("T", "tsp.", "Tbsp.", "cup", "C", "ounce", "oz", "lb.") rather than rewriting every line into one house style, except where FR-017 changes the unit itself. Where the unit changes, its written form MUST match how that unit is normally written in cooking.
- **FR-022**: The system MUST adjust the plural form of a unit or countable noun to agree with the scaled amount where the recipe's own wording makes that adjustment unambiguous ("1 cup" → "2 cups").
- **FR-023**: All text on the ingredient line other than the amounts the system scaled MUST be carried through unchanged, including notes ("divided", "plus more as needed", "or to taste"), brand names, and preparation instructions.

**Trust and clarity**

- **FR-024**: An ingredient line that contains an amount the system could not confidently scale MUST be visually distinguishable from lines that were scaled successfully, so the cook knows to scale it by hand.
- **FR-025**: The system MUST NOT partially rewrite a line it could not fully interpret — a line is either scaled in full or left in its original wording and flagged.
- **FR-026**: Ingredients the cook has already checked off MUST remain checked when the scale changes.
- **FR-027**: The reading position of both the ingredient and instruction panes MUST be preserved when the scale changes.

**Scope of scaling**

- **FR-028**: The cook MUST express the desired amount as a multiplier applied to the recipe as written. The system MUST NOT require, read, or display a serving count.
- **FR-029**: The set of available multipliers MUST include 1/2x, 1x, 1 1/2x, 2x, and 3x, with 1x being the recipe's original amounts.
- **FR-030**: Amounts written inside the instruction steps MUST NOT be scaled in this feature. Instruction text MUST be displayed exactly as written regardless of the active scale factor.
- **FR-031**: Because instruction amounts do not scale, the scale indicator required by FR-005 MUST remain visible while the cook is reading the instruction pane, so an unscaled amount in a step is never mistaken for a scaled one.

### Out of Scope

- **Scaling amounts inside instruction steps.** Deferred to a separate follow-up feature, to be considered once the amount-parsing and unit-normalization rules in this spec are proven against the real library. Instruction prose mixes quantities with times ("3-5 minutes"), temperatures ("350 degrees"), and equipment sizes, and separating them reliably is a materially harder problem than parsing the structured ingredient list. Shipping ingredient scaling first keeps this feature's risk contained.
- **Serving counts and recipe yield.** Not read, stored, or displayed. This keeps the feature clear of the compiled record format, which is at schema version 4 and carries no servings field; adding one would require a compiler change, a schema bump, and a full library re-export.
- **Free numeric entry of an arbitrary scale factor.** The fixed set in FR-029 covers ordinary cooking needs without an additional numeric-entry screen.
- **Persisting a scale factor across recipe sessions or device restarts.**

### Key Entities

- **Scale Factor**: The multiplier currently applied to the open recipe. Session-scoped, resets with the recipe. One value at a time, chosen from a fixed set.
- **Measured Amount**: A quantity found in ingredient text — a value (whole, fraction, mixed, or a range of these), an optional unit, and the role it plays in the line (quantity to use, package size, stated equivalent, or non-quantity). Only quantities-to-use and their equivalents are scaled.
- **Unit Family**: A set of units that convert cleanly among themselves — US volume (teaspoon, tablespoon, fluid ounce, cup, pint, quart, gallon), US weight (ounce, pound), metric volume (millilitre, litre), metric weight (gram, kilogram), and count (no unit). Amounts move only within their own family.
- **Common Cooking Fraction**: The closed set of fractions the system is allowed to display — halves, thirds, quarters, eighths.
- **Ingredient Line Classification**: The outcome of interpreting one ingredient line — scaled, unchanged because it holds nothing to scale, or flagged because it holds an amount the system could not confidently interpret.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A cook can change the scale of an open recipe in a single interaction, without navigating away from the recipe and without losing their place in it.
- **SC-002**: Across every ingredient line in the sample library, scaling by 1/2x, 2x, and 3x produces zero amounts written as decimals and zero fractions outside the common set of halves, thirds, quarters, and eighths.
- **SC-003**: 100% of the unit-normalization cases the request names — 3 teaspoons reading as 1 tablespoon, 8 tablespoons reading as 1/2 cup — produce the stated result.
- **SC-004**: Scaling a recipe and then returning it to its original scale reproduces the original ingredient text exactly, for every recipe in the sample library.
- **SC-005**: Repeatedly changing the scale — for example 2x, then 1/2x, then 3x — yields the same result as applying the final factor once, for every recipe in the sample library.
- **SC-006**: Zero package or container sizes ("28-oz can", "4.3 oz packages") are altered by scaling, across the whole sample library.
- **SC-007**: Every ingredient line in the sample library is either scaled correctly or visibly flagged; no line is silently left unscaled while its neighbours are scaled.
- **SC-008**: Changing the scale updates the screen no more slowly than scrolling the ingredient pane does today, so the interaction does not feel slower than the rest of the app.
- **SC-009**: A cook can tell whether the amounts on screen are scaled, and by how much, without any interaction beyond looking at the screen — including while reading the instruction pane, whose amounts do not scale.
- **SC-010**: Instruction text is byte-for-byte identical at every scale factor, for every recipe in the sample library.

## Assumptions

- **Cook screen only.** Scaling is offered while a recipe is open, matching "scale a recipe while I cook". The recipe list and search screens are unaffected.
- **Session-scoped.** The scale factor lives as long as the open recipe session, alongside the checked-ingredient state. It is not written to the device and does not survive ending the recipe. This matches how the app already treats checked ingredients.
- **Scaled amounts replace the originals.** The ingredient pane is 300px wide on a 758px panel; showing the original amount alongside the scaled one would cost more line wrapping than it is worth. The persistent scale indicator (FR-005) is what tells the cook the numbers are scaled.
- **The existing recipe data is sufficient.** Ingredient amounts are parsed from the ingredient text already present in the compiled library. No change to the Paprika export format, the schema version (currently 4), or the compiled library is required.
- **Amount interpretation is best-effort and fails loudly.** Free-text ingredient lines cannot be parsed with certainty. Where confidence is low the design prefers leaving the line alone and flagging it (FR-024, FR-025) over guessing, because a wrong amount presented as correct is worse for a cook than an amount they were told to work out themselves.
- **Halved eggs and similar indivisible items are the cook's call.** The app presents "1/2 large egg" rather than refusing to scale or silently rounding; deciding what to do about it is a judgement the cook makes.
- **Existing hardware constraints carry over.** The device runtime stays POSIX `sh` with no Python or BusyBox, and scaling must work within the app's existing partial-refresh and redraw behaviour. Recorded in `.agents/memories/kindle-paperwhite-2-runtime.md`.
- **Sample library as the test corpus.** The 15 recipes under `build/fake-kindle/extensions/RecipeViewer/library/` are treated as the representative corpus for the success criteria that reference "the sample library".
