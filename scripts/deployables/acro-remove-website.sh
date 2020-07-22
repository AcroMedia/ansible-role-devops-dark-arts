#!/bin/bash -ue

# This toasts an entire account.
# @TODO: Let user pick values that were not automatically detected.

function main () {
  require_package 'tree'

  # Pre-flight: Need to read global conf to find out php version being used on the machine.
  ACRO_CONF="/etc/acro/add-website.conf"
  set +u
  source "${ACRO_CONF}" || {
    echo "Fatal: Missing $ACRO_CONF"
    exit 1
  }
  set -u

  # Pre-flight: Root required.
  if [[ $EUID -ne 0 ]]; then
     echo "This script must be run as root"
     exit 1
  fi

  # Pre-flight: Need root's environment to get at mysql
  mysqlshow > /dev/null 2>&1 || {
    warn "Cannot access mysql. Make sure you 'sudo -i $(basename "$0")' (or 'su -') to get root's full environment."
  }


  # Main arg
  account=${1:-}
  test -z "${account}" && {
    echo "Which account / website do you want to get rid of?"
    exit 1
  }

  project=""

  # If the account folder doesn't exist, check to see if the user specified the project instead. (i.e. a-r-w thevault instead of a-r-w chubbys thevault)
  if ! test -d "/home/${account}"; then
    PROJECT_MATCH_OUTPUT=$(find /home -mindepth 3 -maxdepth 3 -path "*/www/${account}")
    PROJECT_MATCH_LENGTH=${#PROJECT_MATCH_OUTPUT}
    if [ "$PROJECT_MATCH_LENGTH" -gt 0 ]; then
      PROJECT_MATCH_LINES=$(echo "$PROJECT_MATCH_OUTPUT"|wc -l)
      if [ "$PROJECT_MATCH_LINES" -eq 1 ]; then
        account=$(echo "$PROJECT_MATCH_OUTPUT" |cut -d/ -f 3)
        project=$(echo "$PROJECT_MATCH_OUTPUT" |cut -d/ -f 5)
      else
        echo "I found multiple matches for '$account'. Which one did you mean?"
        # shellcheck disable=SC2086
        # shellcheck disable=SC2116
        PROJECT_MATCHES_AS_STRING=$(echo $PROJECT_MATCH_OUTPUT)
        FULL_PROJECT_PATH=$(multiple_choice "$PROJECT_MATCHES_AS_STRING")
        debug "FULL_PROJECT_PATH $FULL_PROJECT_PATH"
        account=$(echo "$FULL_PROJECT_PATH" |cut -d/ -f 3)
        project=$(echo "$FULL_PROJECT_PATH" |cut -d/ -f 5)
      fi
    fi
  fi

  # Use account if project not specified.
  if test -z "${project}"; then
    project=${2:-}
  fi

  test -z "${project}" && {
    project=${account}
  }

  debug "account: $account"
  debug "project: $project"

  # Arg-based config: Default to simple mode where account and project are the same name.
  # If they are not the same, there should be a dotfile in the account's home directory that can override them.
  #######################################################
  # DONT CHANGE THE NAMES OF THESE VARIABLES!
  # THEIR VALUES ARE OVERRIDDEN BY THE HINTS FILE
  #######################################################
  MYHOSTNAME=$(hostname -f)
  MYIP=$(curl "http://icanhazip.com" 2>/dev/null)
  USERACCOUNT=${account}
  SERVICEACCOUNT=${account}-srv
  HOME_DIR="/home/${account}"
  PROJECT_DIR="/home/${account}/www/${project}"
  GIT_DIR="/home/${account}/git/${project}"
  DBUSER=${project}
  DBNAME=${project}
  ENABLED_NGINX_VHOST="/etc/nginx/sites-enabled/${project}.${MYHOSTNAME}"
  REAL_NGINX_VHOST="/etc/nginx/sites-available/${project}.${MYHOSTNAME}"
  ENABLED_NGINX_VHOST_2019="/etc/nginx/sites-enabled/${account}-${project}.conf"
  REAL_NGINX_VHOST_2019="/etc/nginx/sites-available/${account}-${project}.conf"
  FPM_POOL_CONF="${POOLDIR}/${project}.conf" # Original var name; specified in /home/<account>/.acro-add-website/<project>
  FPM_POOL_CONF_LONG="${POOLDIR}/${account}-${project}.conf"
  FPM_POOL_CONF_SHORT="${POOLDIR}/${project}.conf"
  ACCOUNT_LOG_DIR="/var/log/vhosts/${account}"
  PROJECT_LOG_DIR="$ACCOUNT_LOG_DIR/$project"
  LE_RENEW="/etc/letsencrypt/renewal/${project}.${MYHOSTNAME}.conf"
  LOGROTATE_CONF="/etc/logrotate.d/vhost.${project}"
  if [[ "$account" != "$project" ]]; then
    SERVICEACCOUNT="${account}-${project}-srv"
    DBUSER="${account}_${project}"
    DBNAME="${account}_${project}"
  fi
  WEBSERVER=${WEBSERVER:-nginx} ## Accept 'WEBSERVER' as environment variable, or default to 'nginx' if not present / not defined.
  HTTPD_SERVICE_NAME=${WEBSERVER}

  OLD_HINTS="/home/${account}/www/${project}/.acro-add-website"
  if test -e "${OLD_HINTS}"; then
    HINTS=${OLD_HINTS}
  else
    HINTS="/home/${account}/.acro-add-website/${project}"
  fi
  # If there is a hints file, and if it's only writable by root, use it to override simple defaults
  # i.e. in case the MYSQL DB and USER have been named differently.
  if test -e "${HINTS}"; then
    OCTAL=$(stat -c "%a" "${HINTS}")
    if test -O "${HINTS}" && test -G "${HINTS}" && [[ "${OCTAL}" == "644" ]]; then
      echo "Reading in values from ${HINTS}."
      source "${HINTS}"
    else
      echo "A hints file exists at ${HINTS} but it has bad permissions, so it will be ignored."
    fi
  else
    warn "No hints file was found at ${HINTS}"
    echo "I will do my best to guess what to remove, but there are no guarantees."
  fi

  # If the ENABLED_VHOST and REAL_VHOST variables aren't set, default them to the nginx ones for legacy reasons.
  [ -z "${ENABLED_VHOST+x}" ] && ENABLED_VHOST=${ENABLED_NGINX_VHOST}
  [ -z "${REAL_VHOST+x}" ] && REAL_VHOST=${REAL_NGINX_VHOST}
  [ -z "${ENABLED_VHOST_2019+x}" ] && ENABLED_VHOST_2019=${ENABLED_NGINX_VHOST_2019}
  [ -z "${REAL_VHOST_2019+x}" ] && REAL_VHOST_2019=${REAL_NGINX_VHOST_2019}



  ERRCOUNT=0
  ERRMAX=15
  echo "The following changes will be affected on ${MYHOSTNAME} ( ${MYIP} ):"

  echo "  Service: ${PHP_FPM_SERVICE_NAME:-nginx}  ${BOLD}will be restarted${UNBOLD}"
  echo "  Service: $(get_httpd_service_name)  ${BOLD}will be restarted${UNBOLD}"

  echo -n "  Service account: ${SERVICEACCOUNT} ${BOLD}"
  if id "${SERVICEACCOUNT}" > /dev/null; then
    echo "will be removed"
  else
    # no need to print a warning. System will show an error.
    ERRCOUNT=$((ERRCOUNT+1))
  fi
  echo -n "${UNBOLD}"

  SERVICE_ACCOUNT_HOME_DIR=''
  echo -n "  Service account home dir:"
  if id "${SERVICEACCOUNT}" >/dev/null 2>&1 ; then
    SERVICE_ACCOUNT_HOME_DIR=$(getent passwd "$SERVICEACCOUNT"| cut -d: -f6)
    echo -n " $SERVICE_ACCOUNT_HOME_DIR"
    if [[ -n "$SERVICE_ACCOUNT_HOME_DIR" ]] && [[ -e "$SERVICE_ACCOUNT_HOME_DIR" ]]; then
      echo " ${BOLD}will be removed${UNBOLD}"
    else
      echo " ${BOLD}does not exist${UNBOLD}"
    fi
  else
    echo " ${BOLD}does not exist${UNBOLD}"
  fi

  echo -n "  Project dir: ${PROJECT_DIR} ${BOLD}"
  if test -e "${PROJECT_DIR}"; then
    echo "will be removed"
  else
    echo "does not exist"
    ERRCOUNT=$((ERRCOUNT+1))
  fi
  echo -n "${UNBOLD}"

  echo -n "  Git dir: ${GIT_DIR} ${BOLD}"
  if test -e "${GIT_DIR}"; then
    echo "will be removed"
  else
    echo "does not exist"
    ERRCOUNT=$((ERRCOUNT+1))
  fi
  echo -n "${UNBOLD}"

  echo -n "  Mysql db: ${DBNAME} ${BOLD}"
  if mysql -e "use ${DBNAME}"; then
    echo "will be removed"
  else
    # no need to print a warning. System will show an error.
    ERRCOUNT=$((ERRCOUNT+1))
  fi
  echo -n "${UNBOLD}"

  echo -n "  Mysql user(s): ${DBUSER} ${BOLD}"
  DB_USER_LIST="$(mysql --table -e "SELECT user,host FROM mysql.user WHERE user = '${DBUSER}'")" || ERRCOUNT=$((ERRCOUNT+1))
  DBUSER_RESULT="$(mysql -N -e "SELECT count(user) FROM mysql.user WHERE user = '${DBUSER}'")" || ERRCOUNT=$((ERRCOUNT+1))
  if [[ "${DBUSER_RESULT}" == "" ]]; then
    cerr "An unexpected error occurred while trying to list mysql users."
  elif [[ "${DBUSER_RESULT}" == "1" ]]; then
    echo "will be removed"
  elif [[ "${DBUSER_RESULT}" == "0" ]]; then
    echo "does not exist"
    ERRCOUNT=$((ERRCOUNT+1))
  else
    echo ""
    echo "$DB_USER_LIST"
    echo "  ^^ MORE THAN ONE MYSQL USER WILL BE REMOVED.... BE SURE THIS IS WHAT YOU WANT."
  fi
  echo -n "${UNBOLD}"

  echo -n "  Site available: ${REAL_VHOST} ${BOLD}"
  if test -e "${REAL_VHOST}"; then
    echo "will be removed"
  else
    echo "does not exist"
    ERRCOUNT=$((ERRCOUNT+1))
  fi
  echo -n "${UNBOLD}"

  echo -n "  Site enabled: ${ENABLED_VHOST} ${BOLD}"
  if test -e "${ENABLED_VHOST}"; then
    echo "will be removed"
  else
    echo "does not exist"
    ERRCOUNT=$((ERRCOUNT+1))
  fi
  echo -n "${UNBOLD}"

  echo -n "  Site available (2019 revision): ${REAL_VHOST_2019} ${BOLD}"
  if test -e "${REAL_VHOST_2019}"; then
    echo "will be removed"
  else
    echo "does not exist"
    ERRCOUNT=$((ERRCOUNT+1))
  fi
  echo -n "${UNBOLD}"
  echo -n "  Site enabled (2019 revision): ${ENABLED_VHOST_2019} ${BOLD}"
  if test -e "${ENABLED_VHOST_2019}"; then
    echo "will be removed"
  else
    echo "does not exist"
    ERRCOUNT=$((ERRCOUNT+1))
  fi
  echo -n "${UNBOLD}"

  local LONG_PHP_CONF_FOUND=0
  local SHORT_PHP_CONF_FOUND=0
  echo -n "  PHP FPM config: ${FPM_POOL_CONF_LONG} ${BOLD}"
  if test -e "${FPM_POOL_CONF_LONG}"; then
    echo "will be removed"
    LONG_PHP_CONF_FOUND=1
  else
    echo "does not exist"
    ERRCOUNT=$((ERRCOUNT+1))
  fi
  echo -n "${UNBOLD}"

  if [ $LONG_PHP_CONF_FOUND -eq 0 ]; then
    echo -n "  PHP FPM config: ${FPM_POOL_CONF_SHORT} ${BOLD}"
    if test -e "${FPM_POOL_CONF_SHORT}"; then
      SHORT_PHP_CONF_FOUND=1
      echo "will be removed"
    else
      echo "does not exist"
    fi
    echo -n "${UNBOLD}"
  fi

  if [ $SHORT_PHP_CONF_FOUND -eq 0 ] && [ $LONG_PHP_CONF_FOUND -eq 0 ]; then
    echo -n "  PHP FPM config: ${FPM_POOL_CONF} ${BOLD}"
    if test -e "${FPM_POOL_CONF}"; then
      echo "will be removed"
    else
      echo "does not exist"
    fi
    echo -n "${UNBOLD}"
  fi



  echo -n "  Log dir: ${PROJECT_LOG_DIR} ${BOLD}"
  if test -e "${PROJECT_LOG_DIR}"; then
    echo "will be removed"
  else
    echo "does not exist"
    ERRCOUNT=$((ERRCOUNT+1))
  fi
  echo -n "${UNBOLD}"

  echo -n "  Logrotate config: ${LOGROTATE_CONF} ${BOLD}"
  if test -e "${LOGROTATE_CONF}"; then
    echo "will be removed"
  else
    echo "does not exist"
    ERRCOUNT=$((ERRCOUNT+1))
  fi
  echo -n "${UNBOLD}"


  LE_DOMAIN=${LE_RENEW%.conf}
  LE_DOMAIN=${LE_DOMAIN##*/}
  LE_LIVE_DIR="/etc/letsencrypt/live/${LE_DOMAIN}"
  LE_ARCHIVE_DIR="/etc/letsencrypt/archive/${LE_DOMAIN}"
  for LE_RESOURCE in "$LE_RENEW" "$LE_LIVE_DIR" "$LE_ARCHIVE_DIR"; do
    echo -n "  LetsEncrypt: ${LE_RESOURCE} ${BOLD}"
    if test -e "${LE_RESOURCE}"; then
      echo "will be disabled"
    else
      echo "does not exist"
      ERRCOUNT=$((ERRCOUNT+1))
    fi
    echo -n "${UNBOLD}"
  done








  if [ ${ERRCOUNT} -ge ${ERRMAX}  ]; then
    echo "It appears this script can do nothing for you. You either mistyped something, or the site has already been purged."
    exit 0
  fi

  echo -n "${BOLD}"
  echo "This script does not back up anything. Everything specified above will be gone instantly and permanently. There is no 'undo'."
  echo -n "Enter 'I understand' (case sensitive, without quotes) to continue, anything else to quit: "
  echo -n "${UNBOLD}"
  read -r DRAMATIC_PAUSE
  if [[ "$DRAMATIC_PAUSE" != "I understand" ]]; then
    echo "Aborting."
    exit 1
  fi

  # Turn off abort-on-error, so we can plow trhough the removal and ignore errors.
  set +e

  # Goodbye, cruel world.
  rm -rf "${PROJECT_DIR}"
  rm -rf "${GIT_DIR}"
  if [ $LONG_PHP_CONF_FOUND -eq 1 ]; then
    rm -f "${FPM_POOL_CONF_LONG}"
  elif [ $SHORT_PHP_CONF_FOUND -eq 1 ]; then
    rm -f "${FPM_POOL_CONF_SHORT}"
  else
    rm -f "${FPM_POOL_CONF}"
  fi
  rm -f "${ENABLED_VHOST}"
  rm -f "${REAL_VHOST}"
  rm -fv "${ENABLED_VHOST_2019}"
  rm -fv "${REAL_VHOST_2019}"
  mysql -N -e "SELECT host FROM mysql.user WHERE user = '${DBUSER}'" | while read REMOTE_HOST; do
    mysql -e "drop user '${DBUSER}'@'${REMOTE_HOST}'; flush privileges;"
  done
  mysql -e "drop database ${DBNAME}; flush privileges;"
  service "${PHP_FPM_SERVICE_NAME:-nginx}" restart
  service "$(get_httpd_service_name)" restart
  service "${HTTPD_SERVICE_NAME}" restart
  gpasswd -d "${account}" "${SERVICEACCOUNT}"
  userdel --remove "${SERVICEACCOUNT}"
  rm -rf "${PROJECT_LOG_DIR}"
  find "$ACCOUNT_LOG_DIR" -type d -empty -delete
  rm -f "${LOGROTATE_CONF}"
  test -d /etc/letsencrypt/renewal_disabled && ! test -d /etc/letsencrypt/renewal.disabled && mv /etc/letsencrypt/renewal_disabled /etc/letsencrypt/renewal.disabled
  test -d /etc/letsencrypt/renewal.disabled || mkdir -p /etc/letsencrypt/renewal.disabled
  test -e "${LE_RENEW}" && mv -v "${LE_RENEW}" /etc/letsencrypt/renewal.disabled/
  test -e "${LE_LIVE_DIR}" && mv -v "${LE_LIVE_DIR}" "${LE_LIVE_DIR}.removed"
  test -e "${LE_ARCHIVE_DIR}" && mv -v "${LE_ARCHIVE_DIR}" "${LE_ARCHIVE_DIR}.removed"

  test -e "${HINTS}" && rm -v "${HINTS}"


  if test -e "${HOME_DIR}"; then

    # Clean up empty WWW dirs
    WWW_FOLDERS_LEFT="$(find "${HOME_DIR}/www" -mindepth 1 -maxdepth 1 -type d|wc -l)"
    if [ "$WWW_FOLDERS_LEFT" -eq 0 ]; then
      find "$HOME_DIR/www" -type d -empty -delete
    fi
    # Clean up empty GIT dirs
    GIT_FOLDERS_LEFT="$(find "${HOME_DIR}/git" -mindepth 1 -maxdepth 1 -type d|wc -l)"
    if [ "$GIT_FOLDERS_LEFT" -eq 0 ]; then
      find "$HOME_DIR/git" -type d -empty -delete
    fi
  fi

  echo "${BOLD}She gone.${UNBOLD}"

  if test -e "${HOME_DIR}"; then
    # Offer to remove the web user account
    if [ "$WWW_FOLDERS_LEFT" -eq 0 ] && [ "$GIT_FOLDERS_LEFT" -eq 0 ]; then
      echo "There don't appear to be any websites left in ${HOME_DIR}. Here's what remains: "
      tree -a "${HOME_DIR}"
      QUESTION="Do you wish to remove the user '${USERACCOUNT}' and their home dir?"
      if require_yes_or_no "$QUESTION"; then
        userdel --remove "${USERACCOUNT}"
      fi
    fi
  fi

  cerr ""
  warn "Be sure to manually check for (and remove) any orphaned PHP FPM or NGINX configs. This script can only perform a best-effort removal. Thoroughness is not guaranteed."
  cerr "# grep -irl ${project} /etc/php*"
  cerr "# grep -irl ${project} /etc/nginx*"

}


# ----------------------------------------
# Supporting functions
# ----------------------------------------
function require_yes_or_no() {
  local PROMPT_TEXT="$1 (y/n): "
  printf "%s" "$PROMPT_TEXT"
  while read -r options; do
    case "$options" in
      "y") ANSWER=1; break ;;
      "n") ANSWER=0; break ;;
      *) printf "%s" "$PROMPT_TEXT" ;;
    esac
  done
  if [ $ANSWER -eq 1 ]; then
    true
  else
    false
  fi
}

# If there is more than one project in the dir, prompts the user to choose. Otherwise returns the only one.
function get_project() {
  local ACCOUNT="$1"
  local PARENT_FOLDER="/home/$ACCOUNT/www"
  local FIND_OUTPUT
  FIND_OUTPUT="$(find "$PARENT_FOLDER" -maxdepth 1 -mindepth 1 -type d -not -path '*/\.*' )"
  #debug "FIND_OUTPUT: $FIND_OUTPUT"
  FIND_OUTPUT_LENGTH="${#FIND_OUTPUT}"
  if [ "$FIND_OUTPUT_LENGTH" -eq 0 ]; then
    echo -n "$ACCOUNT"
    return
  fi
  #debug "FIND_OUTPUT_LENGTH: $FIND_OUTPUT_LENGTH"
  local FOLDER_NAMES_ON_NEWLINES
  FOLDER_NAMES_ON_NEWLINES="$(echo "$FIND_OUTPUT"| awk -F"./" '{print $4}')"
  #debug "FOLDER_NAMES_ON_NEWLINES: $FOLDER_NAMES_ON_NEWLINES"
  local NUM_FOLDERS
  NUM_FOLDERS="$(echo "$FOLDER_NAMES_ON_NEWLINES"|wc -l)"
  #debug "NUM_FOLDERS: $NUM_FOLDERS"
  if [ "$NUM_FOLDERS" -eq 1 ]; then
    ##debug 285
    echo "$FOLDER_NAMES_ON_NEWLINES" |tr -d '\n'
    return
  elif [ "$NUM_FOLDERS" -eq 0 ]; then
    # debug 289
    echo -n "$ACCOUNT"
    return
  fi
  >&2 echo "Which site do you want to remove?"
  # shellcheck disable=SC2086
  local FOLDER_NAMES_AS_STRING=$FOLDER_NAMES_ON_NEWLINES
  local PROJECT
  PROJECT="$(multiple_choice "$FOLDER_NAMES_AS_STRING")"
  echo "$PROJECT"
}

function get_httpd_service_name () {
  if [[ "${WEBSERVER}" == "nginx" ]]; then
    HTTPD_SERVICE_NAME=nginx
  else
    if [[ -x /usr/sbin/apache2 ]]; then
      # ubuntu
      HTTPD_SERVICE_NAME=apache2
    elif [[ -x /usr/sbin/httpd ]]; then
      # red hat
      HTTPD_SERVICE_NAME=httpd
    else
      HTTPD_SERVICE_NAME=UNKNOWN
    fi
  fi
  echo "$HTTPD_SERVICE_NAME"
}

# Takes a string separated list, and prompts the user to select one of them. Will not return until the user chooses one.
function multiple_choice() {
  local CHOICES_AS_STRING="$1"
  local CHOICE_COUNT=0
  local CHOICES_AS_ARRAY=()
  for CHOICE_DISPLAY in $CHOICES_AS_STRING; do
    CHOICE_COUNT=$((CHOICE_COUNT+1))
    CHOICES_AS_ARRAY+=("$CHOICE_DISPLAY")
    >&2 echo "[$CHOICE_COUNT] $CHOICE_DISPLAY"
  done
  CHOICE=0
  while [[ "$CHOICE" -lt 1 ]] || [[ "$CHOICE" -gt $CHOICE_COUNT ]]; do
    >&2 echo -n "Please select: "
    read -r CHOICE
    CHOICE_INDEX=$((CHOICE-1))
  done
  local CHOICE_VALUE
  CHOICE_VALUE="${CHOICES_AS_ARRAY[$CHOICE_INDEX]}"

  # Send the value to STDOUT for the caller to capture.
  echo "$CHOICE_VALUE"
}

function require_script () {
  type "$1" > /dev/null  2>&1 || {
    err "The following is not installed or not in path: $1"
    abort
  }
}

function require_package () {
  type "$1" > /dev/null  2>&1 || {
    apt-get -y install "$1" || yum -y install "$1"
  }
}

function warn () {
  bold_feedback "Warn" "$@"
}

function err () {
  bold_feedback "Err" "$@"
}

function bold_feedback () {
  BOLD=$(tput bold)
  UNBOLD=$(tput sgr0)
  cerr "${BOLD}${1}:${UNBOLD} ${2}"
}

function debug () {
  cerr "$@"
}

function cerr() {
  >&2 echo "$@"
}

BOLD=$(tput bold)
UNBOLD=$(tput sgr0)

main "$@"
