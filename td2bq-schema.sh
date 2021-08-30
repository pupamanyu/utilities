for field in `cat schema.json | jq -c .Fields | jq -c '.[]'`; do echo $field | jq -r -c '."@name"'; echo $field | jq -r -c '."DataType"|to_entries[]|.key' | tr [a-z] [A-Z]; done
