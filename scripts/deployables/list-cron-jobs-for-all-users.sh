#!/bin/bash -ue

source /usr/local/lib/acro/bash/functions.sh

function main () {
  require_root
  list_jobs
}

function list_jobs(){
  local USERTAB
  local FILTERED
  local USER
  cut -f1 -d':' < /etc/passwd | while IFS= read -r USER; do
    USERTAB="$(/usr/bin/crontab -u "$USER" -l 2>&1)" || true
    FILTERED="$(echo "$USERTAB"| /bin/grep -vE '^#|^$|no crontab for|cannot use this program')" || true
    if ! test -z "$FILTERED"; then
      echo "# ------ ${BOLD}${USER}${UNBOLD} ------";
      if [[ "${FILTERED}" =~ 'Authentication token is no longer valid'* ]]; then
        echo "# (user's password has expired; cannot read their cron tab)"
      else
        echo "${FILTERED}";
      fi
      echo "";
    fi;
  done
}

main "$@"
