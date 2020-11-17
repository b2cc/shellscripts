#!/bin/bash
#
# atlassian cloud backup script
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# Author: david.gabriel@ndgit.com
# (c) 2020

# script common variables
bitbucket_oauth_url="https://bitbucket.org/site/oauth2"
bitbucket_api_url="https://api.bitbucket.org/2.0"
attachments="false"
backup=""
tenant=""
TEMPDIR=""
LOGGER="$(command -v logger)"
SCRIPT=$(basename $0)
TIMEZONE="Europe/Berlin"
# set term colors via tput
# see man terminfo
black=$(tput setaf 0)
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
magenta=$(tput setaf 5)
cyan=$(tput setaf 6)
white=$(tput setaf 7)
bold=$(tput bold)
reset=$(tput sgr0)

check_for_binaries() {
  BINARIES=(curl git jq ${LOGGER} mktemp tar)
  for binary in "${BINARIES[@]}"; do
    [[ -x $(which ${binary} 2>/dev/null) ]] || die "${binary} binary not found, exiting."
  done
}

check_backup_error_lockfile() {
  if [[ -f ${backup_error_file} ]]; then
    die "lock file found: **${backup_error_file}**, last backup aborted erroneously. check for errors, remove lockfile and try again."
  fi
}

check_backup_in_progress_lockfile() {
  if [[ -f ${backup_in_progress_file} ]]; then
    die "lock file found: **${backup_in_progress_file}**, backup in progress. aborting."
  fi
}

create_tempdir() {
  TEMPDIR=$(mktemp -p ${BACKUP_FOLDER} --suffix="-${APP}" -d || die " * Error while creating tempdir, exiting.")
}

log_generic() {
  logdate=$(date "+%h %d %H:%M:%S")
  logproc=$(echo $$)
  logmessage="$logdate ${HOST} ${scriptname}[${logproc}]: (${USER}) ${LOGLEVEL}: $1"
  echo "${logmessage}"
  ${LOGGER} "$1"
}

log() {
  LOGLEVEL="INFO"
  log_generic "$@"
}

log_debug() {
if [[ ${debug} == enabled ]]; then
  LOGLEVEL="DEBUG"
  log_generic "$@"
fi
}

die() {
  LOGLEVEL="ERROR"
  log_generic "$@"
  rm -f ${backup_in_progress_file}
  touch ${backup_error_file}
  cleanup
  exit 1
}

create_lockfile() {
  touch ${backup_in_progress_file}
}

cleanup() {
  [[ -d ${TEMPDIR} ]] && rm -rf ${TEMPDIR}
  [[ -f ${backup_in_progress_file} ]] && rm -f ${backup_in_progress_file}
}

check_vars() {
  if [[ -z ${APP} ]]; then die " * Error: variable \$APP is not defined, exiting"; fi
  if [[ -z ${BACKUP_FOLDER} ]]; then die " * Error: variable \$BACKUP_FOLDER is not defined, exiting"; fi
  if [[ -z ${tenant} ]]; then die " * Error: variable \$tenant is not defined, exiting"; fi
  if [[ -z ${retention} ]]; then retention=32; fi

  case ${backup} in
    bitbucket)
      if [[ -z ${oauth_key} ]]; then die " * Error: variable \$oauth_key is not defined, exiting"; fi
      if [[ -z ${oauth_secret} ]]; then die " * Error: variable \$oauth_tenant is not defined, exiting"; fi
    ;;
    confluence|jira)
      if [[ -z ${API_TOKEN} ]]; then die " * Error: variable \$API_TOKEN is not defined, exiting"; fi
      if [[ -z ${EMAIL} ]]; then die " * Error: variable \$EMAIL is not defined, exiting"; fi
      if [[ -z ${progress_retries} ]]; then progress_retries=300; fi
      if [[ -z ${progress_sleep} ]]; then progress_sleep=30; fi
      if [[ -z ${timezone} ]]; then timezone="Europe/Vienna"; fi
    ;;
  esac
}

check_backup_folder() {
  [[ -d ${BACKUP_FOLDER} ]] || die " * Backup folder ${BACKUP_FOLDER} doesn't exist, exiting."
  [[ -w ${BACKUP_FOLDER} ]] || die " * Backup folder ${BACKUP_FOLDER} isn't writable, exiting."
}

print_backup_info() {
log " * Backup info:"
log "    * App: ${APP}"
log "    * Tenant domain: ${INSTANCE}"
log "    * Include attachments (only jira/confluence): ${attachments}"
log "    * Backup folder: ${BACKUP_FOLDER}"
log "    * Progress check retries: ${progress_retries}"
log "    * Wait between progress check retries: ${progress_sleep} seconds"
log "    * Timezone: ${timezone}"
log "    * Backup retention: ${retention} days"
}

remove_old_backups() {
log " * Removing backups older than ${retention} days."
if ! find ${BACKUP_FOLDER} -type f -mtime +${retention} | xargs rm -f; then
  die "    * Error removing old backups files!"
else
  log "    * Cleanup complete."
fi
}

backup_bitbucket() {
log " * Starting ${APP} backup"
set -o pipefail
log " * Acquiring ${APP} oauth token.."
auth_token=$(curl -sSlf -X POST -u ${oauth_key}:${oauth_secret} ${bitbucket_oauth_url}/access_token -d  grant_type=client_credentials | jq -r '.access_token') ||  die " * Error while obtaining ${APP} OAuth token, exiting."

log " * Generating list of repositories..."
for ((i = 1 ; i <= 1000 ; i++)); do
  contents=$(curl -sSlf -H "Authorization: Bearer ${auth_token}" "${bitbucket_api_url}/repositories/${tenant}?page=${i}") || die " * Error getting list of repositories from ${APP}, exiting."
  echo "$contents" > ${TEMPDIR}/bburl_${i}.json
  if jq -e '.next | length == 0' >/dev/null; then 
    break
  fi <<< "$contents"
done

repositories=$(cat ${TEMPDIR}/bburl_*.json | jq -r '.values[].full_name' | sort)
if ! [[ -z ${repositories} ]]; then
  log " * Starting bitbucket backup..."
  for repo in ${repositories[@]}; do
    log "   * cloning repository ${repo} to temporary directory..."
    git clone --quiet https://x-token-auth:"${auth_token}"@bitbucket.org/${repo}.git ${TEMPDIR}/${repo} >/dev/null || die " * Error while cloning repository ${repo}, exiting."
  done
else
  die " * List of repositories to clone is empty! Exiting."
fi

cd ${TEMPDIR} || die "Error swiching to tempdir ${TEMPDIR} to start compression of repositories, exiting."
log " * Compressing repositories to archive BITBUCKET-backup-${TODAY}.tar.gz..."
tar czpf BITBUCKET-backup-${TODAY}.tar.gz ${tenant} >/dev/null || die " * Error while compressing repositories, exiting."
log " * moving backup file to permanent storage location..."
mv BITBUCKET-backup-${TODAY}.tar.gz ${BACKUP_FOLDER}/ || die " * Error while moving BITBUCKET-backup-${TODAY}.tar.gz to ${BACKUP_FOLDER}/, exiting."
log " * Cleaning up..."
cleanup
log " * ${APP} backup finished successfully after ${SECONDS} seconds."
}

backup_confluence() {
set -o pipefail
log "* Starting ${APP} backup..."

log " * Requesting start of ${APP} backup from atlassian cloud..."
log "    * backup with attachments requested: ${attachments}"
## The $BKPMSG variable is used to save and print the response
BKPMSG=$(curl -sSfL -u ${EMAIL}:${API_TOKEN} -H "X-Atlassian-Token: no-check" -H "X-Requested-With: XMLHttpRequest" -H "Content-Type: application/json"  -X POST "https://${INSTANCE}/wiki/rest/obm/1.0/runbackup" -d "{\"cbAttachments\":\"${attachments}\" }" || die " * Error during request to atlassian cloud to start confluence backup, exiting.")

## Uncomment below line to print the response message also in case of no errors ##
#log "Response message: $BKPMSG \n"

## Checks if the backup procedure has failed
if [[ "$(echo "$BKPMSG" | grep -ic backup)" -ne 0 ]]; then
  die " * Error during request to atlassian cloud to start ${APP} backup, exiting. Response from atlassian cloud: $BKPMSG"
fi

# Checks if the backup process completed for the number of times specified in progress_retries variable
for (( c=1; c<=${progress_retries}; c++ )); do
  log "    * waiting for atlassian cloud to finish backup..."
  PROGRESS_JSON=$(curl -sSfL -u ${EMAIL}:${API_TOKEN} https://${INSTANCE}/wiki/rest/obm/1.0/getprogress.json || die " * Error while requesting backup generation progress, exiting.")
  FILE_NAME=$(echo "$PROGRESS_JSON" | sed -n 's/.*"fileName"[ ]*:[ ]*"\([^"]*\).*/\1/p')

  ## PRINT BACKUP STATUS INFO ##
  # log "$PROGRESS_JSON"

  if [[ ${PROGRESS_JSON} == *"error"* ]]; then
    break
  fi

  if [[ ! -z "${FILE_NAME}" ]]; then
    break
  fi

  # Waits for the amount of seconds specified in progress_sleep variable between a check and the other
  sleep ${progress_sleep}
done

# If the backup is not ready after the configured amount of progress_retries, it ends the script.
if [[ -z "$FILE_NAME" ]]; then
  log " * last JSON response from atlassian cloud:"
  log "${PROGRESS_JSON}"
  log ""
  die " * atlassian cloud failed or took too long to create a backup after ${SECONDS} seconds, exiting."
else
  ## PRINT THE FILE TO DOWNLOAD ##
  log " * Atlassian cloud finished the generation of the backup."
  log " * Now downloading backup file: https://${INSTANCE}/wiki/download/${FILE_NAME} to ${BACKUP_FOLDER}/CONFLUENCE-backup-${TODAY}.zip ..."
  curl -sSfL -u ${EMAIL}:${API_TOKEN} "https://${INSTANCE}/wiki/download/${FILE_NAME}" -o "${BACKUP_FOLDER}/CONFLUENCE-backup-${TODAY}.zip" || die " * Error while downloading ${APP} backup from atlassian cloud, exiting."
fi
log " * ${APP} backup finished successfully after ${SECONDS} seconds."
}

backup_jira(){
set -o pipefail
# required for cloud backups
EXPORT_TO_CLOUD=true

log "* Starting ${APP} backup..."
log " * Requesting start of ${APP} backup from atlassian cloud..."
log "    * backup with attachments requested: ${attachments}"
 
## The $BKPMSG variable is used to save and print the response
BKPMSG=$(curl -sSLf -u ${EMAIL}:${API_TOKEN} -H "Accept: application/json" -H "Content-Type: application/json" --data-binary "{\"cbAttachments\":\"${attachments}\", \"exportToCloud\":\"${EXPORT_TO_CLOUD}\"}" -X POST https://${INSTANCE}/rest/backup/1/export/runbackup || die " * Error during request to atlassian cloud to start ${APP} backup, exiting.")
 
## Uncomment below line to print the response message also in case of no errors ##
# log "Response: $BKPMSG"
 
# If the backup did not start print the error messaget returned and exits the script
if [ "$(echo "$BKPMSG" | grep -ic error)" -ne 0 ]; then
  die " * Error during request to atlassian cloud to start ${APP} backup, exiting. Response from atlassian cloud: $BKPMSG"
fi
 
# If the backup started correctly it extracts the taskId value from the response
# As an alternative you can call the endpoint /rest/backup/1/export/lastTaskId to get the last task-id
TASK_ID=$(echo "$BKPMSG" | sed -n 's/.*"taskId"[ ]*:[ ]*"\([^"]*\).*/\1/p')
 
# Checks if the backup process completed for the number of times specified in progress_retries variable
for (( c=1; c<=${progress_retries}; c++ )); do
  log "    * waiting for atlassian cloud to finish backup..."
  PROGRESS_JSON=$(curl -sSLf -u ${EMAIL}:${API_TOKEN} -X GET https://${INSTANCE}/rest/backup/1/export/getProgress?taskId=${TASK_ID} || die " * Error while requesting backup generation progress, exiting.")
  FILE_NAME=$(echo "${PROGRESS_JSON}" | sed -n 's/.*"result"[ ]*:[ ]*"\([^"]*\).*/\1/p')
 
  # Print progress message
  # log "${PROGRESS_JSON}"
 
  if [[ ${PROGRESS_JSON} == *"error"* ]]; then
    break
  fi
 
  if [ ! -z "${FILE_NAME}" ]; then
    break
  fi
 
  # Waits for the amount of seconds specified in progress_sleep variable between a check and the other
  sleep ${progress_sleep}
done
 
# If the backup is not ready after the configured amount of progress_retries, it ends the script.
if [[ -z "$FILE_NAME" ]]; then
  log " * last JSON response from atlassian cloud:"
  log "${PROGRESS_JSON}"
  log ""
  die " * atlassian cloud failed or took too long to create a backup after ${SECONDS} seconds, exiting."
else
  ## PRINT THE FILE TO DOWNLOAD ##
  log " * Atlassian cloud finished the generation of the backup."
  log " * Now downloading backup file: https://${INSTANCE}/plugins/servlet/${FILE_NAME} to ${BACKUP_FOLDER}/JIRA-backup-${TODAY}.zip ..."
  curl -sSLf -u ${EMAIL}:${API_TOKEN} -X GET "https://${INSTANCE}/plugins/servlet/${FILE_NAME}" -o "${BACKUP_FOLDER}/JIRA-backup-${TODAY}.zip" || " * Error while downloading ${APP} backup from atlassian cloud, exiting."
fi
log " * ${APP} backup finished successfully after ${SECONDS} seconds."
}

print_help() {

echo "
  ${SCRIPT} - create a backup of an atlassian cloud tenant

  Options:

  generic:
    -h | --help                    display help
    -A | --app [APPNAME]           which cloud app to backup. possible APPNAMEs are:
                                     * bitbucket
                                     * confluence
                                     * jira

    -a | --with-attachments        include attachments in the backup (only valid for confluence and jira)
                                   caution: atlassian allows this only every two days, otherwise backups will fail

    -B | --backup-folder [FOLDER]  location on local filesystem where the backup should be stored

    -t | --tenant [TENANT]         name of the cloud tenant to backup. e.g. if your domain is "https://mycompany.atlassian.net",
                                   the tenant would by "mycompany" (without quotes)

    --print-info                   print some details about the backup process before the backup starts

    --progress-retries [NUMBER]    number of times the script will check if the backup has been prepared. use this value
                                   together with '--progress-sleep' to define maximum interval the script will wait for
                                   the backup to finish (retries * seconds). defaults to 300 retries.

    --progress-sleep [SECONDS]     seconds the script will wait between backup progress checks. defaults to 30 seconds.

    --retention [DAYS]             maximum number of days to keep old backups. defaults to 32 days

    --timezone [TZ]                timezone for correct timestamping of the backup file. defaults to 'Europe/Berlin'

  bitbucket:                       oauth credentials can be created in https://bitbucket.org/<TENANT>/workspace/settings/api

    --oauth-key [KEY]              value of the oauth key set in bitbucket. must at least be able to read projects from bitbucket
    --oauth-secret [SECRET]        value of the oauth secret set in bitbucket.


  confluence/jira:                 API tokens can be defined in https://id.atlassian.com/manage-profile/security/api-tokens
                                   The account needs admin permissions on the atlassian tenant to perform backups

    --api-token [TOKEN]            value of the API token
    --email-address [EMAIL]        corresponding email address of the account that created the API token
"
exit 0
}

if [[ -z $1 ]]; then print_help; fi
OPTS=haA:B:It:
LONGOPTS=help,app:,api-token:,backup-folder:,email-address:,oauth-key:,oauth-secret:,print-info,progress-retries:,progress-sleep:,retention:,tenant:,timezone:,with-attachments
! PARSED=$(getopt --options=${OPTS} \
                  --longoptions=${LONGOPTS} \
                  --name "${0}" \
                  -- "${@}")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
  die "getopt parser reported an error parsing arguments, aborting."
fi

eval set -- "$PARSED"
while [[ ( ${discard_opts_after_doubledash} -eq 1 ) || ( $# -gt 0 ) ]]; do
  case "$1" in
    -h|--help)
      print_help
      ;;
    -A|--app)
      APP="$2"
      shift
      case ${APP} in
        bitbucket)  backup="bitbucket" ;;
        confluence) backup="confluence" ;;
        jira)       backup="jira" ;;
        *)          die " * APP unknown, exiting. (hint: use either bitbucket, confluence or jira for --app)" ;;
      esac
      ;;
    -a|--with-attachments)
      attachments="true"
      ;;
    --api-token)
      API_TOKEN="$2"
      shift
      ;;
    -B|--backup-folder)
      BACKUP_FOLDER="$2"
      shift
      ;;
    --email-address)
      EMAIL="$2"
      shift
      ;;
    --oauth-key)
      oauth_key="$2"
      shift
      ;;
    --oauth-secret)
      oauth_secret="$2"
      shift
      ;;
    --print-info)
      print_info=1
      ;;
    --progress-retries)
      progress_retries="$2"
      shift
      ;;
    --progress-sleep)
      progress_sleep="$2"
      shift
      ;;
    --retention)
      retention="$2"
      shift
      ;;
    --timezone)
      timezone="$2"
      shift
      ;;
    -t|--tenant)
      tenant="$2"
      shift
      ;;
    --) if [[ ${discard_opts_after_doubledash} -eq 1 ]]; then break; fi
      ;;
    *) extra_args=("${extra_args[@]}" "$1")
      ;;
  esac
  shift
done

backup_error_file="/var/lock/${APP}_backup_faulty"
backup_in_progress_file="/var/lock/${APP}_in_progress"
INSTANCE="${tenant}.atlassian.net"
TODAY=$(TZ=$TIMEZONE date +%d-%m-%Y_%H%M)
trap "die '!! backup interrupted !! lock file created: **${backup_error_file}**, future backups disabled!'" INT SIGHUP SIGINT SIGTERM

check_vars
check_for_binaries
check_backup_folder
check_backup_error_lockfile
check_backup_in_progress_lockfile
create_lockfile
[[  ${print_info} -eq 1 ]] && print_backup_info
case ${backup} in
  bitbucket)
    create_tempdir
    backup_bitbucket
    ;;
  confluence)
    backup_confluence
    ;;
  jira)
    backup_jira
    ;;
  *) die " * Unknown backup type requested, exiting."
    ;;
esac
remove_old_backups
cleanup
