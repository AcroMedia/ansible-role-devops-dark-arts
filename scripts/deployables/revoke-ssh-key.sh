#!/bin/bash

set -eu
set -o pipefail
BOLD=$(tput bold 2>/dev/null) || BOLD='\033[1;33m' # orange, if tput isnt available.
UNBOLD=$(tput sgr0 2>/dev/null) || UNBOLD='\033[m'

function usage () {
  cerr ""
  cerr "  Usage: $(basename "$0") '<ssh-key-to-revoke>' ['<replacement-line>']"
  cerr ""
  cerr "  Removes lines containing the specified key from all users' ~/.ssh/authorized_keys files."
  cerr "  Make sure to specify ONLY the core key to revoke. Not the 'ssh-rsa' prefix, or the comment."
  cerr ""
  cerr "  If a 2nd argument is supplied, everything starting from the 'ssh-*' protocol indicator"
  cerr "  on the old line is replaced with the supplied 'replacement-line' arguemnt. Everything before"
  cerr "  'ssh-' is preserved. This way, plain entries are just simple replacements, and entries that "
  cerr "  have speicific connection rules are not clobbered."
  cerr ""
  cerr "  Since 'sed' is used for replacements, ampersands, backslashes, and pipes are not allowed in the"
  cerr "  replacement-line argument."
  cerr ""
  cerr "  A backup is made of any modified files."
  cerr ""
}

function main () {
  if [[ $EUID -ne 0 ]]; then
     cerr "This script must be run as root"
     exit 1
  fi

  if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    usage
    exit 1
  fi

  KEYTOKILL="$1"
  STRING_LENGTH=${#KEYTOKILL}
  if [ "$STRING_LENGTH" -eq 68 ]; then
    true # ed25519 key
  elif [ "$STRING_LENGTH" -eq 204 ]; then
    true # rsa key, 1024 bits
  elif [ "$STRING_LENGTH" -eq 372 ]; then
    true # rsa key, 2048 bits
  elif [ "$STRING_LENGTH" -eq 716 ]; then
    true # rsa key, 4096 bits
  else
    warn "The key you specified to revoke does not appear to be standard length. If you are specifying a partial key, this is OK. Otherwise, you should double check your work."
  fi


  # Is there something to replace the defunct key with?
  if [ $# -ne 1 ]; then

    REPLACEMENTLINE="$2"
    REPLACE_KEY=1

    # Sanity check - new key line needs to be at least 208 chars.
    if [ ${#REPLACEMENTLINE} -lt 208 ]; then
      warn "The replacement line you specified seems too short to contain a valid key."
    fi

    # Check to make sure new key line doesn't contain any characters that will cause problems.
    if [[ "$REPLACEMENTLINE" == *[\|\\\&\"\']* ]]; then
      err "Replacement line cannot contain any of the following charcaters: '\, |, &', newlines or quotes."
      exit 1
    fi

    # Also check the key to revoke for funny characters: $.*[\]^ are sed specials,
    # plus the pipe character, since we are using it as our sed regex delimiter.
    # None of these characters should be in the keytokill string, but just in case
    # some fool has included a comment, we don't want things to blow up.
    if [[ "$KEYTOKILL" == *[\|\\\&$\.\*\[\]^\"\']* ]]; then
      err "The key to revoke should ONLY be the core base64 key, and should not contain any other special characters or comments."
      exit 1
    fi

  else
    REPLACE_KEY=0
  fi


  # -----------------------
  # Main
  # -----------------------

  # Grab a list of home dirs
  cut -d":" -f6 /etc/passwd | sort -u | while read -r line; do

    KEYFILE="$line/.ssh/authorized_keys"
    test -f "$KEYFILE" || continue

    info "Checking $KEYFILE ..."

    # Gitlab handles it's own keys. We should not touch that.
    if [[ "$KEYFILE" == "/var/opt/gitlab/.ssh/authorized_keys" ]]; then
      info "Ignoring $KEYFILE - it is managed by gitlab."
      continue
    fi

    # Normally there's only one instance of a key in a file, but sometimes it's duplicated. We need to handle that gracefully.
    # WHILE_LIMIT is to keep the script from looping into infinity in case something goes wrong while we remove or replace the key.
    # If there's more than WHILE_LIMIT instances of a key in a file, we should probably stop and fix that manually anyway.
    WHILE_COUNT=0
    WHILE_LIMIT=10
    while true; do
      WHILE_COUNT=$((WHILE_COUNT + 1))
      if [ $WHILE_COUNT -gt $WHILE_LIMIT ]; then
        err "Something's wrong with the script. WHILE_COUNT exceeded ${WHILE_LIMIT}"
        exit 1
      fi

      # If the offending key exists in the file, stay and process it. Otherwise exit the while, and move on to the next key file.
      grep -q "$KEYTOKILL" "$KEYFILE" || break
      info "  Key found (iteration #${WHILE_COUNT}) in $KEYFILE"

      # Make a copy preserving ownership & permissions so the user can get rid of the backup without having to sudo.
      BAKFILE="$KEYFILE.$(date +%Y-%m-%d-%H%M%S.%N).bak"
      info "  Backing up $KEYFILE"
      cp -a "$KEYFILE" "$BAKFILE"

      if [ $REPLACE_KEY -eq 1 ]; then

        OLD_LINE="$(grep -m 1 "$KEYTOKILL" "$KEYFILE")"
        if [[ "$OLD_LINE" =~ ^ssh-* ]]; then
          info "  Replacing old key line with new one"
          NEW_LINE="$REPLACEMENTLINE"
        else
          # There are other things that need to be preserved before the 'ssh-' part.
          cerr "  *** Key line does not start with 'ssh-' ... Will prepend the following: ***"
          cerr "      OLD_LINE: $OLD_LINE"
          PREPEND="$(echo "$OLD_LINE" | awk 'match($0, "ssh-") {print substr($0, 1, RSTART -1)}')"
          cerr "      PREPEND: $PREPEND"
          NEW_LINE="$PREPEND$REPLACEMENTLINE"
          cerr "      NEW_LINE: $NEW_LINE"
        fi

        # Stream the contents of the old file through sed, replacing the old key line with the new, overwriting the original file
        # Use vertical pipes instead of forward slashes in the regex: keys commonly contain forward slashes, but never pipes.
        # Because sed works line by line, we need the additional directives to make sure it only replaces the first instance found.
        # We do the one-at-a-time thing in case there are directives that need to be prepended. Otherwise we'd clobber all of them at once.
        NEWCONTENT="$(sed -e "s|.*${KEYTOKILL}.*|${NEW_LINE}|; ta; b; :a { n; ba; }" "${BAKFILE}")"
        # We do this in two separate commands so we don't kill the real file if something goes wrong with sed.
        cerr "Replace key in $KEYFILE (${WHILE_COUNT})"
        echo "$NEWCONTENT" > "$KEYFILE"


      else
        # Do an opposite grep - write everything EXCEPT the key's line back in to the original file.
        cerr "Remove key from $KEYFILE (${WHILE_COUNT})"
        grep -v "$KEYTOKILL" "$BAKFILE" > "$KEYFILE"

      fi
      info ""

    done # while true

  done   # looping through home dirs

}

function info () {
  if [ "${VERBOSE:-0}" == "1" ]; then
    cerr "$@"
  fi
}

function bold () {
  cerr "${BOLD}${*}${UNBOLD}"
}

function err () {
  bold_feedback "Err" "$@"
}

function warn () {
  bold_feedback "Warn" "$@"
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


main "$@"
