set shell := ["bash", "-uc"]

bootstrap:
    bash scripts/bootstrap.sh

registered_generated_files := "flutter/lib/app/routing/app_routes.g.dart flutter/lib/app/routing/app_router.g.dart"

generate:
    cd flutter && fvm dart run build_runner build

check-generated:
    @set -euo pipefail; \
      snapshot_dir="$(mktemp -d)"; \
      trap 'rm -rf "${snapshot_dir}"' EXIT; \
      registered_files=( {{registered_generated_files}} ); \
      before_generated="${snapshot_dir}/before-generated"; \
      mkdir -p "${before_generated}"; \
      for path in "${registered_files[@]}"; do \
        key="$(printf '%s' "${path}" | tr '/' '_')"; \
        if [[ -f "${path}" ]]; then \
          printf 'present\n' > "${before_generated}/${key}.state"; \
          cp "${path}" "${before_generated}/${key}.bytes"; \
        else \
          printf 'absent\n' > "${before_generated}/${key}.state"; \
        fi; \
      done; \
      find flutter/lib -type f \( -name '*.g.dart' -o -name '*.freezed.dart' \) -print | sort > "${snapshot_dir}/before.paths"; \
      just generate; \
      status=0; \
      for path in "${registered_files[@]}"; do \
        key="$(printf '%s' "${path}" | tr '/' '_')"; \
        before_state="$(<"${before_generated}/${key}.state")"; \
        if [[ "${before_state}" == present ]]; then \
          if [[ ! -f "${path}" ]] || ! cmp -s "${before_generated}/${key}.bytes" "${path}"; then \
            echo "Generated output changed: ${path}" >&2; status=1; \
          fi; \
        elif [[ -f "${path}" ]]; then \
          echo "Registered generated output was created: ${path}" >&2; status=1; \
        else \
          echo "Registered generated output is missing: ${path}" >&2; status=1; \
        fi; \
      done; \
      find flutter/lib -type f \( -name '*.g.dart' -o -name '*.freezed.dart' \) -print | sort > "${snapshot_dir}/after.paths"; \
      while IFS= read -r path; do \
        if [[ -z "${path}" ]]; then continue; fi; \
        known=false; \
        for registered in "${registered_files[@]}"; do \
          if [[ "${path}" == "${registered}" ]]; then known=true; break; fi; \
        done; \
        if [[ "${known}" != true ]]; then \
          echo "Unexpected generated output: ${path}" >&2; status=1; \
        fi; \
      done < <(cat "${snapshot_dir}/before.paths" "${snapshot_dir}/after.paths" | sort -u); \
      exit "${status}"

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
