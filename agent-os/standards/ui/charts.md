# Charts

## Colour is computed, not chosen
The categorical series palette in `Theme.series` is **validated**, not picked by
eye. Every slot clears: the dark lightness band (OKLCH L 0.48–0.67), the chroma
floor (C ≥ 0.10), protan/deuteran separation, the normal-vision floor, and 3:1
contrast against `Theme.surface`. Re-run the validator before touching it:

```
node <dataviz-skill>/scripts/validate_palette.js "<hex,…>" --mode dark --surface "#161619"
```

The previous hand-picked palette **failed** three of those checks — every hue sat
above the dark band, one read as grey, and green↔salmon measured ΔE 7.7 under
deuteranopia. That is exactly the failure eyeballing cannot catch.

**The order is the safety mechanism and does not change.** A warm-first reordering
to match the app's terracotta was measured and rejected: it dropped tritan
separation to 4.0 against 8.7. The brand accent and series identity are different
jobs — `Theme.accent` stays terracotta for UI, and charts use the validated order.

## Form follows the data's job
| Job | Form |
|---|---|
| One ratio against its whole | meter on a same-ramp track — never a two-slice pie |
| Part-to-whole, few classes | one horizontal stacked bar + legend |
| Magnitude over ordered bins | columns; **emphasis** when one bin is the story |
| Change against a baseline | diverging, with an arrow and sign so colour is never the only channel |
| More than ~7 classes | a table |

Hour-of-day is 24 ordered bins, so it is a column chart with the peak emphasised
and the rest in `Theme.muted` — not a radial clock. A radial layout distorts
magnitude by radius and is decoration; the cycle is not what the reader is
comparing.

## Marks
Bars cap at 24pt and never fill their band. Data-ends are 4pt rounded and square
at the baseline. Touching fills are separated by a **2pt surface gap**, never a
stroke. Grid and axis rules are solid hairlines one step off the surface — never
dashed.

**Text never wears the data colour.** Values, labels and legends use text tokens;
a coloured mark beside them carries identity. A legend is always present for two
or more series. Direct-label selectively — the peak, the extreme, the one series
the story is about — never every point.

Hero figures use **proportional** digits; `monospacedDigit()` belongs in table
rows and axis ticks, where numbers align vertically, and makes a large standalone
number look loosely spaced.

## Say what the number does not cover
A ratio computed over sources that cannot report its input is a lie by omission.
Cache is reported only by Claude Code, and only Claude Code marks delegated turns
— both panels carry a "Claude Code only" note, and the cache ranking excludes
projects with no cache data rather than listing them at 0% as if they were
caching badly.
