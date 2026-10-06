Native noise takes excluded as screen-recorder capture artifacts (recorder missed the first frames of an event, then delivered frames 1.7-6.7 ms apart):
material.materialize light-stripes take 3
material.materialize.bouncy dark-photo-reduce-motion take 3
material.materialize.bouncy dark-stripes-reduce-motion take 3
material.materialize.bouncy light-stripes-reduce-motion take 4
Evidence: .superpowers/sdd/plan-2b1/task-9-outliers.md and task-9-scan.md
Each folder holds take/ (the moved take) and pairs/ (its stale pair folders).
Replacement attempt 1 for material.materialize.bouncy light-stripes-reduce-motion take 4 (4-attempt1-bad-capture): events had no step labels and a 1848 ms gap; discarded.
Controller ruling (Task 20b): replacement takes renumbered 5 -> 3 in material.materialize light-stripes, material.materialize.bouncy dark-photo-reduce-motion and dark-stripes-reduce-motion, so fitvis (which groups per-take spreads by take number across cases) sees the same take set in every case. Pair folders symlinking to take 5 may dangle; noise.json unchanged.
