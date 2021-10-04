#!/usr/bin/env bash
#
# Utility shell functions to aid in BigQuery Load from GCS
#
#
# Recompile cdcmod binary on the node where gsutil is installed
# if `gsutil version -l` does not produce an output with "compiled crcmod: True"
# Reference: https://cloud.google.com/storage/docs/gsutil/addlhelp/CRC32CandInstallingcrcmod


lock() {
	# 
	# Helper function to set lockfile
	#
	local LOCKFILE="$1"
	touch ${LOCKFILE} && echo "Created lockfile ${LOCKFILE}"
}

clear_lock() {
	# 
	# Helper function to clear lockfile
	#
	local LOCKFILE="$1"
	[ -f ${LOCKFILE} ] && rm -f ${LOCKFILE} && echo "Cleared lockfile ${LOCKFILE}"
}

config_init() {
	# 
	# Load configuration, and setup environment variables
	#
	#
	INITFILE="./config"
	source ${INITFILE}
}

create_named_gcloud_config() {
	#
	# Helper function to create specified named gcloud configuration
	#
	local CONFIGURATION="$1"
	gcloud config configurations create ${CONFIGURATION}
}

activate_named_gcloud_config() {
	#
	# Helper function to activate specified named gcloud configuration
	#
	local CONFIGURATION="$1"
	gcloud config configurations activate ${CONFIGURATION}
}

delete_named_gcloud_config() {
	#
	#
	#
	local CONFIGURATION="$1"
	activate_named_gcloud_config default \
	&& gcloud config configurations delete ${CONFIGURATION}
}

get_credentials() {
	# TODO: Extract needed credentials
	# Helper Function to extract the needed credentials. 
	# Note: Intentionally left empty for the user to implement extraction mechanisms as per the needs.
	# Script/Function to get the service account key/credentials from the vault is called here.
	# Vault related code is explicitly kept as TODO here for security reasons
	# credentials need to be made available as parameter, and/or environment variables.
	# 	
}

gcloud_config_init() {
	#
	# Helper function to initialize gcloud configuration
	# 
	local CONFIGURATION="$1"
	local PROJECT="$2"
	local REGION="$3"
	local SERVICEACCOUNT="$4"
	local BILLINGPROJECT="$5"
	local KEYFILE="$6"
	[ ! -f ${KEYFILE} ] && echo "Specified key file ${KEYFILE} does not exist. Aborting gcloud config init..." && return 1
	activate_named_gcloud_config ${CONFIGURATION}
	gcloud config set core/project ${PROJECT}
	gcloud config set core/account ${SERVICEACCOUNT}
	gcloud config set compute/region ${REGION}
	gcloud config set billing/quota_project ${BILLINGPROJECT}
	gcloud auth activate-service-account ${SERVICEACCOUNT} --key-file=${KEYFILE}
}

load_gcs() {
	# 
	# Helper function to load file(s) into gcs bucket
	# 
        local SRCEXT="csv"
        # Bigquery uses a specific format in JSON. Please use this format to be compatible with bq load"
        local SRCDIR="$1"
        local TARGETBUCKET="$2"
        local TARGETDIR="$3"
        local CTRLFILE="$4"
        local SRC="${SRCDIR}/*.${SRCEXTENSION}"
        local TARGET="${TARGETBUCKET}/${TARGETDIR}"
        { [ -f ${SRCDIR}/${CTRLFILE} ] && echo "Local Control file ${SRCDIR}/${CONTROLFILE}. Initiating loading into GCS for ${SRCEXT} files under ${SRCDIR} into ${TARGET}" \
                && cd ${SRCDIR} \
                && gsutil -q -r -m cp ${SRCDIR}/*.${SRCEXT} ${TARGET} \
                && echo "Loaded all the ${SRCEXT} files under ${SRCDIR} into ${TARGET} successfully" \
                && return 0; } || return 1

}

get_unique_job_id() {
	# 
	# Get a unique job id to be used within workflow scheduler for tracking purposes
	#
	local JOBID="$(python3 -c 'from uuid import uuid4; print(uuid4().hex);')"
	echo ${JOBID}
}


extract_bq_field_schema() {
	# 
	# Extract existing table schema from BigQuery into the specified local schema file
	#
        local PROJECT="$1"
        local DATASET="$2"
        local TABLE="$3"
        local FIELDSCHEMAFILE="$4"
        bq --format=prettyjson show ${PROJECT}:${DATASET}.${TABLE} | jq .schema.fields > ${FIELDSCHEMAFILE} \
                && echo "Field Schema for ${PROJECT}:${DATASET}.${TABLE} is written into ${FIELDSCHEMAFILE}"
}

get_new_field_schema() {
	# 
	# Helper function to convert specified field into the BigQuery schema compatiable format.
	#
        local FIELD="$1"
        local TYPE="$2"
        local DESCRIPTION="$3"
        local MODE="NULLABLE"
        local NEWFIELD="[{\"description\": \"${DESCRIPTION}\",\"name\": \"${FIELD}\",\"type\": \"${TYPE}\",\"mode\": \"${MODE}\"}]"
        echo "[]" | jq -c ". + ${NEWFIELD}"
}

merge_field_schema() {
	# 
	# Helper function to merge specified field within the provided BigQuery schema file.
	#
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
	# 
	# Helper function to update BigQuery table schema using the provided BigQuery schema file.
	#
        local PROJECT="$1"
        local DATASET="$2"
        local TABLE="$3"
        local FIELDSCHEMAFILE="$4"
        bq update ${PROJECT}:${DATASET}.${TABLE} ${FIELDSCHEMAFILE} \
                && echo "New field added for table ${PROJECT}:${DATASET}.${TABLE} using the Schema file ${FIELDSCHEMAFILE}"
}


drop_partition() {
	# 
	# Helper function to drop specified partition within the specified BigQuery table.
	#
        local PROJECT="$1"
        local DATASET="$2"
        local TABLE="$3"
        local PARTITION="$4"
        { bq rm \
                --table ${PROJECT}:${DATASET}.${TABLE}\$${PARTITION} && return 0; } || return 1
}

drop_table() {
	#
	# Helper function to drop specified BigQuery table or snapshot.
	#
	local DATASET=$1
	local TABLE=$2
	{ bq rm \
		--table ${PROJECT}:${DATASET}.${TABLE} && return 0; } || return 1
}

update_table_metadata() {
	#
	# Helper function to update specified BigQuery table metadata.
	#
	local DATASET=$1
	local TABLE=$2
	local JOBID=$3
	local TIMESTAMP=$4
	{ bq update \
	--set_label jobid:${JOBID} \
	--set_label timestamp:${TIMESTAMP} ${DATASET}.${TABLE} && return 0; } || return 1
}

create_clustered_table() {
	#
	# Helper function to create specified BigQuery clustered table.
	#
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
	#
	# Helper function to create specified BigQuery clustered table with time partitioning.
	#
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
	#
	# Helper function to load CSV formatted data into the specified BigQuery table.
	#
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

get_bq_field_type() {
	# Given a Teradata Field Type, provide an closely matching BigQuery Field Type.
	# Commonly used data types are added here. More mappings can be added as per needs 
	# Teradata Reference: https://docs.teradata.com/r/iRq_F~XxKYWu7Kv~HRd~ew/D_RBrANpKte9E5uvWjq8~Q
	# BigQuery Reference: https://cloud.google.com/bigquery/docs/schemas
	local TDFIELDTYPE="$1"
	declare -A td2bq=([INTEGER]=INT64 [BIGINT]=INT64 [DECIMAL]=DECIMAL [DATE]=DATE [TIME]=TIME [FLOAT]=FLOAT64 [NUMBER]=NUMERIC [TIMESTAMP]=TIMESTAMP [BLOB]=BYTES [VARCHAR]=STRING [VARBYTE]=BYTES [CHA
RACTER]=STRING);
	echo ${td2bq["$1"]}
}

create_bq_snapshot() {
	#
	# Helper function to create named snapshot for the specified BigQuery table.
	#
	local SRCDATASET=$1
	local SRCTABLE=$2
	local SNAPDATASET=$3
	local EXPIRYSECONDS=$4
	{ bq cp \
	--snapshot \
	--no_clobber \
	--expiration=${EXPIRYSECONDS} \
	${SRCDATASET}.${SRCTABLE} \
	${SNAPDATASET}.${SRCTABLE} && return 0; } || return 1
}

filter_bq_snapshot() {
	#
	# Helper function to filter/search existing named snapshot with the specified JOBID, and TIMESTAMP labels.
	#
	local DATASET=$1
	local JOBID=$2
	local TIMESTAMP=$3
	bq ls \
	--max_rows=1000000 \
	--format json ${DATASET} \
	| jq -c  -r ".[] | select(.type == \"SNAPSHOT\" and .labels.jobid == \"${JOBID}\" and .labels.timestamp == \"${TIMESTAMP}\") | .tableReference.tableId"
}
