# Perch — Mission

## Pitch
Perch is a local-first macOS app that turns AI coding-tool logs already on your disk
into per-project token analytics, with a pixel pet living in the MacBook notch.

## Problem
Existing trackers answer "how many tokens did I burn?" globally. The question that
matters is **per project**: which models did *this* codebase cost, on which days,
and how does that compare to the others.

## Users
A single developer on their own machine. No accounts, no servers, no network calls.

## Differentiators
1. **Notch-native.** The pet and the live counter ride the notch, not the menu bar.
2. **Project-first.** Every view pivots on project; totals are the roll-up, not the point.
3. **Read-only ingestion.** Perch never writes hooks or config into other tools.

## Non-goals
- Leaderboards, cloud sync, telemetry, accounts.
- Reading prompt or response *content*. Only counts, models, paths, timestamps.
