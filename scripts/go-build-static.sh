#!/bin/sh
set -x
exec go build -ldflags "-extldflags \"-static -Wl,--fatal-warnings\" ${GO_LDFLAGS}" "${@}"
