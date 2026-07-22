#!/bin/sh
# go-mod-overrides.sh — apply tracked go.mod overrides on top of an upstream
# module so Rancher images stay CVE-free even when upstream has not yet bumped.
#
# The overrides file is a simple line-oriented list where each non-comment line
# is passed verbatim to `go mod edit` (or `go work edit` in workspace mode).
# That keeps this a thin, dependency-free wrapper (just `go` + `sh`) and makes
# every override trivially reviewable in a PR diff.
#
# When a go.work file is present (and GOWORK is not "off") the module is treated
# as a Go workspace: overrides are applied with `go work edit`, `go mod tidy` is
# skipped (there is no workspace equivalent and it is unreliable against monorepo
# staging replace directives), and vendoring uses `go work vendor`. Otherwise the
# module-mode path (`go mod edit` + `go mod tidy` + `go mod vendor`) is used.
#
# Usage:
#   go-mod-overrides.sh [OVERRIDES_FILE]
#
# Defaults to ./go-mod-overrides. Must be run from the module directory (the
# directory containing the go.mod — or go.work — you want to patch).

set -e

OVERRIDES="${1:-go-mod-overrides}"

if [ ! -f "${OVERRIDES}" ]; then
    echo "go-mod-overrides: no overrides file at '${OVERRIDES}', nothing to do" >&2
    exit 0
fi

# Detect Go workspace mode: a go.work file in the current directory, unless
# workspace mode has been explicitly disabled via GOWORK=off.
WORKSPACE_MODE=
if [ -f go.work ] && [ "${GOWORK}" != "off" ]; then
    WORKSPACE_MODE=1
fi

if [ -z "${WORKSPACE_MODE}" ] && [ ! -f go.mod ]; then
    echo "go-mod-overrides: no go.mod found in $(pwd)" >&2
    exit 1
fi

# Read line by line; strip comments and surrounding whitespace; pass the rest
# straight to `go mod edit` / `go work edit`. Module paths/versions contain no
# whitespace, so the intentional word-splitting of ${line} cleanly separates the
# flag from its arg.
while IFS= read -r line || [ -n "${line}" ]; do
    line="${line%%#*}"
    # Trim leading/trailing whitespace (pure POSIX sh; avoids external deps like sed).
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [ -z "${line}" ] && continue
    if [ -n "${WORKSPACE_MODE}" ]; then
        echo "go-mod-overrides: go work edit ${line}"
        # shellcheck disable=SC2086
        go work edit ${line}
    else
        echo "go-mod-overrides: go mod edit ${line}"
        # shellcheck disable=SC2086
        go mod edit ${line}
    fi
done < "${OVERRIDES}"

if [ -n "${WORKSPACE_MODE}" ]; then
    # No `go work tidy` exists; workspace mode intentionally skips `go mod tidy`
    # because it is unreliable against monorepo staging replace directives.
    # Re-vendor with the workspace-aware command only if upstream vendors deps.
    if [ -d vendor ]; then
        go work vendor
    fi
    echo "go-mod-overrides: applied overrides from '${OVERRIDES}' (workspace mode)"
else
    # Reconcile the module graph and re-vendor only if upstream vendors its deps.
    go mod tidy
    if [ -d vendor ]; then
        go mod vendor
    fi
    echo "go-mod-overrides: applied overrides from '${OVERRIDES}'"
fi
