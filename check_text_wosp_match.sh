#!/bin/bash
# Checks that the CoNLL shared task test data match the raw text.

GDIR=/media/test-datasets-truth/universal-dependency-learning/conll17-ud-test-2017-05-07
IDIR=/media/test-datasets/universal-dependency-learning/conll17-ud-test-2017-05-07

for gfile in $GDIR/*.conllu ; do
  echo `basename $gfile`
  pfile=$IDIR/`basename $gfile .conllu`-udpipe.conllu
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
