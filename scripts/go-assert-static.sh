#!/bin/sh

if [ -z "$*" ]; then
    echo "usage: $0 file1 [file2 ... fileN]"
fi

for exe in "${@}"; do
    if [ ! -x "${exe}" ]; then
        echo "$exe: file not found" >&2
        exit 1
    fi
    
    if ! file "${exe}" | grep -E '.*ELF.*executable, .*, (statically|static-pie) linked,.*'; then
        file "${exe}" >&2
        echo "${exe}: not a statically linked executable" >&2
        exit 1
    fi
done
