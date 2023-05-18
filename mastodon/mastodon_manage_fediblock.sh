#!/bin/bash
#
# script to quickly limit/suspend domain on multiple mastodon instances
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
# b2c@dest-unreachable.net
#
# Report issues on github:
# * https://github.com/b2cc/shellscripts
#
# history:
# --------
# 2023-05-18 v1.0: initial version

# TODO:
# * currently none \o/

# let's script a bit more safely, shall we?
set -euf -o pipefail

# array(s)
# declare array of mastodon instances and their respective access tokens
# create the token in the Mastodon admin interface like this:
#  -> Development -> New Application
#   -> then add a token with permissions: "admin:read:domain_blocks", "admin:write:domain_blocks"
# now fill in your domains and their respective acess tokens
declare -A instance_names
#instance_names["masto1.domain.tld"]="<ACCESS_TOKEN_OF_masto1.domain.tld>"
#instance_names["masto2.tld"]="<ACCESS_TOKEN_OF_masto2.tld>"
#instance_names["..."]="..."


##############################
#                            #
# NO SERVICEABLE PARTS BELOW #
#                            #
##############################

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

# logging variable(s)
host="$(hostname -s)"
logdate=""
loglevel=""
logproc=""
logmessage=""
scriptname=$(basename $0)
user=$(whoami)
log_generic() {
  logdate=$(date "+%h %d %H:%M:%S")
  logproc=$(echo $$)
  logmessage="$logdate ${host} ${scriptname}[${logproc}]: (${user}) ${loglevel}: $1"
  echo "${logmessage}"
}

log() {
  loglevel="${white}${bold}INFO${reset}"
  log_generic "$@"
}

die() {
  loglevel="${red}${bold}ERROR${reset}"
  log_generic "$@"
  exit 1
}

trap "die 'Program interrupted! Exiting...'" SIGHUP SIGINT SIGQUIT SIGABRT

# script variable(s)
action=""
comment=""
domain=""
domain_id=""
mode=""
severity=""
dummy_arg="__dummy__"
extra_args=("${dummy_arg}")
discard_opts_after_doubledash=0 # 1=Discard, 0=Save opts after -- to ${extra_args}

# function(s)
check_for_binaries() {
BINARIES=(curl grep jq whoami)
for binary in "${BINARIES[@]}"; do
  [[ -x $(which ${binary} 2>/dev/null) ]] || die "${binary} binary not found, exiting."
done
}
print_help() {
echo "
  * ${scriptname}

  Quickly block/unblock domains across multiple Mastodon instances

  Options:

  -a | --action        which action to invoke, can be one of: 
                       'block'   - block a remote instance
                       'unblock' - unblock a remote instance
                       'list'    - print list of instances currently managed by the script
  -c | --comment       comment to add to the block action (visible in admin web interface)
  -h | --help          display help
  -d | --domain        name of the domain which should be blocked/unblocked
  -s | --severity      how to block the instance, can be one of 'limit'/'silence' or 'suspend'
"
exit 0
}

block_instance() {
for instance in ${!instance_names[@]}; do
  log " * ${yellow}${bold}blocking${reset} domain ${white}${bold}${domain}${reset} with action ${action} on instance ${instance}, comment: ${comment}"
  post_data() {
      cat <<EOF
{
"domain": "${domain}",
"severity": "${severity}",
"private_comment": "${comment}"
}
EOF
  }
  curl -sS \
    --fail-with-body \
    -X POST \
    --header "Authorization: Bearer ${instance_names[${instance}]}" \
    -H 'Content-Type: application/json' \
    -d "$(post_data)" \
    "https://${instance}/api/v1/admin/domain_blocks" \
    >/dev/null \
  || die " * error while invoking curl to ${action} ${domain} on ${instance}, exiting."
done
}

unblock_instance() {
for instance in ${!instance_names[@]}; do
  log " * ${green}${bold}unblocking${reset} domain ${white}${bold}${domain}${reset} on instance ${instance}..."
  domain_id=$(curl -sS \
                   --fail-with-body \
                   --header "Authorization: Bearer ${instance_names[${instance}]}" \
                   "https://${instance}/api/v1/admin/domain_blocks" \
                   | jq -r '.[] | select(.domain=="'"${domain}"'") | .id' \
             || die " * error while invoking curl to get ID of bocked domain ${domain}, exiting."
             )
  curl -sS \
    --fail-with-body \
    -X DELETE \
    --header "Authorization: Bearer ${instance_names[${instance}]}" \
    https://${instance}/api/v1/admin/domain_blocks/${domain_id} \
    >/dev/null \
    || die " * error while invoking curl to ${mode} ${domain} on ${instance}, exiting."
done
}

print_list() {
 log " * list of currently managed instances:"
 echo " *  Mastodon instances  *"
 echo " * -------------------- *"
 for instance in "${!instance_names[@]}"; do
   echo "   - ${instance} "
 done \
 | sort -n
}

[[ $# -eq 0 ]] && print_help
OPTS=a:c:d:hs:
LONGOPTS=action:,comment:,domain:,help,severity:
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
      exit 0
      ;;
    -a|--action)
      case $2 in
        block)
          mode="block"
          ;;
        list)
          mode="list"
          ;;
        unblock)
          mode="unblock"
          ;;
        *)
          die " * unknown action, must be either 'block' or 'unblock', exiting."
          ;;
      esac
      shift
      ;;
    -c|--comment)
      comment="$2"
      shift
      ;;

    -d|--domain)
      domain="$2"
      shift
      ;;
    -s|--severity)
      case $2 in
        limit|silence)
          severity="silence"
          ;;
        suspend)
          severity="suspend"
          ;;
        *)
          die " * action unknown, must be either 'limit' or 'suspend', exiting."
          ;;
      esac
      shift
      ;;

    --) if [[ ${discard_opts_after_doubledash} -eq 1 ]]; then break; fi
      ;;
    *) extra_args=("${extra_args[@]}" "$1")
      ;;
  esac
  shift
done
extra_args=("${extra_args[@]/${dummy_arg}}")

# validate variable(s)
tests_for_block_action() {
  if [[ -z ${comment} ]]; then  die " * missing 'comment', exiting."; fi
  if [[ -z ${severity} ]]; then  die " * missing 'severity', exiting."; fi
}

test_domain_name() {
  # validate domain name
  # https://stackoverflow.com/a/32910760
  if [[ -z ${domain} ]]; then die " * missing 'domain', exiting."; fi
  if ! echo "${domain}" | grep -qP '(?=^.{1,254}$)(^(?>(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)'; then
    die " * '${domain}' doesn't look like a domain name, regex test failed. exiting."
  fi
}

if [[ -z ${mode} ]]; then  die " * missing 'action', exiting."; fi

# evaluate action and run script
case ${mode} in
  block)
    tests_for_block_action
    test_domain_name
    if [[ ${severity} == "suspend" ]]; then
      echo "
  *   ${red}${bold}!! WARNING !!${reset}
  * This will defederate the domain ${domain}, meaning it will break all followers/follows,
  * delete remote accounts and posts, all of which will be an irreversible action.${reset}
  "
      read -p " * ${white}${bold}Are you sure you want to ${red}${bold}SUSPEND${reset} ${white}${bold}the domain ${red}${bold}${domain}${reset} (YES/NO): " -r
      if [[ $REPLY == YES ]]; then
        block_instance
      else
        log " * action aborted, exiting."
      fi
    else
      block_instance
    fi
    exit 0
    ;;
  list)
    print_list
    ;;
  unblock)
    test_domain_name
    unblock_instance
    ;;
  *)
    print_help
    ;;
esac

exit 0
