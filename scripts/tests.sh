#!/bin/bash -ue

ASSERT_SOURCE="${ASSERT_SOURCE:-"../vendor/assert.sh/assert.sh"}"

DEBUG=1

if test -f "$ASSERT_SOURCE"; then
  source "$ASSERT_SOURCE"
  echo "Loaded $ASSERT_SOURCE"
else
  echo "Oh snap. The assertion library for bash was not found at $ASSERT_SOURCE"
  echo "Move up to the top of the repo, run 'composer update' to get them and try again."
  exit 1
fi


echo -n 'require-named-parameter()'
# Test name/value pair in first position. Should return "bar"
assert "./deployables/require-named-parameter --foo --foo bar" "bar"
# Test name/value pair in nested position. Should return "baz"
assert "./deployables/require-named-parameter --foo -j 1 -k 2 --foo baz --lunkhead lemon --examp --le" "baz"
# Test value not found. Should raise error 1
assert_raises "./deployables/require-named-parameter --foo -x 1 -y 2 --zed 'three'" 1
# Test missing haystack. Should raise error 2
assert_raises "./deployables/require-named-parameter" 2
echo ' OK'


echo -n "optional-parameter-exists()"
# Test haystack not found
assert_raises "./deployables/optional-parameter-exists" 2
# Test needle not found.
assert_raises "./deployables/optional-parameter-exists --foo" 1
assert_raises "./deployables/optional-parameter-exists --foo --bing bong --ding dong" 1
# Test needle found
assert_raises "./deployables/optional-parameter-exists --foo --bing bong --foo" 0
assert_raises "./deployables/optional-parameter-exists --foo --foo --bing bong" 0
assert_raises "./deployables/optional-parameter-exists --foo --foo" 0
echo ' OK'

FUNCTIONS="deployables/functions.sh"
if test -f "$FUNCTIONS"; then
  source "$FUNCTIONS"
  echo "Loaded $FUNCTIONS"
else
  echo "Could not load $FUNCTIONS"
  exit 1
fi
shellcheck "$FUNCTIONS"
echo -n "Testing functions from $FUNCTIONS"
assert "cerr xyz 2>&1" 'xyz'
assert_contains "bold_feedback 2>&1" "bold_feedback received no arguments:"
assert_contains "bold_feedback abc 2>&1" "abc:"
assert_contains "bold_feedback abc def 2>&1" ' def'
assert_contains "bold_feedback abc def 2>&1" 'abc:'
#assert "info abc 2>&1" "abc" ####### Can't test "info()" as of Ubuuntu 16. It conflicts with /usr/bin/info
assert_contains "warn abc 2>&1" "Warn:"
assert_contains "warn abc 2>&1" "abc"
echo ' OK'
echo -n 'require_root'
assert_raises "require_root" $ERR_ROOT_REQUIRED
assert_raises "require_root_e" $ERR_ROOT_REQUIRED
assert_raises "require_root_i" $ERR_ROOT_REQUIRED
echo ' OK'
echo -n '"require" functions'
assert_raises "require_script /script/that/does/not/exist" $ERR_SCRIPT_REQUIRED
assert_raises "require_script /bin/ls" 0
assert_raises "require_package fictional-package-that-does-not-exist" $ERR_PACKAGE_REQUIRED
assert_raises "require_package awk" 0
echo ' OK'
echo -n 'confirm()'
assert_raises "echo 'y'|confirm 'y/n'" 0
assert_raises "echo 'n'|confirm 'y/n'" 1
assert_contains "echo 'n'|confirm 'y/n'" "y/n"
echo ' OK'

echo -n 'require_yes_or_no()'
assert_raises "echo 'y'|require_yes_or_no 'Some question?'" 0
assert_raises "echo 'n'|require_yes_or_no 'Some question?'" 1
assert_contains "echo 'y'|require_yes_or_no 'Some question?'" "Some question?"
echo ' OK'

assert_end

