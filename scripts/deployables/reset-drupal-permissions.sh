#!/bin/bash -ue

# ----------------------------------------
# ----------------------------------------

function main() {
  echo ''
  echo 'Drupal 7: Run this script from your Drupal Root.'
  echo 'Drupal 8: Run this script from your Web Root.'
  echo ''
  check_prerequisites
  seed_dummy_variables
  collect_variables
  check_maintenance_mode_on
  reset_permissions
  check_maintenance_mode_off
  echo "Reset of Drupal permissions is complete."
}

# ----------------------------------------
# Main functions
# ----------------------------------------

function check_prerequisites() {
  require_root_e
  require_script "/usr/bin/stat"
  require_script "/usr/bin/id"
}

function seed_dummy_variables() {
  # Obviously fictitious values that must already exist, but will get overwritten as the script runs.
  USER_ACCOUNT="_WILL_BE_SET_BY_get_owner_FUNCTION"
  PHP_GROUP="_WILL_BE_SET_BY_get_group_FUNCTION"
}

function collect_variables() {
  # The order of these is important.
  get_drupal_root
  get_web_root
  get_drush_path
  get_drush_version
  get_public_files_path
  get_private_files_path
  verify_drupal_structure
  get_group
  get_owner
}

function check_maintenance_mode_on() {
  if [ "$DRUSH_IS_WORKING" -ne 1 ]; then
    echo "Skipping maintenance mode check (drush tests failed previously)."
    echo ""
    return
  fi

  # drush version 8
  if [ "$DRUSH_VERSION" -eq 8 ]; then
    MM="$(safe_vget maintenance_mode)"
    if [[ "$MM" == "1" ]]; then
      echo "MAINTENANCE_MODE_ON: Site is already in maintenance mode."
      echo ""
      return;
    fi
  fi

  # drush version 9
  if [ "$DRUSH_VERSION" -eq 9 ]; then
    MM="$($DRUSH_PATH sget system.maintenance_mode)"
    if [[ "$MM" -eq 1 ]]; then
      echo "MAINTENANCE_MODE_ON: Site is already in maintenance mode."
      echo ""
      return;
    fi
  fi

  echo "Do you want to put the site in maintenance mode before you begin? (highly recommended)"
  if require_yes_or_no "MAINTENANCE_MODE_ON"; then

    # drush version 8
    if [ "$DRUSH_VERSION" -eq 8 ]; then
      "$DRUSH_PATH" vset maintenance_mode 1
    fi

    # drush version 9
    if [ "$DRUSH_VERSION" -eq 9 ]; then
      "$DRUSH_PATH" sset system.maintenance_mode 1 --input-format=integer
    fi
  fi
  echo ""
}

function check_maintenance_mode_off() {
  if [ "$DRUSH_IS_WORKING" -ne 1 ]; then
    echo "Skipping maintenance mode check (drush tests failed previously)."
    echo ""
    return
  fi

  # drush version 8
  if [ "$DRUSH_VERSION" -eq 8 ]; then
    MM="$(safe_vget maintenance_mode)"
    if [[ "$MM" == "0" ]]; then
      echo "MAINTENANCE_MODE_OFF: Site is online."
      echo ""
      return;
    fi
  fi

  # drush version 9
  if [ "$DRUSH_VERSION" -eq 9 ]; then
    MM="$($DRUSH_PATH sget system.maintenance_mode)"
    if [[ "$MM" -eq 0 ]]; then
      echo "MAINTENANCE_MODE_OFF: Site is online."
      echo ""
      return;
    fi
  fi

  if test -z "$MM"; then
    echo "Maintenance mode is either unspecified (off), or drush isn't working. Assuming site is online."
    echo ""
    return;
  fi

  echo "Do you want to bring the site out of maintenance mode?"
  if require_yes_or_no "MAINTENANCE_MODE_OFF"; then

    # drush version 8
    if [ "$DRUSH_VERSION" -eq 8 ]; then
      "$DRUSH_PATH" vset maintenance_mode 0
    fi

    # drush version 9
    if [ "$DRUSH_VERSION" -eq 9 ]; then
      "$DRUSH_PATH" sset system.maintenance_mode 0 --input-format=integer
    fi

  fi
  echo ""
}

function reset_permissions() {
  echo "Ready to reset permissions and ownership in ${DRUPAL_ROOT}?"
  require_yes_or_no "PULL THE TRIGGER" || abort

  echo -n "Resetting directory permissions on '${DRUPAL_ROOT}'... "
  find "${DRUPAL_ROOT}" -type d -exec chmod 755 {} \;
  echo "OK"

  echo -n "Resetting file permissions on '${DRUPAL_ROOT}'... "
  find "${DRUPAL_ROOT}" -type f -exec chmod 644 {} \;
  echo "OK"

  echo -n "Resetting ownership on '${DRUPAL_ROOT}'... "
  chown -R "$USER_ACCOUNT:" "${DRUPAL_ROOT}"
  echo "OK"

  echo -n "Resetting ownership on '${PUBLIC_FILES}'... "
  chown -R "$USER_ACCOUNT:$PHP_GROUP" "${PUBLIC_FILES}"
  echo "OK"

  echo -n "Giving '$PHP_GROUP' group write access to '${PUBLIC_FILES}'... "
  chmod -R g+w "${PUBLIC_FILES}"
  find "${PUBLIC_FILES}" -type d -exec chmod 2771 {} \;
  echo "OK"

  if test -e "${PRIVATE_FILES}"; then
    echo -n "Resetting ownership on '${PRIVATE_FILES}'... "
    chown -R "$USER_ACCOUNT:$PHP_GROUP" "${PRIVATE_FILES}"
    echo "OK"

    echo -n "Giving '$PHP_GROUP' group write access to '${PRIVATE_FILES}'... "
    chmod -R g+w "${PRIVATE_FILES}"
    find "${PRIVATE_FILES}" -type d -exec chmod 2770 {} \;
    echo "OK"
  fi

  echo -n "Resetting ownership permissions on settings files... "
  find "$DRUPAL_SITES_DIR/" -maxdepth 2 -name settings.php -exec chmod 640 {} \;
  find "$DRUPAL_SITES_DIR/" -maxdepth 2 -name settings.php -exec chown "$USER_ACCOUNT:$PHP_GROUP" {} \;
  find "$DRUPAL_SITES_DIR/" -maxdepth 2 -name settings.local.php -exec chmod 640 {} \;
  find "$DRUPAL_SITES_DIR/" -maxdepth 2 -name settings.local.php -exec chown "$USER_ACCOUNT:$PHP_GROUP" {} \;
  echo "OK"
  echo "All done."
}

# ----------------------------------------
# Secondary functions
# ----------------------------------------

function get_drupal_root() {
  echo "What is the absolute path to your Drupal Root?"
  local DEFAULT_VALUE="$PWD"
  DRUPAL_ROOT="$(prompt_for_value_with_default "DRUPAL_ROOT" "$DEFAULT_VALUE")"
  DRUPAL_SITES_DIR="${DRUPAL_ROOT}/sites"
  DRUPAL_SITES_DEFAULT="${DRUPAL_ROOT}/sites/default"
  echo ""
}

function get_web_root() {
  echo "What is the absolute path to your website root? (Hint: Most of the time, this will be the same as your Drupal root. If drupal lives in a subdirectory, you need to adjust this.)"
  local DEFAULT_VALUE="$DRUPAL_ROOT"
  WEB_ROOT="$(prompt_for_value_with_default "WEB_ROOT" "$DEFAULT_VALUE")"
  echo ""
}

function get_drush_path() {
  echo "What is the absolute path to Drush (if installed)? You are welcome to specify an alternate drush path, if it serves your purposes:"
  if test -x ../bin/drush ; then
    local DEFAULT_VALUE="../bin/drush"
  else
    local DEFAULT_VALUE
    DEFAULT_VALUE="$(which drush||true)"
  fi
  DRUSH_PATH="$(prompt_for_value_with_default "DRUSH_PATH" "$DEFAULT_VALUE")"
  verify_drush
  echo ""
}

function get_drush_version() {
  DRUSH_VERSION=$("$DRUSH_PATH" version | cut -f2 -d':' | tr -d '[:space:]' | cut -f1 -d'.')
  echo "Drush Version: \"$DRUSH_VERSION\""
  echo ""
}

function get_public_files_path() {
  echo "What is the relative path to the 'files' dir (from the Drupal root)?"
  local DEFAULT_VALUE
  if [ "$DRUSH_IS_WORKING" -ne 1 ]; then
    DEFAULT_VALUE="sites/default/files"
  else
    DEFAULT_VALUE="$(safe_vget file_public_path)"
    if test -z "$DEFAULT_VALUE"; then
      info "No files path defined. Falling back to standard default."
      DEFAULT_VALUE="sites/default/files"
    fi
  fi
  PUBLIC_FILES="$(prompt_for_value_with_default "PUBLIC_FILES" "$DEFAULT_VALUE")"
  echo ""
}

function get_private_files_path() {
  echo "What is the relative path to the 'private' directory, if there is one?"
  echo "This is OK to leave blank if there is no private dir:"
  local DEFAULT_VALUE
  if [ "$DRUSH_IS_WORKING" -ne 1 ]; then
    DEFAULT_VALUE="../private"
  else
    DEFAULT_VALUE="$(safe_vget file_private_path)"
  fi
  PRIVATE_FILES="$(prompt_for_value_with_default "PRIVATE_FILES" "$DEFAULT_VALUE")"
  echo ""
}

function get_group() {
  echo "What group should own the 'files' and 'private' directories? i.e. what group does the PHP process owner belong to?"
  local DEFAULT_VALUE
  DEFAULT_VALUE="$(guess_group_owner)"
  UPLOADS_OWNER="$(prompt_for_value_with_default "UPLOADS_OWNER" "$DEFAULT_VALUE")"
  verify_group "$UPLOADS_OWNER"
  PHP_GROUP="$UPLOADS_OWNER"
  echo ""
}

function get_owner() {
  echo "What user should own the rest of the site? It should be same user that owns the current home directory."
  local DEFAULT_VALUE
  DEFAULT_VALUE="$(guess_home_dir_owner)"
  HOME_OWNER="$(prompt_for_value_with_default "HOME_OWNER" "$DEFAULT_VALUE")"
  verify_user "$HOME_OWNER"
  USER_ACCOUNT="$HOME_OWNER"
  echo ""
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

function verify_drush() {
  test -x "$DRUSH_PATH" || {
    err "Drush does not exist or is not executable: '$DRUSH_PATH'"
    return
  }
  info "Testing to see if we can use drush..."
  if "$DRUSH_PATH" status; then
    if "$DRUSH_PATH" sql-query "SHOW TABLES" |grep -q watchdog; then
      # Assuming we are inside DRUPAL_ROOT when this runs, this is a good way to
      # see if the site works. Any errors here will let us know that we can't
      # depend on drush to put the site in or out of maintenance mode, or get
      # variables from it.
      DRUSH_IS_WORKING=1
    fi
  fi
  if [ "$DRUSH_IS_WORKING" -eq 1 ]; then
    echo "Drush works well enough for our purposes."
  else
    warn "Drush can't communicate with the database. Drush commands will be unavailable."
  fi
}

function prompt_for_value_with_default() {
  # All this for the benefit of RHEL 5, which uses bash 3, and doesn't support the "-i" switch of the "read" shell builtin.
  local VARIABLE_NAME="$1"
  local DEFAULT_VALUE="$2"
  local VARIABLE_VALUE
  if bash --version |head -1|grep -qoi 'version 4'; then
    read -r -e -p "$VARIABLE_NAME: " -i "$DEFAULT_VALUE" VARIABLE_VALUE
  elif bash --version |head -1|grep -qoi 'version 3'; then
    read -r -p "$VARIABLE_NAME [$DEFAULT_VALUE]: " VARIABLE_VALUE
    if test -z "${VARIABLE_VALUE}"; then
      VARIABLE_VALUE="$DEFAULT_VALUE"
    fi
  else
    fatal "Unidentified bash version."
  fi
  # Return the value to the caller.
  echo "$VARIABLE_VALUE"
}

# Safe? Well, safer, anyway. At the very least, consistent for use in bash, considering how many different ways results can be returned by drush.
function safe_vget() {
  # Drush sometimes returns the value as quoted string, sometimes not. Sometimes as "Varname: Value", and sometimes just "Value" This handles all cases.
  test -x "$DRUSH_PATH" || {
    err "Drush does not exist or is not executable: $DRUSH_PATH"
    abort
  }
  local VARNAME_TO_GET="$1"
  local VAR_VALUE
  VGET_RESULT="$(${DRUSH_PATH} vget "$VARNAME_TO_GET" --exact --format=string 2>/dev/null)"
  if [[ "$VGET_RESULT" == "${VARNAME_TO_GET}:"* ]]; then
    # Drush returned "Varname: Value"
    VAR_VALUE="$(echo "$VGET_RESULT" |awk '{gsub(/"/,"", $2); print $2}'|tr -d '"'|tr -d '\n')"
  else
    VAR_VALUE="$(echo "$VGET_RESULT" | tr -d '"'|tr -d '\n')"
    # Drush returned just "Value"
  fi
  echo "$VAR_VALUE"
}

function guess_group_owner() {
  FALLBACK_GROUP="$(stat -c '%G' "${PUBLIC_FILES}")"
  if [[ "$FALLBACK_GROUP" == "$USER_ACCOUNT" ]]; then
    # Where USER_ACCOUNT is not the php user, but the legitimate user owner, which will result in PHP not being able to write to the files dir.
    info "guess_group_owner(): Current group owner of ${PUBLIC_FILES} is ${FALLBACK_GROUP}; this is likely incorrect. Setting fallback default to blank."
    FALLBACK_GROUP=""
  fi

# @TODO: If Drupal is in a physical subdirectory, the path being looked for is not found because the web root is actually one or more directories up, and the grep is too specific. Need to find a way to be able to let the script know that the web root and the drupal root are different.

  if test -e "/etc/nginx/sites-enabled"; then
    # debian style
    VHOSTFILE="$(grep -l "$WEB_ROOT" /etc/nginx/sites-enabled/*)"
    DEFAULT_GROUP="www-data"
  elif test -e "/etc/apache2/sites-enabled"; then
    # debian style
    VHOSTFILE="$(grep -l "$WEB_ROOT" /etc/apache2/sites-enabled/*)"
    DEFAULT_GROUP="www-data"
  elif test -e "/etc/nginx/conf.d"; then
    # red hat style
    VHOSTFILE="$(grep -l "$WEB_ROOT" /etc/nginx/conf.d/*)"
    DEFAULT_GROUP="apache"
  elif test -e "/etc/httpd/conf.d"; then
    # red hat style
    VHOSTFILE="$(grep -l "$WEB_ROOT" /etc/httpd/conf.d/*)"
    DEFAULT_GROUP="apache"
  else
    info "guess_group_owner(): Could not find a virtual host configuration directory. Falling back to default."
    echo -n "${FALLBACK_GROUP}"
    return
  fi

  if test -z "$VHOSTFILE"; then
    info "guess_group_owner(): Could not locate any virtual host configuration containing ${WEB_ROOT}. Falling back to default."
    echo -n "${FALLBACK_GROUP}"
    return
  fi

  GREP_RESULT="$(grep \.sock "$VHOSTFILE")"
  if test -z "$GREP_RESULT"; then
    info "guess_group_owner(): No mention of a php fpm unix socket file in ${VHOSTFILE} - falling back to standard web group for this OS."
    echo -n "${DEFAULT_GROUP}"
    return
  fi

  # This is super brittle, and will probably only work for my own setups.
  PHP_SOCKFILE="$(echo "$GREP_RESULT"|grep -v '[[:space:]]*#' |sed 's/fastcgi_pass unix://'|sed 's/;//'|tr -d ' ' | head -1)"

  if test -z "$PHP_SOCKFILE"; then
    debug "guess_group_owner(): Failed to grep the php-fpm.sock file. Falling back to standard web group for this OS, which is very likely NOT what you need."
    echo -n "${DEFAULT_GROUP}"
    return
  fi

  FPM_POOL="$(grep -irl "$PHP_SOCKFILE" /etc/php*)"

  if test -z "${FPM_POOL}"; then
    debug "guess_group_owner(): Failed to determine which FPM pool the socket file came from. Falling back to standard web group for this OS, which is very likely NOT what you need."
    echo -n "${DEFAULT_GROUP}"
    return
  fi

  GROUP_OWNER="$(grep ^group "$FPM_POOL")"
  if test -z "${FPM_POOL}"; then
    debug "guess_group_owner(): Failed to grep group owner from ${FPM_POOL} - falling back to standard web group for this OS, which is almost definitely NOT what you need."
    echo -n "${DEFAULT_GROUP}"
    return
  fi

  # FINALLY!
  echo -n "$GROUP_OWNER" |sed 's/^group//'|sed 's/=//' | tr -d ' '

}



function guess_home_dir_owner() {
  FALLBACK_OWNER="$(stat -c '%U' "${DRUPAL_ROOT}")"
  if ! tree_root_is_named_home; then
    echo -n "${FALLBACK_OWNER}"
    return
  fi
  if ! home_dir_name_matches_owner_name; then
    echo -n "${FALLBACK_OWNER}"
    return
  fi
  echo -n "${OWNER}"
}



function tree_root_is_named_home() {
  # Delimiter = /
  #    / home / jack / www / project / wwwroot / ...
  # f1 / f2   / f3   / f4  / f5      / f6      / ...
  DIR_PART="$(echo "$PWD"|cut -d "/" -f2)"
  if [[ "$DIR_PART" == "home" ]]; then
    true
  else
    false
  fi
}

function home_dir_name_matches_owner_name() {
  # Delimiter = /
  #    / home / jack / www / project / wwwroot / ...
  # f1 / f2   / f3   / f4  / f5      / f6      / ...
  DIR_USER="$(echo "$PWD"|cut -d "/" -f3)"
  OWNER="$(stat -c '%U' "/home/${DIR_USER}")"
  if [[ "${OWNER}" == "${DIR_USER}" ]]; then
    true
  else
    false
  fi
}


function verify_user() {
  USERNAME="$1"
  if /usr/bin/id -u "${USERNAME}" > /dev/null; then
    true
  else
    abort
  fi
}

function verify_group() {
  GROUPNAME="$1"
  if /usr/bin/id -g "${GROUPNAME}" > /dev/null; then
    true
  else
    abort
  fi
}

# ----------------------------------------
# ----------------------------------------
# ----------------------------------------
# ----------------------------------------
# ----------------------------------------

function confirm () {
  echo -n "$@"
  read -r CONFIRMATION
  if [[ "${CONFIRMATION}" != 'y' ]]; then
    false
  fi
}

function back_up() {
  WHAT="$1"
  if test -e "$WHAT"; then
    cp -av "$WHAT" "$WHAT.$(date +%s).bak"
  fi
}



function verify_drupal_structure() {
  ERRORS=0
  test -e "$DRUPAL_SITES_DIR" || {
    err "DRUPAL_SITES_DIR does not exist: $DRUPAL_SITES_DIR"
    ERRORS=$((ERRORS + 1))
  }
  test -e "$DRUPAL_SITES_DEFAULT" || {
    err "DRUPAL_SITES_DEFAULT does not exist: $DRUPAL_SITES_DEFAULT"
    ERRORS=$((ERRORS + 1))
  }
  SETTINGS_PHP_COUNT="$(find "$DRUPAL_SITES_DIR/" -maxdepth 2 -name settings.php |wc -l)"
  if [ "$SETTINGS_PHP_COUNT" -lt 1 ]; then
    err "Could not find any settings.php files inside $DRUPAL_SITES_DIR"
    ERRORS=$((ERRORS + 1))
  fi
  test -e "$PUBLIC_FILES/" || {
    err "PUBLIC_FILES does not exist: $PUBLIC_FILES/"
    ERRORS=$((ERRORS + 1))
  }
  test -e "$PRIVATE_FILES/" || {
    warn "PRIVATE_FILES does not exist: $PRIVATE_FILES/"
    echo ""
    # Drupal can function without a private files dir. This isn't a fatal error.
  }
  if [ "$ERRORS" -gt 0 ]; then
    info "Make sure you're running this script from Drupal root, and that (a) your installation either conforms to a standard structure, or (b) you're specifying the correct paths to the alternate structure."
    abort
  fi
}

function require_script () {
  type "$1" > /dev/null  2>&1 || {
    err "The following is not installed or not in path: $1"
    abort
  }
}

function require_root_e() {
  if [ $EUID -ne 0 ]; then
    err "This script must be run as root. Hint: Run with sudo -E for best results."
    abort
  fi
}

# ----------------------------------------
# Supporting functions
# ----------------------------------------


function fatal () {
  bold_feedback "Fatal" "$@"
}

function err () {
  bold_feedback "Err" "$@"
}

function warn () {
  bold_feedback "Warn" "$@"
}

function info () {
  cerr "$@"
}

function debug () {
  cerr "$@"  # Uncomment for debugging.
  true  # Bash functions can't be empty.
}

function bold_feedback () {
  BOLD=$(tput bold)
  UNBOLD=$(tput sgr0)
  cerr "${BOLD}${1}:${UNBOLD} ${2}"
}

function abort () {
  cerr "Aborting."
  exit 1
}

function cerr() {
  >&2 echo "$@"
}

function ctrl_c() {
  # When using "read -e", weird things happen if ctrl + c gets called. Stty sane fixes that. Could also use 'reset' but thats really aggressive.
  stty sane
  exit 1
}


# ----------------------------------------
# Nothing happens until this line is read.
# ----------------------------------------
DRUSH_IS_WORKING=0 # Pessimistic. Will be set to 1 if and when drush is located and tested.
DRUSH_VERSION="Unknown" # Will be set if drush is working.

trap ctrl_c INT
main "$@"
