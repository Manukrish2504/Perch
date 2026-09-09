# The Mascot

## Built from rectangles, not a sprite
The character is a **rig of named parts** — body, eyes, two hands, four legs —
each drawn as plain rectangles and each independently transformable. It is not a
baked pixel grid. That distinction is the whole point: a lean has to bend the
legs, a walk has to swing them from the hip, and a landing has to squash the
body. None of that is expressible in a grid, which is why the earlier sprite
version could only bob up and down.

Adding a species means adding a palette, never a second skeleton. Five rigs would
mean five walks to tune.

## Pivots decide whether motion reads
- Legs pivot from the **hip** (`legPivot`), not the foot. Rotating a leg about its
  foot looks like a windscreen wiper.
- The body pivots at **(53, 64)** — down near the hips, so a lean puts weight into
  the ground instead of spinning the body around its middle.
- Legs are **clipped to the floor**. Stretching a rectangle does not care where the
  ground is, so without the clip the legs punch straight through it on a lean.

## Timelines are sampled, not stepped
`MascotTimeline.value` replays a property's tweens in order from its identity
value, so each tween starts wherever the previous one ended and any instant can be
evaluated directly. Never drive the mascot from a frame counter: the pet is drawn
from a `TimelineView` clock that skips frames whenever its window is hidden, and a
counter would drift out of sync with the animation it is supposed to represent.

Easing names follow GSAP, where `power1` is quadratic, `power2` cubic and `power3`
quartic. The jump's asymmetry is deliberate and load-bearing: `sine.out` going up
and `power3.in` coming down is what reads as gravity.

## Bounds must fit the animation, not the pose
Drawing bounds reserve headroom for the **jump**, because a character that lifts
20 units gets its head clipped off without it. Headroom is otherwise constant
across moods on purpose — deriving it per mood makes the pet visibly resize every
time it starts or stops working.

## The dashboard's opening run
Opening the dashboard plays `MascotAnimations.run` while the scan happens behind
it, and **the pet is the progress indicator** — it runs the track and lays the bar
down behind it, position driven by the fraction of sources actually read.

Pace it with `min(elapsed / floor, scanProgress)`, never `max`. A warm scan
reports 100% almost immediately, so taking the larger of the two snaps the bar to
the end before the pet takes a step — it reads as broken, and it was. Time paces
the run; real progress holds it back whenever the scan is the slower of the two.

The mascot's feet sit ~95% down its own bounds (the rest is jump headroom), so a
pet placed at a track's baseline floats above the line unless it is offset by that
fraction.

## Every state is earned
Mood comes from real activity, never a timer: working (a request in the last 90s),
focused (6 min), calm, resting (45 min). The flag is a 3-day streak. Confetti is
two or more models used today. Nothing about the pet is decorative randomness.
