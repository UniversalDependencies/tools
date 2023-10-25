#!/bin/bash
# Checks that the CoNLL shared task test data match the raw text.

GDIR=/net/work/people/zeman/UD_Poetry_with_Udapi/manual
IDIR=/net/work/people/zeman/UD_Poetry_with_Udapi/automatic

for gfile in $GDIR/*.conllu ; do
  echo `basename $gfile`
  pfile=$IDIR/`basename $gfile .conllu`.conllu
  tfile=$IDIR/`basename $gfile .conllu`.txt
  text_without_spaces.pl --input conllutext < $gfile > /tmp/a
  text_without_spaces.pl --input conlluform < $gfile > /tmp/b
  diff /tmp/a /tmp/b
  text_without_spaces.pl --input conllutext < $pfile > /tmp/b
  diff /tmp/a /tmp/b
  text_without_spaces.pl --input conlluform < $pfile > /tmp/b
  diff /tmp/a /tmp/b
  text_without_spaces.pl --input plaintext  < $tfile > /tmp/b
  diff /tmp/a /tmp/b
  echo
done
