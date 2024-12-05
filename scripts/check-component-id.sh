#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: make check-component-id ID=<id>"
  exit 1
fi

id=$1

matches=$(find . -name "*.proto" -exec grep -l "option (common\.ecs_component_id) = $id;" {} +)

if [ -z "$matches" ]; then
  echo "id $id is free"
else
  echo "id $id is taken"
fi
