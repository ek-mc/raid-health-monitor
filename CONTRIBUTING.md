# Contributing

## Local checks

Run shell syntax check:

```bash
bash -n raid-health-monitor.sh
```

Run smoke test (uses temp dir, no mail send expected):

```bash
./tests/smoke.sh
```

## Style

- Keep Bash POSIX-ish where possible
- Prefer explicit checks over clever one-liners
- Keep alerts human-readable
- Keep normalized state deterministic (stable ordering)

## Safety

- Do not add destructive disk operations
- Do not add commands that modify RAID/ZFS state
- Monitoring should remain read-only

## PR checklist

- [ ] README updated if behavior changed
- [ ] CHANGELOG updated
- [ ] Smoke test passes
- [ ] Backward-compatible defaults (env overrides only)
