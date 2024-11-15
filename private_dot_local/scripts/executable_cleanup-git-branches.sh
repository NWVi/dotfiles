#!/bin/bash

git fetch -p

deleted_count=0

for branch in $(git for-each-ref --format '%(refname) %(upstream:track)' refs/heads | awk '$2 == "[gone]" {sub("refs/heads/", "", $1); print $1}'); do
  git branch -D "$branch"
  ((deleted_count++))
done

echo "Deleted $deleted_count branches."
