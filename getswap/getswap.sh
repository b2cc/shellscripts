#!/bin/bash
#
# calculate swap usage from /proc
#
# 2018-02-09
# b2c@dest-unreachable.net
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

BINARIES=(awk column cut find grep sort)
for binary in "${BINARIES[@]}" ; do
  if ! [[ -x $(which ${binary} 2>/dev/null) ]]; then
    echo "${binary} binary not found, exiting." && exit 1
  fi
done

echo -en "calculating...\n\n"
{
SUM="0"
TOTAL="0"
for DIR in $(find /proc/ -maxdepth 1 -type d -regex '^/proc/[0-9]+') ; do
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
