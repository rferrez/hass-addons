#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Community Add-on: Amazon S3 Backup
# ==============================================================================
#bashio::log.level "debug"

bashio::log.info "Starting Amazon S3 Backup..."

bucket_name="$(bashio::config 'bucket_name')"
storage_class="$(bashio::config 'storage_class' 'STANDARD')"
endpoint_url="$(bashio::config 'endpoint_url' '')"
bucket_region="$(bashio::config 'bucket_region' 'eu-central-1')"
delete_local_backups="$(bashio::config 'delete_local_backups' 'true')"
local_backups_to_keep="$(bashio::config 'local_backups_to_keep' '3')"
remote_backups_to_keep="$(bashio::config 'remote_backups_to_keep' '0')"
monitor_path="/backup"
endpoint_args=()
if bashio::var.has_value "${endpoint_url}"; then
    endpoint_args=(--endpoint-url "$endpoint_url")
fi
jq_filter=".backups|=sort_by(.date)|.backups|reverse|.[$local_backups_to_keep:]|.[].slug"

export AWS_ACCESS_KEY_ID="$(bashio::config 'aws_access_key')"
export AWS_SECRET_ACCESS_KEY="$(bashio::config 'aws_secret_access_key')"
export AWS_REGION="$bucket_region"

bashio::log.debug "Using AWS CLI version: '$(aws --version)'"
bashio::log.debug "Command: 'aws s3 sync $monitor_path s3://$bucket_name/ --no-progress --region $bucket_region --storage-class $storage_class'"
aws s3 sync $monitor_path "${endpoint_args[@]}" s3://"$bucket_name"/ --no-progress --region "$bucket_region"

# Keep it >= local_backups_to_keep, or the next sync re-uploads what was just deleted.
if [ "${remote_backups_to_keep}" -gt 0 ]; then
    bashio::log.info "Will delete bucket backups except the '${remote_backups_to_keep}' newest ones."
    remote_keys="$(aws s3api list-objects-v2 "${endpoint_args[@]}" --bucket "$bucket_name" --region "$bucket_region" \
        --query 'Contents[].[LastModified,Key]' --output json \
        | jq -r --argjson keep "$remote_backups_to_keep" '(. // []) | map(select(.[1] | endswith(".tar"))) | sort_by(.[0]) | .[:-$keep] | .[][1]')"

    for k in $remote_keys; do
        bashio::log.info "Deleting bucket backup: '$k'"
        aws s3 rm "${endpoint_args[@]}" s3://"$bucket_name"/"$k" --region "$bucket_region"
    done
fi

if bashio::var.true "${delete_local_backups}"; then
    bashio::log.info "Will delete local backups except the '${local_backups_to_keep}' newest ones."
    backup_slugs="$(bashio::api.supervisor "GET" "/backups" "false" "$jq_filter")"
    bashio::log.debug "Backups to delete: '$backup_slugs'"

    for s in $backup_slugs; do
        bashio::log.info "Deleting Backup: '$s'"
        bashio::api.supervisor "DELETE" "/backups/$s"
    done
else
    bashio::log.info "Will not delete any local backups since 'delete_local_backups' is set to 'false'"
fi

bashio::log.info "Finished Amazon S3 Backup."
