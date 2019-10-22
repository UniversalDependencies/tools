#!/bin/bash
# Prepares a UD release.
# Copyright © 2016, 2017, 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

if [ "$RELEASE" = "" ] || [ "$1" = "" ]; then
  echo "Usage: RELEASE=2.0 tools/package_ud_release.sh UD_Ancient_Greek UD_Ancient_Greek-PROIEL ..."
  echo "       UD repositories to be included in the release must be listed as arguments."
  echo "       Repositories without test data will be skipped even if they are given as arguments."
  echo "       Use tools/check_files.pl to get the list of releasable repositories."
  echo "Usage: RELEASE=2.0 tools/package_ud_release.sh --update UD_X UD_Y"
  echo "       Only update the repositories UD_X and UD_Y in an already existing release folder."
  echo "       The option --update must be the first item after the script name."
  exit 255
fi



#------------------------------------------------------------------------------
# Copies one UD treebank to the current folder (only files that shall be
# released). We assume that the current folder the parent of the source dir.
#------------------------------------------------------------------------------
function copy_data_repo
{
    local dstdir=release-$RELEASE/ud-treebanks-v$RELEASE
    if [ ! -z "$STSET" ] ; then
        dstdir=release-$RELEASE/ud-treebanks-conll2018
    fi
    mkdir -p $dstdir
    echo Copying $1 to $dstdir
    rm -rf $dstdir/$1
    cp -r $1 $dstdir
    # Erase files that should not be released (.gitignore, .gitattributes, .git, .travis.yml, not-to-release).
    rm -rf $dstdir/$1/CONTRIBUTING.md $dstdir/$1/.git* $dstdir/$1/.travis.yml $dstdir/$1/not-to-release
    # The training data in UD_Czech-PDT and in UD_German-HDT is split to
    # multiple files because it is too large for Github.
    # However, it can be one file in our release, so join the files again in the release copy.
    if [ "$1" == "UD_Czech-PDT" ] ; then
        cat $dstdir/$1/cs_pdt-ud-train-*.conllu > $dstdir/$1/cs_pdt-ud-train.conllu
        rm $dstdir/$1/cs_pdt-ud-train-*.conllu
    elif [ "$1" == "UD_German-HDT" ] ; then
        cat $dstdir/$1/de_hdt-ud-train-*.conllu > $dstdir/$1/de_hdt-ud-train.conllu
        rm $dstdir/$1/de_hdt-ud-train-*.conllu
    fi
    # If we are creating the special package for the CoNLL 2018 shared task,
    # and if this treebank is considered small, merge its training and development data.
    local lcode=$(ls $1 | grep ud-test.conllu | perl -e '$x=<STDIN>; $x =~ m/(\S+)-ud-test\.conllu/; print $1;')
    if [ "$STSET" == "SMALL" ] ; then
        echo This is a small treebank. Merging training and development data.
        if [ -f $dstdir/$1/$lcode-ud-train.conllu ] ; then
            cat $dstdir/$1/$lcode-ud-dev.conllu >> $dstdir/$1/$lcode-ud-train.conllu
            rm $dstdir/$1/$lcode-ud-dev.conllu
        else
            mv $dstdir/$1/$lcode-ud-dev.conllu $dstdir/$1/$lcode-ud-train.conllu
        fi
    fi
    # Generate raw text files from CoNLL-U files. At present we do not maintain
    # the raw text files in Github repositories and only generate them for the release.
    # Also we want one cs_pdt-ud-train.txt and not four (see above).
    if [ "$lcode" = "" ] ; then echo Unknown language code ; fi
    for j in $dstdir/$1/*.conllu ; do
      tools/conllu_to_text.pl --lang $lcode < $j > $dstdir/$1/$(basename $j .conllu).txt
    done
}

#------------------------------------------------------------------------------



echo RELEASE $RELEASE

# Create the release folder if it does not exist yet.
mkdir -p release-$RELEASE/ud-treebanks-v$RELEASE

# If the first argument is --update, we will only update the listed treebanks but we will not do anything with docs and tools.
if [ "$1" == "--update" ] ; then
    ONLY_UPDATE_TREEBANKS=YES
    shift
else
    ONLY_UPDATE_TREEBANKS=NO
fi
# If the first argument is --large or --small, we will only create the extra package for the shared task.
if [ "$1" == "--small" ] ; then
    STSET=SMALL
    shift
elif [ "$1" == "--large" ] ; then
    STSET=LARGE
    shift
fi

# Copy there the repositories that contain .conllu data (skip empty repositories!)
for i in $@ ; do
    if [ "$i" == "--small" ] ; then
        STSET=SMALL
    elif [ "$i" == "--large" ] ; then
        STSET=LARGE
    elif [ -f $i/*-ud-test.conllu ] ; then
        copy_data_repo $i
    else
        echo Skipping $i because no test data found.
    fi
done
cd release-$RELEASE
if [ ! -z "$STSET" ] ; then
    echo Packaging all shared task treebanks in one TGZ archive...
    tar czf ud-treebanks-conll2018.tgz ud-treebanks-conll2018
    cd ..
    exit
fi
echo Packing all treebanks in one TGZ archive...
tar czf ud-treebanks-v$RELEASE.tgz ud-treebanks-v$RELEASE
cd ..

if [ "$ONLY_UPDATE_TREEBANKS" == "YES" ] ; then
    exit
fi

# Prepare the current content of the tools repository as a separate package, also without .git and .gitignore.
pushd tools ; git pull --no-edit ; popd
cd release-$RELEASE
mkdir ud-tools-v$RELEASE
cp -r ../tools/* ud-tools-v$RELEASE
rm -rf ud-tools-v$RELEASE/.git* ud-tools-v$RELEASE/not-to-release
tar czf ud-tools-v$RELEASE.tgz ud-tools-v$RELEASE
cd ..

# Prepare the current content of the docs repository as a separate package, also without .git and .gitignore.
# Note that this is archiving the MarkDown source code of the documentation. See below for archiving the corresponding HTML.
pushd docs ; git checkout pages-source ; git pull --no-edit ; popd
cd release-$RELEASE
mkdir -p ud-documentation-v$RELEASE/markdown-source
cp -r ../docs/* ud-documentation-v$RELEASE/markdown-source
rm -rf ud-documentation-v$RELEASE/markdown-source/.git* ud-documentation-v$RELEASE/markdown-source/not-to-release
cd ..

# The surface form of documentation (i.e. the web content visible to the reader) is automatically generated
# in a separate Github repository. WARNING! Many folders contain generated files AUX.html and aux.html
# (besides AUX_.html and aux_.html). These should not be included in the package because that might prevent
# people from unpacking it in MS Windows (although some unpacking programs, like 7zip, will be able to overcome
# this by simply renaming the file to _aux.html before unpacking it). Note furthermore that we currently cannot
# force Jekyll (the page generator) to make all hyperlinks relative in order for the pages to work well offline.
# Many hyperlinks will be broken when viewing the pages, and the user will have to open individual pages from
# the file manager instead. However, it may still be useful to provide the HTML rendering, especially because
# of the embedded tree visualizations.
###!!!git clone git@github.com:UniversalDependencies/universaldependencies.github.io.git
pushd universaldependencies.github.io ; git pull --no-edit ; popd
cd release-$RELEASE
mkdir -p ud-documentation-v$RELEASE/html
cp -r ../universaldependencies.github.io/* ud-documentation-v$RELEASE/html
rm -rf ud-documentation-v$RELEASE/html/.git* ud-documentation-v$RELEASE/html/not-to-release
rm -f ud-documentation-v$RELEASE/html/*/*/{AUX,aux}.html
tar czf ud-documentation-v$RELEASE.tgz ud-documentation-v$RELEASE
cd ..
