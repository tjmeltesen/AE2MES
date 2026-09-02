# AE2MES

OpenComputers MES node client for AE2/GT automation.

## Tests (Busted)

Unit and integration tests use [Busted](https://lunarmodules.github.io/busted/) with Lua 5.2. Scenarios live in `spec/*_spec.lua` and reuse step helpers from `features/support/`.

### Run in Docker (recommended)

From the `AE2-ES2` directory:

```powershell
docker build -f Dockerfile.test -t ae2-es2-test .
docker run --rm ae2-es2-test
```

### Run locally

```bash
luarocks install busted
./scripts/run_tests.sh
```

### Manual in-game smoke test

Copy `scripts/manual/test_me_snapshot.lua` to an OpenComputers computer with a real ME controller attached.

## Layout

| Path | Purpose |
|------|---------|
| `lib/` | Hardware component wrappers |
| `src/` | Runtime, executor, cloud client |
| `spec/` | Busted test specs |
| `features/` | Gherkin reference scenarios and shared step helpers |
| `scripts/manual/` | Hardware smoke tests (not run in CI) |
