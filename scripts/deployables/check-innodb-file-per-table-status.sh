#!/bin/bash

# First thing to do is look in my.cnf to see if innodb_file_per_table is already set.
if [ -f /etc/my.cnf ]; then
  MYCONF="/etc/my.cnf"
elif [ -f /etc/mysql/my.cnf ]; then
  MYCONF="/etc/mysql/my.cnf"
elif [ -f /usr/etc/my.cnf ]; then
  MYCONF="/usr/etc/my.cnf"
else
  echo "No my.cnf file exists, or you don't have permission to view it. Try running as root. Exiting now."
  exit 1
fi

if [ ! -r "$MYCONF" ]; then
  echo "You don't have permission to read $MYCONF. Try running as root instead. Exiting now."
  exit 1
fi

echo "Looking for 'innodb_file_per_table' in $MYCONF..."
if grep innodb_file_per_table "$MYCONF"; then
  echo "The above line is from $MYCONF ... if it's not commented out, and the variable evaluates to TRUE, then file-per-table is already on."
else
  echo "Not found. You need to add"
  echo "innodb_file_per_table=1"
  echo "to the [mysqld] section of $MYCONF"
  exit
fi

echo ""
echo "Confirming 'innodb_file_per_table' settings from mysql running config..."
mysql -e "show variables like '%file_per_table%'" || {
  echo "Could not get variables from mysql. Do you have access?"
}
