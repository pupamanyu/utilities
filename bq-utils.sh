#!/usr/bin/env bash
#
# Utility shell functions to aid in BigQuery Load from GCS
#
#
# Recompile cdcmod binary on the node where gsutil is installed
# if `gsutil version -l` does not produce an output with "compiled crcmod: True"
# Reference: https://cloud.google.com/storage/docs/gsutil/addlhelp/CRC32CandInstallingcrcmod
load_gcs() {
        local SRCEXT="csv"
        # Bigquery uses a specific format in JSON. Please use this format to be compatible with bq load"
        local LCKFILE="${SRCDIR}/.loadlock"
        local SRCDIR="$1"
        local TARGETBUCKET="$2"
        local TARGETDIR="$3"
        local CTRLFILE="$4"
        local SRC="${SRCDIR}/*.${SRCEXTENSION}"
        local TARGET="${TARGETBUCKET}/${TARGETDIR}"
        { [ -f ${SRCDIR}/${CTRLFILE} ] && echo "Local Control file ${SRCDIR}/${CONTROLFILE}. Initiating loading into GCS for ${SRCEXT} files under ${SRCDIR} into ${TARGET}" \
                && cd ${SRCDIR} \
                && touch ${LOCKFILE} \
                && gsutil -q -r -m cp ${SRCDIR}/*.${SRCEXT} ${TARGET} \
                && echo "Loaded all the ${SRCEXT} files under ${SRCDIR} into ${TARGET} successfully" \
                && echo "Removing the lock file ${LCKFILE} now" \
                && rm -f ${LCKFILE} \
                && return 0; } || return 1

}


extract_bq_field_schema() {
        local PROJECT="$1"
        local DATASET="$2"
        local TABLE="$3"
        local FIELDSCHEMAFILE="$4"
        bq --format=prettyjson show ${PROJECT}:${DATASET}.${TABLE} | jq .schema.fields > ${FIELDSCHEMAFILE} \
                && echo "Field Schema for ${PROJECT}:${DATASET}.${TABLE} is written into ${FIELDSCHEMAFILE}"
}

get_new_field_schema() {
        local FIELD="$1"
        local TYPE="$2"
        local DESCRIPTION="$3"
        local MODE="NULLABLE"
        local NEWFIELD="[{\"description\": \"${DESCRIPTION}\",\"name\": \"${FIELD}\",\"type\": \"${TYPE}\",\"mode\": \"${MODE}\"}]"
        echo "[]" | jq -c ". + ${NEWFIELD}"
}

merge_field_schema() {
        local FIELD="$1"
        local TYPE="$2"
        local DESCRIPTION="$3"
        local FIELDSCHEMAFILE="$4"
        local OLDSCHEMAFILE="$5"
        local NEWSCHEMAFILE="$6"
        [ -f ${FIELDSCHEMAFILE} ] && cat ${FIELDSCHEMAFILE} | jq -c ". + $(get_new_field_schema ${FIELD} ${TYPE} \"${DESCRIPTION}\")" > ${NEWSCHEMAFILE} \
                && echo "Updated schema written to ${NEWSCHEMAFILE} with the new field ${FIELD}"
}

add_field() {
        local PROJECT="$1"
        local DATASET="$2"
        local TABLE="$3"
        local FIELDSCHEMAFILE="$4"
        bq update ${PROJECT}:${DATASET}.${TABLE} ${FIELDSCHEMAFILE} \
                && echo "New field added for table ${PROJECT}:${DATASET}.${TABLE} using the Schema file ${FIELDSCHEMAFILE}"
}


drop_partition() {
        local PROJECT="$1"
        local DATASET="$2"
        local TABLE="$3"
        local PARTITION="$4"
        { bq rm \
                --table ${PROJECT}:${DATASET}.${TABLE}\$${PARTITION} && return 0; } || return 1
}

create_clustered_table() {
        local PROJECT="$1"
        local DATASET="$2"
        local TABLE="$3"
        # Supply contiguos list of cluster fields upto max 4 fields(for eg: field1,field2,field3,field4)
        local CLUSTER_COLUMNS="$4"
        # Bigquery uses a specific format in JSON. Please use this format to be compatible with bq"
        local SCHEMAFILE="$5"
        local DESCRIPTION="$6"
        # TODO: Add label option
        { bq mk \
                --project_id=${PROJECT} \
                --table \
                --quiet=true
                --schema=${SCHEMAFILE} \
                --clustering_fields=${CLUSTER_COLUMNS} \
                --description="${DESCRIPTION}" \
                ${PROJECT}:${DATASET}.${TABLE} && return 0; } || return 1
}


create_partitioned_table() {
        local PROJECT="$1"
        local DATASET="$2"
        local TABLE="$3"
        local PARTITIONTYPE="DAY"
        local PARTITIONFIELD="$4"
        # TODO: Add label option
        # Supply contiguos list of cluster fields upto max 4 fields(for eg: field1,field2,field3,field4)
        local CLUSTER_COLUMNS="$5"
        # Bigquery uses a specific format in JSON. Please use this format to be compatible with bq"
        local SCHEMAFILE="$6"
        local DESCRIPTION="$7"
        { bq mk \
                --project_id=${PROJECT} \
                --table \
                --quiet=true \
                --schema=${SCHEMAFILE} \
                --time_partitioning_field=${PARTITIONFIELD} \
                --time_partitioning_type=${PARTITIONTYPE} \
                --require_partition_filter=true
                --clustering_fields=${CLUSTER_COLUMNS} \
                --description="${DESCRIPTION}" \
                ${PROJECT}:${DATASET}.${TABLE} && return 0; } || return 1
}

append_table() {
        local SRCFMT="CSV"
        local PARTITIONTYPE="DAY"
        # Set CSVSKIPHEADER to 0 if CSV does not have header"
        local CSVSKIPHEADER=1
        local SRC="$1"
        local PROJECT="$2"
        local DATASET="$3"
        local TABLE="$4"
        local PARTITIONFIELD="$5"
        # BQ JSON Schema file is local to the bq client
        local SCHEMAFILE="$6"
        { bq load \
                --project_id=${PROJECT} \
                --quiet=true
                --noreplace \
                --fingerprint_job_id=true \
                --format=${SRCFMT} \
                --allow_jagged_rows \
                --skip_leading_rows=${CSVSKIPHEADER} \
                --synchronous_mode=true \
                ${DATASET}.${TABLE} \
                ${SRC} \
                ${SCHEMAFILE} && return 0; } || return 1

}
