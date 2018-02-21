#!/bin/bash
#
# update firewall ipset entries
# based on dynDNS hostnames

PATH="${PATH}:/sbin"
set -o pipefail

logger="$(which logger)"

log() {
  logdate=$(date "+%h %d %H:%M:%S")
  logproc=$(echo $$)
  logmessage="$logdate ${HOSTNAME} update-arge-vpn-dynip-clients.sh[${logproc}]: (${USER}) $1"
  echo "${logmessage}"
  ${logger} "$1"
}

die() {
  logdate=$(date "+%h %d %H:%M:%S")
  logproc=$(echo $$)
  logmessage="$logdate ${HOSTNAME} update-arge-vpn-dynip-clients.sh[${logproc}]: (${USER}) $1"
  echo "${logmessage}"
  ${logger} "$1"
  exit 1
}

BINARIES=(file host ipset)
for binary in "${BINARIES[@]}" ; do
  if ! [[ -x $(which ${binary} 2>/dev/null) ]]; then
    die "${binary} binary not found, exiting."
  fi
done

clientlist="/etc/update-ipset-dyndns.list"
clientips=()
ip=""
ipset_online="dynip"
ipset_swap="dynip-swap"

log "performing pre-flight checks..."
if ! [[ -f ${clientlist} ]]; then
  die "expected file with dyndns clients does not exist, aborting."
else
  log "  - file ${clientlist} exists."
fi
if ! [[ "$(file -b --mime-type ${clientlist})" == "text/plain" ]]; then
  die "file ${clientlist} is not in text/plain format, exiting."
else
  log "  - file ${clientlist} has correct format and mime type."
fi

log "  - reading hostnames from ${clientlist}..."
clients=($(egrep -v '^(\#|\s|$|[A-Za-z0-9\.]+\s+)' ${clientlist} 2>/dev/null || die "could not read hostnames from ${clientlist}, exiting."))

log "resolving ${#clients[@]} dynamic hostnames to IP addresses..."
for client in ${clients[@]}; do
  log "  - resolving ${client}..."
  ip="$(host -t A ${client} 2>/dev/null | awk '{print $4}')"
  if [[ $? -ne 0 ]]; then
    log "  - could not resolve ${client} to IP, skipping."
    ip=""
  else
  log "  - ${client} has IP ${ip}"
  clientips+=("${ip}")
  fi
done

log "removing duplicate IP addresses (if any)..."
readarray -t clientipsunique < <(printf '%s\n' "${clientips[@]}" | awk '!x[$0]++')

log "testing if ipsets '${ipset_online}' '${ipset_swap}' exist..."
for IPSET in ${ipset_online} ${ipset_swap}; do
  if ! ipset list -t | egrep -q Name.*${IPSET} 2>/dev/null ; then
    log "  - ipset ${IPSET} does not exist, creating..."
    ipset create ${IPSET} hash:ip || die "error creating ipset ${IPSET}, exiting."
    log "  - successfully created ipset ${IPSET}."
  else
    log "  - ipset ${IPSET} exists, skipping"
  fi
done

log "flushing ipset ${ipset_swap} before adding new IP addresses..."
ipset flush ${ipset_swap} || die "error flushing ipset ${ipset_swap}, exiting."
log "flushed ipset ${ipset_swap}."

log "adding IP addresses to ipsets..."
for address in ${clientipsunique[@]}; do
  log "  - adding IP ${address} to ipset ${ipset_swap}."
  ipset -\! add ${ipset_swap} ${address} || die "error adding IP ${address} to ipset ${ipset_swap}, exiting."
done
log "added ${#clientipsunique[@]} addresses to ipset."

log "swapping ipset ${ipset_swap} to production..."
ipset swap ${ipset_swap} ${ipset_online} || die "error swapping ipsets, exiting."
ipset flush ${ipset_swap} 2>&1 >/dev/null
log "successfully swapped sets, firewall has been updated. all done, bye."
exit 0
