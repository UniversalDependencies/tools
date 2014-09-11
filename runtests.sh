#!/bin/bash

# Run test cases through CoNLL-U validator.

set -u

VALIDATOR="python validate.py --quiet"
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
    
    for f in $d/*; do 
	$VALIDATOR < $f
	if [ $? -eq 0 ]; then
	    validv=true
	else
	    validv=false
	fi
	if [ "$validf" = "$validv" ]; then
	    success=$((success+1))
	    output_mark="pass: "
	else
	    failure=$((failure+1))
	    output_mark="FAIL: "
	fi
	if [ "$silent" = false ]; then
	    echo "$output_mark$f: valid: $validf validated: $validv" >&2;
	fi
    done
done

echo "passed $success/$((success+failure)) tests."
