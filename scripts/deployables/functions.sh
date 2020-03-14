#!/bin/bash

# Small, commonly used functions to save on typing, and make larger scripts more readable.

# Other scripts exect to find me at:
# /usr/local/lib/acro/bash/functions.sh

ERR_ROOT_REQUIRED=1
ERR_SCRIPT_REQUIRED=2
ERR_PACKAGE_REQUIRED=3

# Only print fancy colors and text effects when running with a terminal
if [ -t 1 ] ; then
  BOLD=$(tput bold 2>/dev/null) || BOLD='\033[1;33m' # orange, if tput isnt available.
  UNBOLD=$(tput sgr0 2>/dev/null) || UNBOLD='\033[m'
  GREY=$(tput setaf 7 2> /dev/null)
  NC=$(tput sgr0 2>/dev/null) # No Color
else
  # If running via cron, or through a pipe, then the colors get turned into codes, and cause readability issues
  BOLD=''
  UNBOLD=''
  GREY=''
  NC=''
fi


is_integer() {
  local WHAT="$*"
  if [[ "$WHAT" =~ ^-?[0-9]+$ ]]; then
    true
  else
    false
  fi
}

# Zero is a positive integer too.
is_positive_integer() {
  local WHAT="$*"
  if [[ "$WHAT" =~ ^[0-9]+$ ]]; then
    true
  else
    false
  fi
}

# Prompts the user to select from a list of values. Will not return until the user chooses one.
# Arg 1 (Required): A space separated list of values to choose from. I.e: "foo bar ding bat"
# Arg 2 (Optional): A pipe-separated list of titles. If supplied, will be shown to the user instead of the values. I.e: "Title 1|Title 2|Something Else|Last Option".
# Arg 3 (Optional): If values need to be split on something other than a space, specify the delimiter.
# Arg 4 (Optional): The maximum number of selections to accept. Default is 1. Specify 0 to accept multiple selections (up to the amount of values there are), or another number for an arbitrary maximum.
multiple_choice() {
  local CHOICE_VALUES_AS_STRING="$1"
  #cerr "CHOICE_VALUES_AS_STRING: $CHOICE_VALUES_AS_STRING"
  local CHOICE_TITLES_AS_STRING="${2:-}"
  #cerr "CHOICE_TITLES_AS_STRING: $CHOICE_TITLES_AS_STRING"
  test -z "$CHOICE_TITLES_AS_STRING" && {
    # if no titles were supplied, use values as titles, turning whitespace into pipes like the title string should have.
    CHOICE_TITLES_AS_STRING="$(echo -n "$CHOICE_VALUES_AS_STRING" | tr '[:space:]' '|')"
  }
  local CHOICE_VALUE_DELIMITER="${3:-}"
  test -z "$CHOICE_VALUE_DELIMITER" && CHOICE_VALUE_DELIMITER="$IFS"

  local MAX_SELECTIONS="${4:-1}"
  #cerr "MAX_SELECTIONS: $MAX_SELECTIONS"
  if ! is_positive_integer "$MAX_SELECTIONS"; then
    err "multiple_choice: expected an  integer >= 0 ; got '$MAX_SELECTIONS' instead."
  fi

  # turn the strings into arrays
  OLDIFS="$IFS"
  local CHOICE_VALUES_AS_ARRAY
  IFS="$CHOICE_VALUE_DELIMITER" read -r -a CHOICE_VALUES_AS_ARRAY <<< "$CHOICE_VALUES_AS_STRING"
  local CHOICE_TITLES_AS_ARRAY
  IFS='|' read -r -a CHOICE_TITLES_AS_ARRAY <<< "$CHOICE_TITLES_AS_STRING"
  IFS="$OLDIFS"

  # Sanity check - make sure we have the same number of items in each list.
  local CHOICE_VALUES_COUNT="${#CHOICE_VALUES_AS_ARRAY[@]}"
  if [ "$MAX_SELECTIONS" -eq 0 ]; then
    MAX_SELECTIONS=$CHOICE_VALUES_COUNT
  fi
  #cerr "CHOICE_VALUES_COUNT: $CHOICE_VALUES_COUNT"
  local CHOICE_TITLES_COUNT="${#CHOICE_TITLES_AS_ARRAY[@]}"
  #cerr "CHOICE_TITLES_COUNT: $CHOICE_TITLES_COUNT"
  if [ "$CHOICE_VALUES_COUNT" -ne "$CHOICE_TITLES_COUNT" ]; then
    warn "multiple_choice() - The number of choice values did not match number of choice titles... results may be unpredictable"
  fi

  # Present the choices
  local CHOICE_COUNT=0
  for ((LOOP=0; LOOP < "${#CHOICE_VALUES_AS_ARRAY[*]}"; LOOP++)); do
    CHOICE_COUNT=$((CHOICE_COUNT+1))
    local CHOICE_VALUE="${CHOICE_VALUES_AS_ARRAY[$LOOP]}"
    local CHOICE_TITLE="${CHOICE_TITLES_AS_ARRAY[$LOOP]}"
    if [[ "${CHOICE_TITLE}" == "${CHOICE_VALUE}" ]]; then
      cerr "[${CHOICE_COUNT}] ${CHOICE_TITLE}"
    else
      cerr "[${CHOICE_COUNT}] ${CHOICE_TITLE} (${CHOICE_VALUE})"
    fi
  done

  # Collect and validate chocies
  local PROMPT_TEXT
  if [ "$MAX_SELECTIONS" -eq 1 ]; then
    PROMPT_TEXT="Please select: "
  else
    PROMPT_TEXT="Enter up to $MAX_SELECTIONS selections, separated by space or comma: "
  fi
  local RETURNED_OUTPUT=''
  VALID_SELECTION_COUNT=0
  while [ $VALID_SELECTION_COUNT -lt 1 ]; do
    #cerr "VALID_SELECTION_COUNT: $VALID_SELECTION_COUNT"
    >&2 echo -n "$PROMPT_TEXT"
    local USER_INPUT=''
    read -r USER_INPUT
    #cerr "USER_INPUT: $USER_INPUT"
    USER_INPUT=$(echo "$USER_INPUT" |tr --squeeze ',' ' ')
    #cerr "USER_INPUT: $USER_INPUT"
    for NUMBER in $USER_INPUT; do
      #cerr "NUMBER: $NUMBER"
      #cerr "CHOICE_VALUES_COUNT: $CHOICE_VALUES_COUNT"
      if is_positive_integer "$NUMBER" \
        && [ "$NUMBER" -le "$CHOICE_VALUES_COUNT" ] \
        && [ "$NUMBER" -gt 0 ]; then
        VALID_SELECTION_COUNT=$((VALID_SELECTION_COUNT + 1))
        RETURNED_OUTPUT="$RETURNED_OUTPUT ${CHOICE_VALUES_AS_ARRAY[$((NUMBER - 1))]}"
        #cerr "RETURNED_OUTPUT: $RETURNED_OUTPUT"
        #cerr "VALID_SELECTION_COUNT: $VALID_SELECTION_COUNT"
        #cerr "MAX_SELECTIONS; $MAX_SELECTIONS"
        if [ $VALID_SELECTION_COUNT -ge "$MAX_SELECTIONS" ]; then
          break 2;
        fi
      else
        cerr "Invalid choice: $NUMBER"
        VALID_SELECTION_COUNT=0
        RETURNED_OUTPUT=''
      fi
    done
  done

  # Send the value to STDOUT for the caller to capture
  echo "$RETURNED_OUTPUT" | awk '{$1=$1};1' # Trim leading/trailing space
}


require_yes_or_no() {
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


confirm () {
  >&2 echo -n "$@"
  read -r CONFIRMATION
  if [[ "${CONFIRMATION}" != 'y' ]]; then
    false
  fi
}


require_script () {
  type "$1" > /dev/null  2>&1 || {
    err "The following is not installed or not in path: $1"
    exit "$ERR_SCRIPT_REQUIRED"
  }
}

# Usage
# -----
#   Only one argument is required if the package and binary are named the same thing:
#
#       require_package tree
#
#   If the binary you require comes from a package with a different name, specify the package name as the 2nd argument:
#
#       require_package pip python-pip
#
#   If you want this funciton to automatically try installing missing package, specify all 3 args, even if binary and package are the same:
#
#       require_package tree tree 1
#       require_package pip python-pip 1
#
require_package () {
  local BINARY="$1"
  local PACKAGE="${2:-}"
  local ATTEMPT_INSTALL_IF_MISSING="${3:-0}"
  test -z "$PACKAGE" && PACKAGE="$BINARY"
  type "$BINARY" > /dev/null  2>&1 || {
    cerr "Package '$PACKAGE' is required, but not found."
    if [ "$ATTEMPT_INSTALL_IF_MISSING" -eq 1 ]; then
      #echo  "Will try installing it..."
      apt-get -y install "$PACKAGE" || yum -y install "$PACKAGE" || {
        err "require_package(): Could not install '$PACKAGE'."
        exit "$ERR_PACKAGE_REQUIRED"
      }
    else
      err "Please install '$PACKAGE' and try again."
      exit 1
    fi
  }
}

require_root_e() {
  if [ $EUID -ne 0 ]; then
    err "This script must be run as root. Hint: Run with 'sudo -E' for best results."
    exit "$ERR_ROOT_REQUIRED"
  fi
}

require_root_i() {
  if [ $EUID -ne 0 ]; then
    err "This script must be run as root. Hint: Run with 'sudo -i' for best results."
    exit "$ERR_ROOT_REQUIRED"
  fi
}

require_root() {
  if [ $EUID -ne 0 ]; then
    err "This script must be run as root."
    exit "$ERR_ROOT_REQUIRED"
  fi
}


fatal () {
  bold_feedback "Fatal" "$@"
}

err () {
  bold_feedback "Err" "$@"
}

warn () {
  bold_feedback "Warn" "$@"
}

bold () {
  >&2 echo "${BOLD}${*}${UNBOLD}"
}

# Requires Two arguments
bold_feedback () {
  local PREFIX
  PREFIX="${1:-"bold_feedback received no arguments"}"
  shift || true
  local MESSAGE="$*"
  cerr "${BOLD}${PREFIX}:${UNBOLD} ${MESSAGE}"
}

# To turn on messages, 'export DEBUG=1' before running the script.
# To use, pass the NAME of the variable, not the value:
# i.e. "deubg FOO" instead of "debug $FOO"
debug () {
  local DEBUG_IS_ON="${DEBUG:-0}"
  if [ ! "${DEBUG_IS_ON}" -eq 1 ]; then
    return
  fi
  >&2 echo "!1 - ${!1}"
  >&2 echo " 1 - ${1}"
  bold_feedback "DEBUG" "${1} -> ${!1}"
}



info () {
  cerr "${GREY}INFO ${*}${NC}"
}

cerr () {
  >&2 echo "$@"
}


strip_unsafe_sql_chars () {
  TEMPVAL="$1"
#  sed -e 's/^"//' -e 's/"$//' <<< "$TEMPVAL"    # If you only wanted double quotes from the beginning and end.
  TEMPVAL="$(echo -n "$TEMPVAL"|sed -e "s/'//g")"
  TEMPVAL="$(echo -n "$TEMPVAL"|sed -e 's/"//g')"
  TEMPVAL="$(echo -n "$TEMPVAL"|sed -e 's/`//g')"
  TEMPVAL="$(echo -n "$TEMPVAL"|sed -e 's/\\//g')"
  echo -n "$TEMPVAL"
}


# Use like so:
#  DRUPAL_ROOT="$(prompt_for_value_with_default "DRUPAL_ROOT" "$DEFAULT_VALUE")"
prompt_for_value_with_default() {
  # All this for the benefit of RHEL 5, which uses bash 3, and doesn't support the "-i" switch of the "read" shell builtin.
  local VARIABLE_NAME="$1"
  local DEFAULT_VALUE="$2"
  local VARIABLE_VALUE
  trap "stty sane" SIGINT  # When using "read -e", weird things happen if ctrl + c gets called. Stty sane fixes that. Could also use 'reset' but thats really aggressive.
  read -r -e -p "$VARIABLE_NAME: " -i "$DEFAULT_VALUE" VARIABLE_VALUE
  # Return the value to the caller.
  echo "$VARIABLE_VALUE"
}

is_sane_fqdn () {
  local ARG="$1"
  if echo "$ARG" | grep -Pq '(?=^.{5,254}$)(^(?:(?!\d+\.)[a-zA-Z0-9_\-]{1,63}\.?)+(?:[a-zA-Z]{2,})$)'; then
    true
  else
    false
  fi
}

## Not quite as smart as how `ls` presents human readable sizes, but good enough for our purposes.
human_print_bytes () {
  ############################
  # Warning: Number comparisons produce errors if they are larger than the
  # integer limit for bash on the system. (64 bits for bash => 4).
  # [ X -lt 9223372036854775807 ] == OK
  # [ X -lt 9223372036854775808 ] == "integer expression expected" error
  ############################
  local BYTES
  BYTES="$1"
  local chrlen="${#BYTES}"
  if [ "$chrlen" -gt 16 ]; then
    >&2 printf "human_print_bytes() Warning: This function can't be trusted with numbers approaching 64 bits in length.\n"
  fi
  if ! is_integer "${BYTES}"; then
    >&2 echo "ERR: human_print_bytes(): Invalid argument: ${BYTES}"
    return 1
  fi
  local POSNEG=''
  if [ "${BYTES}" -lt 0 ]; then
    POSNEG='-'
    BYTES=$((0 - BYTES))
  fi
  local DECIMAL_AS_STRING=''
  local SuffixIndex=0
  local SUFFIXES=(Bytes {K,M,G,T,P,E,Z,Y}iB)
  while ((BYTES > 1024)); do
    DECIMAL_AS_STRING="$(printf ".%02d" $((BYTES % 1024 * 100 / 1024)))"
    BYTES=$((BYTES / 1024))
    SuffixIndex=$((SuffixIndex+1))
  done
  echo "${POSNEG}${BYTES}${DECIMAL_AS_STRING} ${SUFFIXES[$SuffixIndex]}"
}

function is_ip_address() {
  if [[ "$1" =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then
    true
  else
    false
  fi
}

function get_file_size () {
  local FULLPATH=$1
  if [ ! -f "$FULLPATH" ]; then
    err "file_size() - File not found: $FULLPATH"
    exit 1
  fi
  local BYTES
  BYTES=$(wc -c "$FULLPATH"|awk '{print $1}')
  if ! is_positive_integer "$BYTES"; then
    err "file_size() - Expected integer, got '$BYTES' instead: $FULLPATH"
    exit 1
  fi
  echo -n "$BYTES"
}
