#!/bin/bash
#
# calculate swap usage from /proc
# uses 'column' from bsdmainutils
#
# b2c@dest-unreachable.net

echo -en "calculating...\n\n"
{
SUM="0"
TOTAL="0"
for DIR in $(find /proc/ -maxdepth 1 -type d | egrep "^/proc/[0-9]") ; do
  PID=$(echo ${DIR} | cut -d / -f 3)
  PROGNAME=$(ps --no-headers -p ${PID} -o args | cut -c1-80)
  for SWAP in $(grep Swap ${DIR}/smaps 2>/dev/null| awk '{ print $2 }'); do
    let SUM=${SUM}+${SWAP}
  done
  echo " PID ${PID} ~ Swap used: ${SUM}K ~ ${PROGNAME}" | grep -v 'Swap used: 0K'
  let OVERALL=${OVERALL}+${SUM}
  TOTAL="${OVERALL}"
  SUM=0
done
}> >(sort -u -n -k6,6 | column -t -s '~')

echo -en "" | cat
echo -en "---------------------------------\n"
echo -en " Total ~ ~ Swap used: ${TOTAL}K\n" | column -t -s '~'
echo -en "\n"
