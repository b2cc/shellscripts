#!/bin/bash

BOTLIST="/tmp/botlist.txt"

# clean up existing botlist
[[ -f ${BOTLIST} ]] && rm -f ${BOTLIST}

# grab new lists
echo " * Grabbing new botlists..."

## ichido blocklist
curl -fsSl https://files.ichi.do/recommended-nginx-block-ai-bots.conf \
  | awk -F'"' '{print $2}' \
  >> ${BOTLIST}

## nginx ultimate bot blocklist
curl -fsSl https://raw.githubusercontent.com/mitchellkrogza/nginx-ultimate-bad-bot-blocker/refs/heads/master/_generator_lists/bad-user-agents.list \
  | grep -Ev '^Evil' \
  >> ${BOTLIST}

# construct new ingress config snippet
echo " * Generating ingress-nginx configmap snippet..."
echo -en "\n  block-user-agents: |\n    "
grep -Ev '^$|^#|^[0-9]|^aa|^b2w|^vsw|FediDB|[Mm]ozilla|^oBot|[uU]ptime' ${BOTLIST} \
  | tr -d '\\' \
  | sort -u \
  | awk -F "\"" 'ORS="," {print "\"~*"$1 "\""}' \
  | sed 's/\(.*\),/\1\n /'

echo " 
 * Complete! Run 'oc edit -n ingress-nginx configmaps ingress-nginx-controller' to add it to the ingress controller.

"
exit 0
