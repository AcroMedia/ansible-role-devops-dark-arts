#!/bin/bash -ue
set -o pipefail

###############################################################################
# Adds passwordless sudo for all users of a group, (usually wheel or 'sudo'), or
# for a single user.
#
# Assumes the server you're modifying picks up files from the /etc/sudoers.d directory.
#
# You can specify either a group name, or a username.
#
# If the name you specify exists as a group, the group will be given passwordless sudo.

# If there is no group by that name, but the name you specify is a user, the user will be given
# passwordless sudo.

# If the name you specify does not exist as either a group or a user, nothing will change.
#
# Execute locally (as root):
#   ./passwordless-sudo.sh sudo     # This is the normal sudoers group on Debian / Ubuntu
#   ./passwordless-sudo.sh wheel    # This is the normal sudoers group on Red Hat / CentOS
#   ./passwordless-sudo.sh johndoe  # Give an individual user passwordless sudo on either OS
#
# Run it remotely over SSH:
#   ssh USER@SERVER 'sudo bash -s' < ./passwordless-sudo.sh sudo     # Group on Ubuntu
#   ssh USER@SERVER 'sudo bash -s' < ./passwordless-sudo.sh wheel    # Group on RedHat
#   ssh USER@SERVER 'sudo bash -s' < ./passwordless-sudo.sh johndoe  # Individual on either OS
###############################################################################

SUDOERS="/etc/sudoers"
INCLUDEDIR="/etc/sudoers.d"
README="$INCLUDEDIR/README"
PWSUDOERS="$INCLUDEDIR/passwordless-sudoers"

function main () {

  if [ $EUID -ne 0 ]; then
     err "This script must be run as root"
     exit 1
  fi

  if [ ! -d "$INCLUDEDIR" ]; then
    err "Dir does not exist: $INCLUDEDIR"
    cerr "Is the sudo package installed?"
    # This can also happen if the sudo package is *VERY* old, but if that's the case, the script shouldn't be handling it.
    exit 1
  fi

  # We only accept one arg
  if [ $# -ne 1 ]; then
    cerr "Usage:"
    cerr "  $(basename "$0") GROUP_OR_USER"
    exit 1
  fi

  # Validate the argument
  OPTION1="$1"
  if getent group -- "${OPTION1}" > /dev/null; then
    USER_OR_GROUP_STRING="%${OPTION1}"
  elif getent passwd -- "${OPTION1}" > /dev/null; then
    USER_OR_GROUP_STRING="${OPTION1}"
  else
    err "The group or user '${OPTION1}' does not exist on the system."
    exit 1
  fi


  # Make sure the line exists in /etc/sudoers that's actually going to include the file we create.
  if grep -qx "^@includedir ${INCLUDEDIR}" "$SUDOERS"; then  # Sudo >= 1.9.2
    true  # The line starts with an @ symbol on >= 22.04
  elif grep -qx "^#includedir ${INCLUDEDIR}" "$SUDOERS"; then  # Sudo < 1.9.2
    true  # The line starts with a hash symbol on <= 20.04
  else
    err "The file '${SUDOERS}' does not include files from '${INCLUDEDIR}'."
    cerr "The sudoers file must be adjusted with visudo before this script can be used."
    exit 1
  fi

  # Make sure there's a readme file in the sudoers.d directory.
  # It's common for no files to exist in the sudoers.d dir on CentOS/RHEL.
  # Best practice is to always have at least one file there, even if it is just a readme.
  if [ ! -f "$README" ]; then
    echo "# Always use 'visudo -f <filename>' to update sudoers content." | EDITOR="tee -a" visudo -f "$README" > /dev/null
    RESULT=$?
    if [ $RESULT -ne 0 ]; then
      err "Could not create $README"
      cerr "The last command exited with error $RESULT. Aborting."
      exit $RESULT
    fi
  fi

  # Create the base passwordless-sudoers file
  if [ ! -f "$PWSUDOERS" ]; then
    {
      echo "## Always use 'visudo' to update sudoers content:"
      echo "##   visudo -f $PWSUDOERS"
      echo "## Single user:"
      echo "# yourusername ALL = (ALL) NOPASSWD: ALL"
      echo "## All users of a group:"
      echo "# %unixgroup ALL = (ALL) NOPASSWD: ALL"
      echo ""
    } | EDITOR="tee -a" visudo -f "$PWSUDOERS" > /dev/null
    RESULT=$?
    if [ $RESULT -ne 0 ]; then
      err "Could not create $PWSUDOERS"
      exit $RESULT
    fi
  fi

  # Finally. Add the specified user or group to the file.
  # Let this get printed to stdout so the user knows something happened.
  PW_SUDOER_LINE="${USER_OR_GROUP_STRING} ALL = (ALL) NOPASSWD: ALL"
  if grep -qx "$PW_SUDOER_LINE" "$PWSUDOERS"; then
    cerr "OK (already exists)"
  else
    echo "${USER_OR_GROUP_STRING} ALL = (ALL) NOPASSWD: ALL" | EDITOR="tee -a" visudo -f "$PWSUDOERS"
    RESULT=$?
    if [ $RESULT -ne 0 ]; then
      err "Adding ${USER_OR_GROUP_STRING} to $PWSUDOERS failed."
      exit $RESULT
    fi
    cerr "OK"
  fi

}

function err() {
  cerr "ERR: $*"
}

function warn () {
  cerr "WARN: $*"
}

function cerr() {
  >&2 echo "$@"
}

main "$@"
