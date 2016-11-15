#!/bin/bash
# Prepares a UD release.
# Copyright © 2016 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

RELEASE=1.4

echo WARNING! This script currently does not detect repositories that contain data but their README says they should not be released yet!

# Create the release folder, copy there the repositories that contain .conllu data (skip empty repositories!)
mkdir release-$RELEASE
cd release-$RELEASE
mkdir ud-treebanks-v$RELEASE
cd ud-treebanks-v$RELEASE
for i in ../../UD_* ; do if [ -f $i/*-ud-train.conllu ] ; then echo $i ; cp -r $i . ; fi ; done
# The training data in UD_Czech is split to four files because it is too large for Github.
# However, it can be one file in our release, so join the files again in the release copy.
cp -r ../../UD_Czech .
cat UD_Czech/cs-ud-train-*.conllu > UD_Czech/cs-ud-train.conllu
rm UD_Czech/cs-ud-train-*.conllu
# Erase files that should not be released (.gitignore, .git, not-to-release).
rm -rf UD_*/.git* UD_*/not-to-release
cd ..
tar czf ud-treebanks-v$RELEASE.tgz ud-treebanks-v$RELEASE
cd ..

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
