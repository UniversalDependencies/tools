#!/bin/bash
# Scans the contents of the release folder and copies the shared task files into folders that should appear in TIRA.
UDPATH=/net/work/people/zeman/unidep
SRCREL=$UDPATH/release-2.2/ud-treebanks-conll2018
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
# Expected folder structure at TIRA: Datasets are mounted under /media/*.
# The top-level subfolders determine where, when and how the datasets are
# accessible:
# - training-datasets
# - training-datasets-truth
# - test-datasets
# - test-datasets-truth
# Each of these folders has subfolders for all shared tasks hosted at TIRA.
# Ours is called "universal-dependency-learning", its subfolders could be
# datasets of various years/rounds; we currently have CoNLL 2017 and 2018.
# The subfolders of the 2017 task are:
# - conll17-ud-trial-2017-03-19 (in training-datasets ==? training-datasets-truth; for ar, en, tr, vi, zh)
# - conll17-ud-development-2017-03-19 (in training-datasets ==? training-datasets-truth)
# - conll17-ud-test-2017-05-09 (in test-datasets and test-datasets-truth)
# So we should now create for 2018:
# - conll18-ud-trial-2018-03-06 (in training-datasets)
# - later also conll18-ud-development and conll18-ud-test
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
TASK="universal-dependency-learning/conll18-ud"
DATE="2018-03-06"
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
echo Small subset of the development data, intended for debugging. > $DSTTRIALI/README.txt
echo code-udpipe.conllu ... predicted segmentation and morphology, no syntax >> $DSTTRIALI/README.txt
echo code.txt ............. raw text input >> $DSTTRIALI/README.txt
echo code-udpipe.conllu ... predicted segmentation and morphology, no syntax > $DSTTESTI/README.txt
echo code.txt ............. raw text input >> $DSTTESTI/README.txt

# In the folders that the system can get as input, we will create metadata.json.
# The system should use it to identify what files it is supposed to process and
# how. Metadata fields:
cat << EOF > $DST/README-metadata.txt

The system must read metadata.json to obtain the list of test sets it is
supposed to process. Each test set has a record in the list, and the fields in
the record are interpreted as follows:

* lcode ..... language code (for UD languages same as in UD; but other
              languages may appear here too)
* tcode ..... treebank code (for UD treebanks same as in UD; but extra non-UD
              treebanks may appear here too)
* rawfile ... name of raw text file (input of systems that do their own
              segmentation)
* psegmorfile ... name of CoNLL-U file with segmentation and morphology
              predicted by a baseline system (currently UDPipe)
* outfile ... name of the corresponding CoNLL-U file that the system must
              generate in the output folder

Extra fields not needed by the participating system:

* goldfile ... name of the corresponding gold-standard file to be used by the
               evaluation script (in a separate folder)
EOF
cat $DST/README-metadata.txt >> $DSTDEVI/README.txt
cat $DST/README-metadata.txt >> $DSTTRIALI/README.txt
cat $DST/README-metadata.txt >> $DSTTESTI/README.txt
rm $DST/README-metadata.txt



# Copy the data to the folders.
cd $SRCREL
echo '[' > $DSTDEVI/metadata.json
echo '[' > $DSTTRIALI/metadata.json
echo '[' > $DSTTESTI/metadata.json
for i in UD_* ; do
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
    echo -n '  {"lcode":"'$lcode'", "tcode":"'$tcode'", "rawfile":"'$ltcode'.txt", "psegmorfile":"'$ltcode'-udpipe.conllu", "outfile":"'$ltcode'.conllu", "goldfile":"'$ltcode'.conllu"}' >> $DSTDEVI/metadata.json
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
  if [ "$i" = "UD_English-GUM" ] || [ "$i" = "UD_Czech-PDT" ] || [ "$i" = "UD_Arabic-PADT" ] || [ "$i" = "UD_Chinese-GSD" ] || [ "$i" = "UD_Swedish-Talbanken" ] ; then
    if [ -z "$firsttrial" ] ; then
      firsttrial="nolonger"
    else
      echo , >> $DSTTRIALI/metadata.json
    fi
    echo -n '  {"lcode":"'$lcode'", "tcode":"'$tcode'", "rawfile":"'$ltcode'.txt", "psegmorfile":"'$ltcode'-udpipe.conllu", "outfile":"'$ltcode'.conllu", "goldfile":"'$ltcode'.conllu"}' >> $DSTTRIALI/metadata.json
    split_conll.pl -head 50 < $i/$ltcode-ud-dev.conllu $DSTTRIALG/$ltcode.conllu /dev/null
    ../../tools/conllu_to_text.pl --lang $lcode < $DSTTRIALG/$ltcode.conllu > $DSTTRIALI/$ltcode.txt
    cp $SRCPSM/trial/$ltcode-udpipe.conllu $DSTTRIALI/$ltcode-udpipe.conllu
  fi
  # Copy the test data. All treebanks should have test data even if they do not
  # have training or development data.
  ltcode=$(ls $i | grep test.conllu | perl -pe 's/-ud-test\.conllu$//')
  lcode=$(echo $ltcode | perl -pe 's/_.*//')
  tcode=$(echo $ltcode | perl -pe 'if(m/_(.+)/) {$_=$1} else {$_=0}')
  echo $ltcode
  if [ -z "$firsttest" ] ; then
    firsttest="nolonger"
  else
    echo , >> $DSTTESTI/metadata.json
  fi
  echo -n '  {"lcode":"'$lcode'", "tcode":"'$tcode'", "rawfile":"'$ltcode'.txt", "psegmorfile":"'$ltcode'-udpipe.conllu", "outfile":"'$ltcode'.conllu", "goldfile":"'$ltcode'.conllu"}' >> $DSTTESTI/metadata.json
  chmod 644 $ltcode-ud-test.conllu
  cp $i/$ltcode-ud-test.conllu $DSTTESTG/$ltcode.conllu
  cp $i/$ltcode-ud-test.txt    $DSTTESTI/$ltcode.txt
  # Erase newdoc with nonsense id, add newdoc without id.
  # newdoc id = /net/work/people/zeman/unidep/data-for-tira/test-datasets/universal-dependency-learning/conll17-ud-test-2017-05-07/it.txt
  # WARNING! This command assumes that the first line is always a newdoc! At present this holds even for the surprise languages, although
  # their newdoc looks different.
  cat $ltcode-udpipe.conllu | tail -n +2 | (echo "# newdoc"; cat) > $DSTTESTI/$ltcode-udpipe.conllu
done
echo >> $DSTDEVI/metadata.json
echo >> $DSTTRIALI/metadata.json
echo >> $DSTTESTI/metadata.json
echo ']' >> $DSTDEVI/metadata.json
echo ']' >> $DSTTRIALI/metadata.json
echo ']' >> $DSTTESTI/metadata.json
cp $DSTDEVI/metadata.json $DSTDEVG/metadata.json
cp $DSTTRIALI/metadata.json $DSTTRIALG/metadata.json
cp $DSTTESTI/metadata.json $DSTTESTG/metadata.json



###!!! NO DEV TRAIN THIS TIME!
#rm -rf $DSTTRAINI
#rm -rf $DSTTRAING
#rm -rf $DSTDEVI
#rm -rf $DSTDEVG
#rm -rf $DSTTRIALI
#rm -rf $DSTTRIALG



cd $DST/..
rm tira.zip
cd $DST
zip -r ../tira.zip *
