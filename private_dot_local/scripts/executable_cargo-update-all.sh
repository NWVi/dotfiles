#!/bin/sh

cargo install $(cargo install --list | grep '^[a-zA-Z0-9_\-]* v[0-9.]*:$' | cut -d ' ' -f1)
