#!/bin/bash

if [[ "$1" == "" ]]
then
    echo "Usage: ./validate_all.sh DIR [DIR DIR ...]"
    echo "Will try to validate all files in these directories"
    echo
    echo "Examples: "
    echo "./validate_all.sh ~/UD_Finnish"
    echo "./validate_all.sh ~/UD/UD_*"
    exit
fi

lang_config["cs"]="--multi"

for D in $*
do
    echo $(basename "$D")
    if [[ $(ls $D/ | grep conllu | wc -l) == "0" ]]
    then
	echo "No data uploaded"
	continue
    fi
    for F in $D/*.conllu
    do
	L=$(echo $(basename "$F") | cut -f 1 -d-)
	echo -n "$(basename $F)"
	python validate.py ${lang_config[$L]} --noecho --lang=$L "$F" > /dev/null 2>&1
	RES=$?
	if [[ $RES == 0 ]]
	then
	    echo "    ... SUCCESS"
	else
	    echo "    ... FAIL"
	fi
    done
    echo
done

