# schema.xml contains the output of SHOW IN XML <TABLE> statement
cat schema.xml | xq -c '.TeradataDBObjectSet.Table.ColumnList.Column'| jq -c '.[]' | jq -r -c '[."@name", ((."DataType"|to_entries[]).key | ascii_upcase)] | @csv'
