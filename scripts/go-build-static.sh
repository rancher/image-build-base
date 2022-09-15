#!/bin/sh

export CGO_ENABLED=${CGO_ENABLED:-1}
GOVERSION=$(go version)
if echo ${GOVERSION} | grep -q '1.19'; then
  echo "Enabling goboringcrypto"
  export GOEXPERIMENT=boringcrypto
fi
if [ "${CGO_ENABLED}" != "1" ]; then
  echo "CGO_ENABLED=${CGO_ENABLED}, should be set to 1 for static goboring compilation" >&2
  exit 1
fi
set -x
exec go build -ldflags "-linkmode=external -extldflags \"-static -Wl,--fatal-warnings\" ${GO_LDFLAGS}" "${@}"
