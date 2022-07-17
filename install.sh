#!/usr/bin/env bash
#  ___  _    _          _ __      
# / __|| |_ | |_   ___ | '_ \ ___ 
# \__ \|  _||   \ / _ \| .__// -_)
# |___/ \__||_||_|\___/|_|   \___|

GEN_MAC=$(echo '00 60 2f'$(od -An -N3 -t xC /dev/urandom) | sed -e 's/ /:/g' | tr '[:lower:]' '[:upper:]')
NEXTID=$(pvesh get /cluster/nextid)
RELEASE=$(curl -sX GET "https://api.github.com/repos/home-assistant/operating-system/releases" | awk '/tag_name/{print $4;exit}' FS='[""]')
STABLE="8.3"
YW=`echo "\033[33m"`
BL=`echo "\033[36m"`
RD=`echo "\033[01;31m"`
BGN=`echo "\033[4;92m"`
GN=`echo "\033[1;92m"`
DGN=`echo "\033[32m"`
CL=`echo "\033[m"`
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap cleanup EXIT

function error_exit() {
  trap - ERR
  local reason="Unknown failure occured."
  local msg="${1:-$reason}"
  local flag="${RD}‼ ERROR ${CL}$EXIT@$LINE"
  echo -e "$flag $msg" 1>&2
  [ ! -z ${VMID-} ] && cleanup_vmid
  exit $EXIT
}

function cleanup_vmid() {
  if $(qm status $VMID &>/dev/null); then
    if [ "$(qm status $VMID | awk '{print $2}')" == "running" ]; then
      qm stop $VMID
    fi
    qm destroy $VMID
  fi
}

function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null

function header_info {
echo -e "${BL}
         ___  _    _          _ __      
        / __|| |_ | |_   ___ | '_ \ ___ 
        \__ \|  _||   \ / _ \| .__// -_)
        |___/ \__||_||_|\___/|_|   \___|
${CL}"
}
header_info

function msg_info() {
    local msg="$1"
    echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
    local msg="$1"
    echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}
function create_vm() {
        clear
        header_info
		BRANCH=${STABLE}
		VMID=$NEXTID
		VM_NAME=Home-Assistant
	        CORE_COUNT="2"
	        RAM_SIZE="4096"
	        BRG="vmbr0"
		MAC=$GEN_MAC
	        VLAN=""
		START_VM="no"

}

create_vm

while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=( "$TAG" "$ITEM" "OFF" )
done < <(pvesm status -content images | awk 'NR>1')
if [ $((${#STORAGE_MENU[@]}/3)) -eq 0 ]; then
  echo -e "'Disk image' needs to be selected for at least one storage location."
  die "Unable to detect valid storage location."
elif [ $((${#STORAGE_MENU[@]}/3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --title "Storage Pools" --radiolist \
    "Which storage pool you would like to use for the HAOS VM?\n\n" \
    16 $(($MSG_MAX_LENGTH + 23)) 6 \
    "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3) || exit
  done
fi
URL=https://github.com/home-assistant/operating-system/releases/download/${BRANCH}/haos_ova-${BRANCH}.qcow2.xz
sleep 2
wget -q --show-progress $URL
FILE=$(basename $URL)
unxz $FILE
STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
  nfs|dir)
    DISK_EXT=".qcow2"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format qcow2"
    ;;
    
  btrfs)
    DISK_EXT=".raw"
    DISK_REF="$VMID/"
    DISK_FORMAT="subvol"
    DISK_IMPORT="-format raw"
    ;;
    
esac
for i in {0,1}; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done

qm create $VMID -agent 1 -bios ovmf -cores $CORE_COUNT -memory $RAM_SIZE -name $VM_NAME -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN \
  -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE%.*} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF},efitype=4m,size=4M \
  -scsi0 ${DISK1_REF},size=32G >/dev/null
qm set $VMID \
  -boot order=scsi0 >/dev/null
qm set $VMID -description "# Home Assistant OS" >/dev/null

if [ "$START_VM" == "yes" ]; then
qm start $VMID
fi
echo -e "\n\e[1;3;5;42mCompleted Successfully!\e[0m\n"
