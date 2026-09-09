# Theme Tokens

All colour and metric literals live in `Theme.swift`. A raw `Color(red:…)` or a
magic `padding(13)` anywhere else is a bug.

## Palette
Perch is dark-first: the shelf must read as an extension of the physical notch, so
the notch surface is true black (`#000000`) and is never themed.

The dashboard uses a near-black surface ramp (`bg` → `surface` → `raised`) with a
single warm accent for token volume, matching the pet's palette. Series colours come
from `Theme.series`, in order — never pick a colour per-chart.

## Rules
- Text: `.primaryText` / `.secondaryText` / `.tertiaryText`. Three levels, no more.
- Numbers are `.monospacedDigit()` everywhere so they stop jittering as they tick.
- Corner radius: `Theme.radius` (10) for cards, `Theme.notchRadius` (bottom of shelf).
- Animations: `Theme.expand` (spring) for the shelf, `.easeInOut(0.18)` for hovers.
  The pet's own animation is frame-based, never a SwiftUI implicit animation.
