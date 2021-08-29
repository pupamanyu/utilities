#
# Script to extract schema from teradata
#
# This requires a python module yq(jq style yaml/xml tool). Use pip3 install yq module
# yq python module provides xq(xml), yq(yaml) binaries for processing xml/yaml data
#
#
get_td_schema_extract() {
    #
    # Execute SHOW IN XML <TABLE> against the source Teradata DB, and store it in a file beforehand.
    # Alternatively we can extract the show statement output into a temp file
    # The schema file provided needs to be as is output from SHOW in XML statement
    local TABLESCHEMAFILE="$1"
    local TDJSONSCHEMA = "$(cat ${TABLESCHEMAFILE} \
    | xq '.TeradataDBObjectSet.Table' \
    | jq '[] + [{"DatabaseName":."@dbName"}] + [{"TableName":."@name"}] + [{"Fields":.ColumnList.Column}] + [{"DDL": .SQLText}]')"
    echo "${TDJSONSCHEMA}";
}
