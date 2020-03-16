#!/bin/bash -ue
set -o pipefail

# For use on brand new Ubuntu machines
# @TODO Make this work for CentOS too

function usage () {
  >&2 echo "Usage:"
  >&2 echo "  ssh USER@X.X.X.X 'sudo bash -s' < $(basename "$0") host.domain.com"
  >&2 echo "or:"
  >&2 echo "  ssh USER@X.X.X.X 'sudo bash -s' < $(basename "$0") host.domain.com --replace"
  >&2 echo "Where X.X.X.X is the current IP address of the remote Ubuntu server,"
  >&2 echo "and HOST.DOMAIN.COM is the new fully qualified domain name you want to set."
  >&2 echo "Use the --replace option to overwrite the whole hosts file. A backup will be made."
}


# Root is required
if [[ $EUID -ne 0 ]]; then
  >&2 echo "Err: This script needs to be run as root."
  usage
  exit 11
fi


# Get FQDN
if env |grep -qE ^NEW_FQDN= ; then
  : # already set in the environment.
else
  # take it from the command line
  NEW_FQDN="${1:-}"; shift
fi
>&2 echo "NEW_FQDN: $NEW_FQDN"
if test -z "$NEW_FQDN"; then
  >&2 echo "Err: Missign NEW_FQDN as argument or environment variable."
  usage
  exit 45
fi


# Derive short hostname
if [[ "$NEW_FQDN" == *"."* ]]; then
  SHORTHOSTNAME="$(echo "$NEW_FQDN"|cut -d"." -f1)"
else
  SHORTHOSTNAME="$NEW_FQDN"
fi
>&2 echo "SHORTHOSTNAME: $SHORTHOSTNAME"



# Set hosts file
HOSTS="/etc/hosts"
HOSTSBAK="$HOSTS.$(date +%s.%N)~"
cp -av "${HOSTS}" "${HOSTSBAK}"
if [[ "${1:-}" == "--replace" ]]; then
  shift
  {
  echo "127.0.0.1 localhost"
  echo "127.0.1.1 $NEW_FQDN $SHORTHOSTNAME"
  echo "# The following lines are desirable for IPv6 capable hosts"
  echo "::1 ip6-localhost ip6-loopback"
  echo "fe00::0 ip6-localnet"
  echo "ff00::0 ip6-mcastprefix"
  echo "ff02::1 ip6-allnodes"
  echo "ff02::2 ip6-allrouters"
  echo "ff02::3 ip6-allhosts"
  } | tee "$HOSTS"
  >&2 echo "Replaced hosts file."
else
  if grep -P "127\.0\..\.1.* $NEW_FQDN\b" "$HOSTS" && grep -P "127\.0\..\.1.* $NEW_FQDN([^\.]|$)" "$HOSTS"; then
    >&2 echo "$NEW_FQDN already exists in $HOSTS"
  else
    if [ ! -f "$HOSTSBAK" ]; then
      cp -a "$HOSTS" "$HOSTSBAK" || {
        >&2 echo "Err: Could not back up $HOSTSBAK"
        exit 33
      }
    fi
    >&2 echo "Adding $NEW_FQDN to $HOSTS"
    echo "127.0.1.1 $NEW_FQDN" >> "$HOSTS"
  fi
  if grep -P "127\.0\..\.1.* $SHORTHOSTNAME\b" "$HOSTS" && grep -P "127\.0\..\.1.* $SHORTHOSTNAME([^\.]|$)" "$HOSTS"; then
    >&2 echo "$SHORTHOSTNAME already exists in $HOSTS"
  else
    if [ ! -f "$HOSTSBAK" ]; then
      cp -a "$HOSTS" "$HOSTSBAK" || {
        >&2 echo "Err: Could not back up $HOSTSBAK"
        exit 33
      }
    fi
    >&2 echo "Adding $SHORTHOSTNAME to $HOSTS"
    echo "127.0.1.1 $SHORTHOSTNAME" >> "$HOSTS"
  fi
fi

# Set hostname
HOSTNAMEFILE="/etc/hostname"
if grep -qE "^$NEW_FQDN$" "$HOSTNAMEFILE"; then
  >&2 echo "Hostname is already set to $NEW_FQDN"
else
  BAKFILE="$HOSTNAMEFILE.$(date +%s).bak"
  cp -a "$HOSTNAMEFILE" "$BAKFILE" || {
    >&2 echo "Err: Could not back up $HOSTNAMEFILE"
    exit 33
  }
  >&2 echo "Setting hostname to $NEW_FQDN"
  if test -x /usr/bin/hostnamectl; then
    # This utility takes care of both the /etc/hostname file and the sysconfig files.
    /usr/bin/hostnamectl set-hostname "$NEW_FQDN"
  else
    /bin/hostname "$NEW_FQDN"
    echo "$NEW_FQDN" > "$HOSTNAMEFILE"
  fi
fi
