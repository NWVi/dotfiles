#!/bin/sh

echo "${@: -1}"
dir=$(mktemp -p /tmp -d sxiv-XXX)
7z x "${@: -1}" -o$dir > /dev/null
sxiv -r $dir
\rm -r $dir
