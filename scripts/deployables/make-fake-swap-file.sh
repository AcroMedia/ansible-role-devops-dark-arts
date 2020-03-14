#!/bin/bash -ue

####################
# For tiny AWS servers that have no swap space by default.
# A tiny, slow swap file is preferable to having the server crash and need to be rebooted.
# This is surely a band-aid measure. A better solution would be to have a separately mounted volume.
####################


SWAP_FILE="/swapfile"
MIN_DISK_FREE_GB=4
SWAP_FILE_SIZE_MB=512

function main () {

  grep swap /etc/fstab && {
    err "Not running because I found the word 'swap' in /etc/fstab."
    exit 1
  }

  test -e "$SWAP_FILE" && {
    err "Swap file already exists."
    exit 0
  }

  if ! is_positive_integer "$SWAP_FILE_SIZE_MB"; then
    err "Invalid value specified for SWAP_FILE_SIZE_MB: $SWAP_FILE_SIZE_MB"
    exit 1
  fi

  if ! is_positive_integer "$MIN_DISK_FREE_GB"; then
    err "Invalid value specified for MIN_DISK_FREE_GB: $MIN_DISK_FREE_GB"
    exit 1
  fi

  MIN_DISK_FREE_KB=$(( MIN_DISK_FREE_GB * 1024 * 1024))
  if ! is_positive_integer "$MIN_DISK_FREE_KB"; then
    err "Unexpected value was returned for MIN_DISK_FREE_KB: $MIN_DISK_FREE_KB"
    exit 1
  fi

  KB_FREE="$(df -P / |tail -1|awk '{print $4}')" # <<<<  Making the assumption SWAP_FILE will reside on the root / partition.
  if ! is_positive_integer "$KB_FREE" ; then
    err "Unexpected error trying to calculate free space"
    exit 1
  fi

  if [ "$KB_FREE" -lt $MIN_DISK_FREE_KB ]; then
    err "There is not enough space left on the drive to safely create a swap file."
    cerr "Min free KB:    $MIN_DISK_FREE_KB"
    cerr "Actual free KB: $KB_FREE"
    exit 1
  fi


  (set -x && dd if=/dev/zero of="${SWAP_FILE}" bs=1M count="${SWAP_FILE_SIZE_MB}")
  (set -x && chmod 600 "$SWAP_FILE")
  (set -x && mkswap "$SWAP_FILE")
  (set -x && swapon "$SWAP_FILE")
  (set -x && echo "$SWAP_FILE swap swap defaults 0 0" |tee -a /etc/fstab)

  echo "OK: $(ls -laFh "$SWAP_FILE")"


}

function is_positive_integer() {
  local WHAT="$*"
  if [[ "$WHAT" =~ ^[0-9]+$ ]]; then
    true
  else
    false
  fi
}

function err () {
  bold_feedback "Err" "$@"
}

function bold_feedback () {
  local PREFIX="${1:-"bold_feedback received no arguments"}"
  shift || true
  local MESSAGE="$*"
  cerr "${BOLD}${PREFIX}:${UNBOLD} ${MESSAGE}"
}

function cerr () {
  >&2 echo "$@"
}


BOLD=$(tput bold  2>/dev/null) || BOLD=''
UNBOLD=$(tput sgr0 2>/dev/null)  || UNBOLD=''

main "$@"
