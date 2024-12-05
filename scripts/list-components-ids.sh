#!/bin/bash

ids=$(find . -name "*.proto" -exec grep -ho 'option (common\.ecs_component_id) = [0-9]\+;' {} + | sed -E 's/.*= ([0-9]+);/\1/' | sort -n)

count=$(echo "$ids" | wc -l | xargs)

echo "List of ids ($count total):"

i=1
echo "$ids" | while read id; do
    echo "$i. $id"
    ((i++))
done

