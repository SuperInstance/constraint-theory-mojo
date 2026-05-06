# Contributing to constraint-theory-mojo

## Prerequisites

- **Mojo SDK** (nightly): For native Mojo compilation
- **Python 3.10+**: For the Python fallback (always available)
- **MLIR tools**: For dialect development (optional)

## Development Setup

```bash
# Python fallback (always works)
python3 -c "from flux import automotive; print(automotive().check(60))"

# Mojo (requires SDK)
mojo build src/engine.mojo -o flux_engine
```

## Architecture

The codebase has three layers:
1. **Mojo source** (`src/*.mojo`): Native Mojo implementation
2. **Python fallback** (`flux/`): Pure Python with same API
3. **MLIR dialect** (`mlir/`): Custom dialect definition

All three produce identical results (zero mismatches on golden vectors).

## Testing

```bash
# Python
python3 -m pytest tests/

# Mojo (when available)
mojo test tests/
```

## Adding Presets

1. Add preset function in `src/engine.mojo`
2. Add matching Python preset in `flux/__init__.py`
3. Add tests in both `tests/`
4. Document in README

## License

Apache 2.0
