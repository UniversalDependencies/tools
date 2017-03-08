#!/bin/bash
# Scans the contents of the release-2.0/ud-treebanks-conll2017 folder and copies the shared task files into folders that should appear in TIRA.
for i in UD_* ; do
  ltcode=$(ls $i | grep train.conllu | perl -pe 's/-ud-train\.conllu$//')
  lcode=$(echo $ltcode | perl -pe 's/_.*//')
  tcode=$(echo $ltcode | perl -pe 'if(m/_(.+)/) {$_=$1} else {$_=0}')
  #echo $ltcode $lcode $tcode
  echo '{"ltcode":"'$ltcode'", "lcode":"'$lcode'", "tcode":"'$tcode'", "rawfile":"'$ltcode'.txt", "goldfile":"'$ltcode'.conllu", "preprocessed": [{"udpipe":"'$ltcode'-udpipe.conllu"}], "outfile":"'$ltcode'.conllu"}'
done
