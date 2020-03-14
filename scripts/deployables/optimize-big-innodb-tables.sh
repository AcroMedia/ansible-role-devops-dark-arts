#!/bin/bash


# --- Arguments & Configuration ---


# Name of database to process (Required)
DBNAME="$1"

# In MB - what is the minimum size file we want to consider (optional)
MINSIZE="$2"

# If not specified, what to default as
DEFAULTMINSIZE=750




# --- User defined functions ---

# Full path to running script
ME="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/$(basename "$0")"

# Show the best way to make this thing succeed
showhints() {
  echo ""
  echo "Make sure root's ~/.my.cnf is configured, and has 600 permissions."
  echo "Then try running as:"
  echo "  sudo -i $ME <dbname> [<minsize>]"
}



# --- Sanity checks ---


# Root is required
if [[ $EUID -ne 0 ]]; then
  echo "You will need root permissions to run this script."
  showhints
  exit 19
fi

# Check connectivity to MySQL (general)
DATABASE_LIST=$(mysql -N -e "SELECT CONCAT('  ', schema_name) FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','information_schema','performance_schema')") || {
  echo "Could not access mysql"
  showhints
  exit 34
}

# Required argument
if [[ ! "$DBNAME" ]]; then
  echo "Please supply the name of the mysql database to process:"
  echo "$DATABASE_LIST"
  exit 27
fi

# Check connectivity to MySQL (specific db)
mysql -e "use $DBNAME;"|| {
  echo "Could not access mysql db: $DBNAME"
  showhints
  exit 34
}

# Get location of mysql's data dir
NAMEVALUE=$(mysql -N -e "show variables where variable_name = 'datadir'") || {
  echo "Could not query mysql for variables."
  exit 40
}
MYDIRBASE=$(echo "$NAMEVALUE"|awk '{ print $2 }')
if [[ ! "$MYDIRBASE" ]]; then
  echo "Error: could not determine mysql data dir."
  exit 45
fi

# If file per table is not on, then there is no point being here.
FILE_PER_TABLE=$(mysql -N -e "show variables where variable_name = 'innodb_file_per_table'") || {
  echo "Could not query mysql for variables."
  exit 71
}
FILE_PER_TABLE_VALUE=$(echo "$FILE_PER_TABLE"|awk '{ print $2 }')
if [[ ! "$FILE_PER_TABLE_VALUE" == "ON" ]]; then
  echo "innodb_file_per_table is not ON, so there there is nothing to do. Have a nice day."
  exit 0
fi


# Double check that the DB exists and files can be read.
DBDIR="$MYDIRBASE/$DBNAME"
if [ ! -d "$DBDIR" ]; then
  echo "Mysql dir is not accessible: $DBDIR"
  showhints
  exit 53
fi

# Check for presence of minsize
if [[ ! "$MINSIZE" ]]; then
  MINSIZE="$DEFAULTMINSIZE"
  echo "Minsize not specified. Using default of $MINSIZE MB"
fi

# Minsize has to be an integer
if [[ ! "$MINSIZE" =~ ^-?[0-9]+$ ]]; then
  echo "Minsize is not a valid integer: $MINSIZE"
  echo "Using default of $MINSIZE MB"
fi



# --- Everything is in place. Let's do some work ---



# Temp file to hold list of file names to process
TEMPFILE=$(mktemp "$(basename "$0").XXXXXX") || {
  echo "Could not create temp file"
  exit 97
}

# Find all the DB files larger than X MB. Write the results to a temp file.
find "$DBDIR" \
-type f \
-size +"$MINSIZE"M \
-name "*.ibd" \
-print0 \
> "$TEMPFILE" || {
  echo "'find' command failed."
  exit 108
}

# Load the results from the temp file in to an array.
# Strip off the '.ibd' to convert the file in to the
# mysql table name.
TABLENAMES=()
echo ""
echo "The following tables will be optimized:"
while IFS=  read -r -d $'\0'; do
    FULL_PATH="$REPLY"
    FILESIZE=$(du -h "$FULL_PATH" | cut -f1)
    FILENAME=$(basename "$FULL_PATH")
    TABLENAME="${FILENAME%.*}"
    echo " $FILESIZE on disk: $TABLENAME"
    TABLENAMES+=("$TABLENAME")
done <"$TEMPFILE"

# Don't need the temp file anymore.
rm -f "$TEMPFILE"

DOALL=0
QUIT=0
TOTAL_BYTES_RECLAIMED=0
TOTAL_ELAPSED_SECONDS=0

# Move the files we want to process in to the temp dir.
for TABLE in "${TABLENAMES[@]}"; do
  RECORDS=$(mysql -D "$DBNAME" -N -e "select count(*) from "'`'"$TABLE"'`')
  FULL_PATH="$DBDIR/$TABLE.ibd"
  SIZE_BEFORE=$(du -h "$FULL_PATH" | cut -f1) || exit 158
  DISK_BYTES_BEFORE=$(wc -c "$FULL_PATH" | awk '{print $1}') || exit 159
  STATEMENT="optimize table "'`'"$TABLE"'`'
  TABLE_INDEX_BYTES=$(mysql -D "$DBNAME" -N -e "SELECT data_length + index_length FROM information_schema.TABLES WHERE table_schema = '$DBNAME' and table_name = '$TABLE';")
  #echo "$STATEMENT  /* $RECORDS records */"
  if [ $DOALL -eq 1 ]; then
    DOTHIS=1
  else
    echo ""
    MYPROMPT="Optimize '$TABLE' ($SIZE_BEFORE on disk,  $RECORDS records / $((100*TABLE_INDEX_BYTES/DISK_BYTES_BEFORE))% efficient)? [y]es, [n]o, [a]ll, [q]uit: "
    printf "%s" "$MYPROMPT"
    while read -r options; do
      case "$options" in
        "y") DOTHIS=1; break ;;
        "n") DOTHIS=0; echo "Skipping table."; break ;;
        "a") DOTHIS=1; DOALL=1; break ;;
        "q") QUIT=1; break ;;
        *) printf "%s" "$MYPROMPT" ;;
      esac
    done
  fi
  if [ $QUIT -eq 1 ]; then
    break;
  fi
  if [ $DOTHIS -eq 0 ]; then
    continue;
  fi
  echo ""
  echo "Working ... "
  STARTTIME=$(date +%s)
  mysql -D "$DBNAME" -e "$STATEMENT"
  ENDTIME=$(date +%s)
  SIZE_AFTER=$(du -h "$FULL_PATH" | cut -f1)
  BYTES_AFTER=$(wc -c "$FULL_PATH" | awk '{print $1}')
  ELAPSED_TIME=$((ENDTIME - STARTTIME))
  TOTAL_ELAPSED_SECONDS=$((TOTAL_ELAPSED_SECONDS + ELAPSED_TIME))
  echo "Elapsed time: $ELAPSED_TIME s"
  DIFFERENCE=$((DISK_BYTES_BEFORE - BYTES_AFTER))
  TOTAL_BYTES_RECLAIMED=$((TOTAL_BYTES_RECLAIMED + DIFFERENCE))
  echo "New file size: $SIZE_AFTER (reduced by $DIFFERENCE bytes)"
done

echo ""
echo "Total bytes reclaimed: $TOTAL_BYTES_RECLAIMED"
echo "Total time to process: $TOTAL_ELAPSED_SECONDS s"
echo ""
