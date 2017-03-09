#!/bin/bash
# Scans the contents of the release-2.0/ud-treebanks-conll2017 folder and copies the shared task files into folders that should appear in TIRA.
UDPATH=/net/work/people/zeman/unidep
SRCREL=$UDPATH/release-2.0/ud-treebanks-conll2017
SRCTST=$UDPATH/testsets
DST=$UDPATH/conll2017data-tira
rm -rf $DST
PRFX=""
mkdir -p $DST/${PRFX}training-data
mkdir -p $DST/${PRFX}dev-data-gold
mkdir -p $DST/${PRFX}dev-data-input
mkdir -p $DST/${PRFX}dev-data-output
mkdir -p $DST/${PRFX}test-data-gold
mkdir -p $DST/${PRFX}test-data-input
mkdir -p $DST/${PRFX}test-data-output
mkdir -p $DST/${PRFX}micro-data-gold
mkdir -p $DST/${PRFX}micro-data-input
mkdir -p $DST/${PRFX}micro-data-output
cd $SRCREL
echo '[' > $DST/metadata.json
for i in UD_* ; do
  ltcode=$(ls $i | grep train.conllu | perl -pe 's/-ud-train\.conllu$//')
  lcode=$(echo $ltcode | perl -pe 's/_.*//')
  tcode=$(echo $ltcode | perl -pe 'if(m/_(.+)/) {$_=$1} else {$_=0}')
  echo $ltcode
  echo '  {"name":"'$i'", "ltcode":"'$ltcode'", "lcode":"'$lcode'", "tcode":"'$tcode'", "rawfile":"'$ltcode'.txt", "goldfile":"'$ltcode'.conllu", "preprocessed": [{"udpipe":"'$ltcode'-udpipe.conllu"}], "outfile":"'$ltcode'.conllu"},' >> $DST/metadata.json
  chmod 644 $i/$ltcode-ud-train.conllu
  cp $i/$ltcode-ud-train.conllu $DST/${PRFX}training-data/$ltcode.conllu
  cp $i/$ltcode-ud-train.txt    $DST/${PRFX}training-data/$ltcode.txt
  # Some small treebanks do not have any dev set.
  if [ -f $i/$ltcode-ud-dev.conllu ] ; then
    chmod 644 $i/$ltcode-ud-dev.conllu
    cp $i/$ltcode-ud-dev.conllu   $DST/${PRFX}dev-data-gold/$ltcode.conllu
    cp $i/$ltcode-ud-dev.txt      $DST/${PRFX}dev-data-input/$ltcode.txt
  fi
  cp $SRCTST/$ltcode-ud-test.conllu $DST/${PRFX}test-data-gold/$ltcode.conllu
  ../../tools/conllu_to_text.pl --lang $lcode < $SRCTST/$ltcode-ud-test.conllu > $DST/${PRFX}test-data-input/$ltcode.txt
  # Create a micro-dataset for debugging purposes.
  if [ "$i" = "UD_English" ] || [ "$i" = "UD_Turkish" ] || [ "$i" = "UD_Arabic" ] || [ "$i" = "UD_Chinese" ] || [ "$i" = "UD_Vietnamese" ] ; then
    split_conll.pl -head 50 < $i/$ltcode-ud-dev.conllu $DST/${PRFX}micro-data-gold/$ltcode.conllu /dev/null
    ../../tools/conllu_to_text.pl --lang $lcode < $DST/${PRFX}micro-data-gold/$ltcode.conllu > $DST/${PRFX}micro-data-input/$ltcode.txt
  fi
done
echo ']' >> $DST/metadata.json


###!!! Mohl by Milan pro dev a test data alternativně vyrobit verze, které ani segmentaci nemají ruční?
#cp $i/$lt od Milana s morfologií, ale zaslepenou syntaxí!
###!!! od Milana s morfologií test sety zatím nemáme! A pro některé test sety se bude muset morfologie získávat zvláštním způsobem!
