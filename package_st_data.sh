#!/bin/bash
# Scans the contents of the release-2.0/ud-treebanks-conll2017 folder and copies the shared task files into folders that should appear in TIRA.
UDPATH=/net/work/people/zeman/unidep
SRCREL=$UDPATH/release-2.0.1/ud-treebanks-conll2017
SRCTST=$UDPATH/testsets
# SRCMOR: UDPipe morphology, gold segmentation and syntax. This has been released in Lindat.
# SRCPSM: UDPipe segmentation and morphology, no syntax. Preprocessing for participants who do not want to do this on their own.
# This folder contains a pipeline that Milan created for this. The script process-tira-devel-trial.sh runs it on devel and trial.
# The script takes its input from my $DST folder (see below), thus it must be re-run if we change the data here. But right now
# the results are there, in folders development and trial, called code-udpipe.conllu.
# Milan has removed the unpacked SRCMOR folder from his home, thus I created
# a copy.
#SRCMOR=/home/straka/troja/conll2017-models-final/ud-2.0-conll17-crossfold-morphology
SRCMOR=/net/work/people/zeman/unidep/ud-2.0-conll17-crossfold-morphology
SRCPSM=/home/straka/troja/conll2017-tira/udpipe-preprocess
DSTFOLDER=data-for-tira
DST=$UDPATH/$DSTFOLDER
# Expected folder structure at TIRA: Datasets are mounted under /media/*. Each
# of the following folders has subfolders for all shared tasks hosted at TIRA.
# Ours is called "universal-dependency-learning", its subfolders could be
# datasets of various years/rounds, but we currently have only CoNLL 2017. All
# subfolders of "universal-dependency-learning" start with "conll17-universal-dependency-learning-",
# which seems unnecessarily long. We should ask Martin Potthast to shorten it.
# /media/training-datasets: Only this folder can be accessed by the participants.
#     It contains the training data (just in case they want to train something
#     here?), the development data (participants can access the development data
#     directly from their virtual machine, and they can run their system through
#     the web interface with the development data as input), and trial data
#     (a small subset of the development data, used for fast debugging).
#     These datasets may include the gold standard so that the participants can
#     access it when they experiment in their virtual machine; but a copy of the
#     gold standard must also exist in the "truth" folder mentioned below.
# /media/training-datasets-truth: Not accessible by the participants, although
#     the other tasks seem to have just a copy of the training and development
#     data here. This is probably the place where the evaluation script takes
#     the gold standard from.
# /media/test-datasets: Blind test data used as input for the systems. The
#     participants normally do not see it, their system only can access it when
#     the virtual machine is "sandboxed", to prevent information leaks.
#     Of course this folder must not contain gold-standard data.
# /media/test-datasets-truth: Gold standard test data used by the evaluation
#     script.
TASK="universal-dependency-learning/conll17-ud"
DATE="2017-05-07"
DSTTRAINI="$DST/training-datasets/$TASK-training-$DATE"
DSTTRAING="$DST/training-datasets-truth/$TASK-training-$DATE"
DSTDEVI="$DST/training-datasets/$TASK-development-$DATE"
DSTDEVG="$DST/training-datasets-truth/$TASK-development-$DATE"
DSTTRIALI="$DST/training-datasets/$TASK-trial-$DATE"
DSTTRIALG="$DST/training-datasets-truth/$TASK-trial-$DATE"
DSTTESTI="$DST/test-datasets/$TASK-test-$DATE"
DSTTESTG="$DST/test-datasets-truth/$TASK-test-$DATE"
# Generate the folders.
rm -rf $DST
mkdir -p $DSTTRAINI
mkdir -p $DSTTRAING
mkdir -p $DSTDEVI
mkdir -p $DSTDEVG
mkdir -p $DSTTRIALI
mkdir -p $DSTTRIALG
mkdir -p $DSTTESTI
mkdir -p $DSTTESTG
echo code.conllu .......... gold standard data > $DSTTRAINI/README.txt
echo code-pmor.conllu ..... gold segmentation and syntax, predicted morphology >> $DSTTRAINI/README.txt
echo code-udpipe.conllu ... predicted segmentation and morphology, no syntax >> $DSTTRAINI/README.txt
echo code.txt ............. raw text input >> $DSTTRAINI/README.txt
cp $DSTTRAINI/README.txt $DSTDEVI/README.txt
# In the folders that the system can get as input, we will create metadata.json.
# The system should use it to identify what files it is supposed to process and
# how. Metadata fields:
cat << EOF > $DST/README-metadata.txt

The system must read metadata.json to obtain the list of test sets it is
supposed to process. Each test set has a record in the list, and the fields in
the record are interpreted as follows:

* lcode ..... language code (for UD languages same as in UD; but other
              languages may appear here too)
* tcode ..... treebank code (first UD treebank for the language: "0";
              additional UD treebank: as in UD; extra non-UD treebanks may
              appear here too)
* rawfile ... name of raw text file (input of systems that do their own
              segmentation)
* psegmorfile ... name of CoNLL-U file with segmentation and morphology
              predicted by a baseline system (currently UDPipe)
* outfile ... name of the corresponding CoNLL-U file that the system must
              generate in the output folder

Extra fields not needed by the participating system:

* goldfile ... name of the corresponding gold-standard file to be used by the
               evaluation script (in a separate folder)
* ltcode ..... language_treebank code as in UD data (i.e. no "_0" for first
               treebanks)
* name ....... name of the corresponding UD repository, e.g.
               "UD_Ancient_Greek-PROIEL"
EOF
cat $DST/README-metadata.txt >> $DSTDEVI/README.txt
echo Small subset of the development data, intended for debugging. > $DSTTRIALI/README.txt
echo code-psegmor.conllu ... predicted segmentation and morphology, no syntax >> $DSTTRIALI/README.txt
echo code.txt .............. raw text input >> $DSTTRIALI/README.txt
cat $DST/README-metadata.txt >> $DSTTRIALI/README.txt
rm $DST/README-metadata.txt



# Copy the data to the folders.
cd $SRCREL
echo '[' > $DSTDEVI/metadata.json
echo '[' > $DSTTRIALI/metadata.json
###!!! Hack: temporarily blocking generation of training/development/trial data: UUUUD
for i in UUUUD_* ; do
  ltcode=$(ls $i | grep train.conllu | perl -pe 's/-ud-train\.conllu$//')
  lcode=$(echo $ltcode | perl -pe 's/_.*//')
  tcode=$(echo $ltcode | perl -pe 'if(m/_(.+)/) {$_=$1} else {$_=0}')
  echo $ltcode
  chmod 644 $i/$ltcode-ud-train.conllu
  cp $i/$ltcode-ud-train.conllu         $DSTTRAING/$ltcode.conllu
  cp $i/$ltcode-ud-train.conllu         $DSTTRAINI/$ltcode.conllu
  cp $SRCMOR/$i/$ltcode-ud-train.conllu $DSTTRAINI/$ltcode-pmor.conllu
  cp $i/$ltcode-ud-train.txt            $DSTTRAINI/$ltcode.txt
  # Some small treebanks do not have any dev set.
  if [ -f $i/$ltcode-ud-dev.conllu ] ; then
    if [ -z "$firstdev" ] ; then
      firstdev="nolonger"
    else
      echo , >> $DSTDEVI/metadata.json
    fi
    echo -n '  {"lcode":"'$lcode'", "tcode":"'$tcode'", "rawfile":"'$ltcode'.txt", "psegmorfile":"'$ltcode'-udpipe.conllu", "outfile":"'$ltcode'.conllu", "goldfile":"'$ltcode'.conllu", "name":"'$i'", "ltcode":"'$ltcode'"}' >> $DSTDEVI/metadata.json
    chmod 644 $i/$ltcode-ud-dev.conllu
    cp $i/$ltcode-ud-dev.conllu                  $DSTDEVG/$ltcode.conllu
    cp $i/$ltcode-ud-dev.conllu                  $DSTDEVI/$ltcode.conllu
    cp $SRCMOR/$i/$ltcode-ud-dev.conllu          $DSTDEVI/$ltcode-pmor.conllu
    cp $SRCPSM/development/$ltcode-udpipe.conllu $DSTDEVI/$ltcode-udpipe.conllu
    cp $i/$ltcode-ud-dev.txt                     $DSTDEVI/$ltcode.txt
  fi
  # Create a trial dataset for debugging purposes.
  # Unlike the development data, we will not provide the gold-standard file in the input folder.
  # The purpose is to make the setting as similar to the test data as possible.
  if [ "$i" = "UD_English" ] || [ "$i" = "UD_Turkish" ] || [ "$i" = "UD_Arabic" ] || [ "$i" = "UD_Chinese" ] || [ "$i" = "UD_Vietnamese" ] ; then
    if [ -z "$firsttrial" ] ; then
      firsttrial="nolonger"
    else
      echo , >> $DSTTRIALI/metadata.json
    fi
    echo -n '  {"lcode":"'$lcode'", "tcode":"'$tcode'", "rawfile":"'$ltcode'.txt", "psegmorfile":"'$ltcode'-udpipe.conllu", "outfile":"'$ltcode'.conllu", "goldfile":"'$ltcode'.conllu", "name":"'$i'", "ltcode":"'$ltcode'"}' >> $DSTTRIALI/metadata.json
    split_conll.pl -head 50 < $i/$ltcode-ud-dev.conllu $DSTTRIALG/$ltcode.conllu /dev/null
    ../../tools/conllu_to_text.pl --lang $lcode < $DSTTRIALG/$ltcode.conllu > $DSTTRIALI/$ltcode.txt
    cp $SRCPSM/trial/$ltcode-udpipe.conllu $DSTTRIALI/$ltcode-udpipe.conllu
  fi
done
echo >> $DSTDEVI/metadata.json
echo >> $DSTTRIALI/metadata.json
echo ']' >> $DSTDEVI/metadata.json
echo ']' >> $DSTTRIALI/metadata.json



# Copy the test data to the folders.
# We cannot do this in the UD_ loop above because there are test sets that do not have corresponding training sets.
cd $SRCTST
echo '[' > $DSTTESTI/metadata.json
for i in *-ud-test.conllu ; do
  ltcode=$(echo $i | perl -pe 's/-ud-test\.conllu$//')
  lcode=$(echo $ltcode | perl -pe 's/_.*//')
  tcode=$(echo $ltcode | perl -pe 'if(m/_(.+)/) {$_=$1} else {$_=0}')
  echo $ltcode
  chmod 644 $i/$ltcode-ud-test.conllu
  cp $ltcode-ud-test.conllu $DSTTESTG/$ltcode.conllu
  ../tools/conllu_to_text.pl --lang $lcode < $ltcode-ud-test.conllu > $DSTTESTI/$ltcode.txt
  ###!!! We also need $DSTTESTI/$ltcode-udpipe.conllu
done
echo >> $DSTTESTI/metadata.json
echo ']' >> $DSTTESTI/metadata.json



cd $DST/..
rm tira.zip
cd $DST
zip -r ../tira.zip *

