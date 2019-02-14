#!/bin/bash

#### GPL ####
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.


### check if user is root
if [ "$(id -u)" != "0" ]; then
  echo "  please run script with root permissions"
  exit 1
fi

### define defaults for global variables
LVM_NAME=''
LVM_SIZE=''
EXAMPLE=""
FREE_TYPE=false
FREESPACELIST="Free disk space: \n"
NO_PROMPT=false

###########################
### begin function block 

# parse and validate input for lvm increase, we only work with MB as unit so only a number is required
verify_size ()
{
  if [[ "$1" =~ ^[0-9]+$ ]]; 
   then  
     if [ -z "$LVM_SIZE" ]
     then
       LVM_SIZE=$1;
     else
       echo "  LVM increase already defined (${LVM_SIZE}m)."
     fi
   else 
     echo "  please only enter digits, value will be considered as MB" ; 
   fi 
}

# parse and validate input for lvm name, make sure the lvm exists, also make sure only one lvm is handled 
verify_name ()
{
  if  lvs | grep $1 > /dev/null 2>&1 ; 
   then
     if [ -z "$LVM_NAME" ]
     then
       LVM_NAME=$1 ;
     else
       echo "  LVM name already defined ($LVM_NAME), you can only increase one LVM per script call"
     fi
   else 
     echo "  $1 is not a valid input";
   fi 
}

# this block allows a random order of parameters and displays help if requested
check_input () 
{
  case $1 in
    "noprompt")  NO_PROMPT=true
      ;;
    "help"|"-h")  
      echo -e "  this script can be used to resize a lvm and extend the coresponding vg with existing free diskspace or a new device"
      echo -e "    usage: $0 [lvm-name] [size in MB] (eg.: $0 lv_home 2048 )\n"
      echo -e "  the noprompt parameter is optional and will supress all confirmation dialogs and assumes certian parameters."
      echo -e "  only use this parameter if you already have experience with this script (eg.: $0 lv_home 2048 noprompt )\n"
      exit 0
      ;;
    [0-9]*)  verify_size $1
      ;;
    *)  verify_name $1
      ;;
   esac

}

# lvm resize block with optional user confirmation
resize_lvm ()
{
  LVM_NAME=$1
  LVM_SIZE=$2
  while ( true )
  do
    # user confirmation can be skipped if script was started with noprompt parameter
    if [ "$NO_PROMPT" == "false" ]
    then
      read -p "  Increase $LVM_NAME by ${LVM_SIZE}m? (yes/NO) " PROMPT_YN
    else
      PROMPT_YN="yes"
    fi
    # if prompted yes, resize the lvm and the filesystem
    case $PROMPT_YN in
      "yes"|"YES"|"y"|"Y")  
        lvresize -r -L+${LVM_SIZE}M $(lvs -o lv_path | grep $LVM_NAME) > /dev/null 2>&1
        echo "  LVM ${LVM_NAME} increased by ${LVM_SIZE}m, new value: $(lvs -o lv_name,lv_size | grep  $LVM_NAME | awk '{ print $2 }')"
        exit 0
        ;;
      "no"|"NO"|"n"|"N"|"")
        echo " abort"
        exit 0
        ;;  
      *)
        echo "  Please write yes or no!"
        ;;
    esac
  done    

}

# list disks
function rescan_scsi ()
{
  # rescan all devices for new diveses and size changes 
  for i in `ls /sys/class/scsi_device/`
  do 
    echo 1 > /sys/class/scsi_device/$i/device/rescan
  done
}

verify_free_space ()
{
  # this block determins if there is enought free space on any connected disk
  # it iterates though all /dev/sd[a-z] devices
  #   ToDo: don't forget to verify that only valid disks are used
  for i in `ls /dev/sd[a-z]`; 
  do
    # check if there are already partitions on the disk, reason for this is, that parted output differs between partitioned and unpartitioned disks 
    PARTCOUNT=$(parted $i unit MB print free  2> /dev/null  | grep primary)  
    if [ -n "$PARTCOUNT" ]
    then
      FREE=$(parted $i unit MB print free 2> /dev/null  | grep 'Free Space' | tail -n1 | awk '{print $3}' | sed -e 's/[a-Z]//g' | awk 'BEGIN {FS="."}{print $1}' )
      FREE=$( expr ${FREE} - 1)
      # don't configure 2 or more volume groups on the same disk, if you need more than one volume group on a disk, you have to disable the check and also adapt the pv/vg resize part
      if [ -n "$(pvs | grep ${i} | grep ${VG_NAME})" ] 
        then
        # only resize the partition if either the partition or the partition and the remaining vg space is big enough to handle the lvm increase
        if (( $LVM_SIZE <= $( expr ${FREE} + ${VGS_SIZE} ) )) 
        then 
            echo "  ${FREE}m free space on $i"
            DEVICE=$i
            FREE_TYPE="resizeable"
        else
          FREESPACELIST="${FREESPACELIST}  $i free: $FREE MB\n"
        fi
      fi
    else
      # normalize free space value so that it can be parsed by the script
      UNPART=$(parted $i unit MB print free 2> /dev/null | grep sd[a-z] | awk '{ print $3 }' | sed -e 's/[a-Z]//g'  | awk 'BEGIN {FS="."}{print $1}' )
      if [ -n "$UNPART" ] 
      then
        # if the new disk has enough space, a new partiton and phisical volume will be created 
        if (( $LVM_SIZE <= $UNPART )) 
        then 
          echo "  $i is unpartitioned and has ${UNPART}m free space."
          FREE_TYPE="unpartitioned"
          EXAMPLE=$i
        else
          FREESPACELIST="$FREESPACELIST  $i free: $UNPART MB\n"
        fi
      fi
    fi    
  done
}

# this block will ask the user which devices should be used for the new partition, if noprompt parameter was set, the device will be assumed based on earlier evaluation steps
function define_device ()
{
  LOOP_RUN=false
  while [ -z "$DEVICE" ] ; 
    do 
      if [ "$NO_PROMPT" == "false" ]
      then
        read -p "  Select device (e.g.: ${EXAMPLE}): " TMPDEV
      elif [ "$LOOP_RUN" == "true" ]
      then
        echo " can't automatically assign device - abort"
        ecit 1
      else
        # example is the most likely device and in most cases can be safely used, if this is not the case in your system, don't activate noprompt mode
        TMPDEV=${EXAMPLE}
      fi
      case $TMPDEV in
        /dev/sd[a-z]|sd[a-z])  
          DEVICE=$(ls /dev/sd[a-z] | grep $TMPDEV)
          LOOP_RUN=true
          ;;
        *)  
          DEVICE=""
          LOOP_RUN=true
          ;;
      esac
   done
}

# based on user input or script evaluation a new partition and pv will be created and added to the vg, afterwards the lvm will be resized
create_partition ()
{
  while ( true )
  do
    if [ "$NO_PROMPT" == "false" ]
    then
      read -p "  Create new partition on $DEVICE? (yes/NO) " PROMPT_YN
    else
      PROMPT_YN="yes"
    fi
    case $PROMPT_YN in
      "yes"|"YES"|"y"|"Y")
          # parted in script mode will not ask for user input
          parted ${DEVICE} mklabel msdos --script > /dev/null 2>&1
          parted -s ${DEVICE} mkpart primary 0% 100% > /dev/null 2>&1
          # if parition creation fails, exit script
          if [ $? -ne 0 ]; then
            echo "  could not create partition"
            exit 1
          fi
          # check for not labled primary partition, only unused partitions, like the one we just created, should be unlabled 
          PART_NUM=$(parted ${DEVICE} print free | /bin/grep primary | awk '{ if (( $NF == "primary" )) print $1 }')
          parted ${DEVICE} set ${PART_NUM} lvm on
          partprobe
          vgextend $(lvs | grep $LVM_NAME | awk '{print $2}') ${DEVICE}${PART_NUM}
          resize_lvm $LVM_NAME $LVM_SIZE
        ;;
      "no"|"NO"|"n"|"N"|"")
        echo " abort"
        exit 0
        ;;  
      *)
        echo "  Please write yes or no!"
        ;;
    esac
  done    
}

resize_partition ()
{
  # we want to resize the last partition because, if a disk is extended, new space will added to the end of the disk.
  # with this command we will extract the last parition which is labled lvm, if no lvm parition exists this part will not be called from upstream functions
  LVM_PARTITION_NUMBER=$(parted ${DEVICE} unit MB print free | /bin/grep lvm | awk '{print $1}'0 | tail -1)
  while ( true )
  do
    if [ "$NO_PROMPT" == "false" ]
    then
      read -p "  Resize partition ${DEVICE}${LVM_PARTITION_NUMBER}? (yes/NO) " PROMPT_YN
    else
      PROMPT_YN="yes"
    fi
    case $PROMPT_YN in
      "yes"|"YES"|"y"|"Y")
        parted -s ${DEVICE} resizepart ${LVM_PARTITION_NUMBER} 100%
        # if the resize fails exit script
        if [ $? -ne 0 ]; then
          echo "  could not resize partition"
          exit 1
        fi
        partprobe
        pvresize ${DEVICE}${LVM_PARTITION_NUMBER}
        resize_lvm $LVM_NAME $LVM_SIZE
        ;;
      "no"|"NO"|"n"|"N"|"")
        echo " abort"
        exit 0
        ;;  
      *)
        echo "  Please write yes or no!"
        ;;
    esac
  done    
 
}

### end function block 
###########################

###########################
### begin script main body

## ToDo: rethink this block

# only three script parameters are supported
if [ $# -gt 0 ]; then
     if [ -n "$1" ] ; then check_input $1; fi
     if [ -n "$2" ] ; then check_input $2; fi
     if [ -n "$3" ] ; then check_input $3; fi
fi

# if no valid lvm could be extracted from the parameters, prompt for lvm_name, in noprompt mode script aborts
while [ -z "$LVM_NAME" ] ; 
do 
  if [ "$NO_PROMPT" == "true" ]
  then
    echo " invalid input - abort"
    exit 1
  fi
  read -p '  LVM name (e.g.: lv_home): ' TMPNAME ; verify_name $TMPNAME ; 
done
# if no valid size could be extracted from the parameters, prompt for lvm_size, in noprompt mode script aborts
while [ -z "$LVM_SIZE" ] ; 
do 
  if [ "$NO_PROMPT" == "true" ]
  then
    echo " invalid input - abort"
    exit 1
  fi
  read -p '  LVM increase (e.g.: 1024): ' TMPSIZE ; verify_size $TMPSIZE ; 
done
## block end

# get volume group name and size based on the lvm 
VG_NAME=$(lvs  | grep $LVM_NAME | awk '{ print $2 }')
VGS_SIZE=$(vgs --unit m | grep ${VG_NAME} | awk '{ print $7}' | awk 'BEGIN {FS="."}{print $1}' | sed -e 's/[a-Z]//g')

# decide if volume group space is enough or if partition or vg needs to be extended 
if (( $LVM_SIZE  <= $VGS_SIZE  ))
then 
  # resize lvm if there is enough free space in the vg, a partition or vg extension is discouraged at this point
  echo "  Free space in VG: ${VGS_SIZE} MB"
  resize_lvm $LVM_NAME $LVM_SIZE
else
  echo "  Volume group $VG_NAME to small for automatic increase, please create new partition."
  rescan_scsi
  verify_free_space
fi

# script only continues if there is enough free space, otherwise it aborts
case $FREE_TYPE in 
  "resizeable")
    resize_partition
    ;;
  "unpartitioned")
      define_device 
      create_partition      
    ;;
  *)
    echo "  Not enough space left on any disk, please add a new disk, or extend existing one."
    echo -e "\n`pvs`\n"
    echo -e "  $FREESPACELIST"
    exit 1
    ;;
esac

### end script main body
###########################
