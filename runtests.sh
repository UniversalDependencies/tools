#!/bin/bash

RESTORE=$(echo -en '\033[0m')
BOLD=$(echo -en '\033[1m')
RED=$(echo -en '\033[00;31m')
GREEN=$(echo -en '\033[00;32m')
YELLOW=$(echo -en '\033[00;33m')
BLUE=$(echo -en '\033[00;34m')
MAGENTA=$(echo -en '\033[00;35m')
PURPLE=$(echo -en '\033[00;35m')
CYAN=$(echo -en '\033[00;36m')
LIGHTGRAY=$(echo -en '\033[00;37m')
LRED=$(echo -en '\033[01;31m')
LGREEN=$(echo -en '\033[01;32m')
LYELLOW=$(echo -en '\033[01;33m')
LBLUE=$(echo -en '\033[01;34m')
LMAGENTA=$(echo -en '\033[01;35m')
LPURPLE=$(echo -en '\033[01;35m')
LCYAN=$(echo -en '\033[01;36m')
WHITE=$(echo -en '\033[01;37m')



# Run test cases through CoNLL-U validator.

#set -u

VALIDATOR="python validate.py --lang=testsuite"
VALID_DIR="test-cases/valid"
NONVALID_DIR="test-cases/nonvalid"

silent=false
success=0
failure=0

for validf in true false; do
    if [ "$validf" = true ]; then
	d="$VALID_DIR"
    else
	d="$NONVALID_DIR";
    fi

    for f in $d/*.conllu; do
	OUTP=$($VALIDATOR $f 2>&1)
	if [ $? -eq 0 ]; then
	    validv=true
	else
	    validv=false
	fi
	if [ "$validf" = "$validv" ]; then
	    success=$((success+1))
	    echo ${LGREEN}${BOLD}PASS $f${RESTORE}
	else
	    failure=$((failure+1))
	    echo ${LRED}${BOLD}FAIL "$f valid: $validf validated: $validv" ${RESTORE}
	fi
	if [[ "$1" == "-v" ]]
	then
	    echo -en "$OUTP" | egrep -v ' PASSED ' | egrep -v ' FAILED ' | egrep -v 'errors: [0-9]'
	    echo
        fi
    done
done

# Test the multiple ID thing over several files
OUTP=$($VALIDATOR $VALID_DIR/id_test_part*.conllu 2>&1)
if [ $? -eq 0 ]; then
    echo ${LRED}${BOLD}FAIL "Several files with id duplication across files not caught" ${RESTORE}
    failure=$((failure+1))
else
    echo ${LGREEN}${BOLD}PASS "Several files with id duplication across files" ${RESTORE}
    success=$((success+1))
    if [[ "$1" == "-v" ]]
    then
	echo -en "$OUTP" | egrep -v ' PASSED ' | egrep -v ' FAILED ' | egrep -v 'errors: [0-9]'
	echo
    fi
fi


echo "passed $success/$((success+failure)) tests."
