# Tests

Headless regression gate for the game. No display required.

```bash
# from the project dir (herosauro-superboxy/)
godot --headless --import .                       # once, so preloads resolve
godot --headless --script res://tests/test_runner.gd
echo $?    # 0 = all checks passed, 1 = at least one failure
```

`test_runner.gd` covers two layers:

1. **Compile gate** — loads every `.gd` under `scripts/`, `autoloads/`, and `tests/` (which transitively
   pulls in the scenes/materials/shaders they preload). A parse error anywhere fails the run.
2. **Logic tests** — exercises `GameManager`'s score, P2 combo, phase-2 threshold, and victory/defeat
   rules on a fresh instance.

CI runs this on every source push via `.github/workflows/tests.yml`.

It is intentionally dependency-free (a plain `SceneTree` script) so it runs reliably in headless CI.
Migrating to GUT or GdUnit4 later is straightforward and won't change the CI shape.
