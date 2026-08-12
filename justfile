set shell := ["bash", "-uc"]

bootstrap:
    bash scripts/bootstrap.sh

generate:
    @echo "No committed generated-source families are registered in SLICE-P00-001."

check-generated: generate
    @echo "Generated-source freshness check: no registered generated families."

format:
    @bash scripts/run_rust.sh cargo fmt --manifest-path rust/Cargo.toml --all
    cd flutter && fvm dart format .

_format-check:
    @bash scripts/run_rust.sh cargo fmt --manifest-path rust/Cargo.toml --all -- --check
    cd flutter && fvm dart format --output=none --set-exit-if-changed .

lint:
    @bash scripts/run_rust.sh cargo clippy --manifest-path rust/Cargo.toml --workspace --all-targets --all-features --locked -- -D warnings
    cd flutter && fvm flutter analyze --no-pub
    shellcheck scripts/*.sh

_architecture:
    bash scripts/check_rust_dependencies.sh

test:
    @bash scripts/run_rust.sh cargo test --manifest-path rust/Cargo.toml --workspace --all-features --locked
    cd flutter && fvm flutter test --no-pub

check: check-generated _format-check lint _architecture test
