#!/bin/bash
# Run this script in the folder where all UD treebank repositories exist as
# subfolders. In addition, a subfolder named master-eval-logs is expected,
# where verbose outputs from evaluate_treebank.pl are stored. Filename
# convention: UD_Urdu.eval.log. The script will go to each repository's master
# branch, copy the eval log there (and name it just eval.log), then push it and
# switch back to the dev branch.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

for i in master-eval-logs/UD_*.eval.log ; do
    treebank=`basename $i .eval.log`
    echo ============================================================
    pwd
    echo $treebank
    if [ -d $treebank ] ; then
        cd $treebank
        git checkout master
        git pull --no-edit
        cp ../$i ./eval.log
        git add eval.log
        git commit -m 'Evaluation report for UD 2.1.'
        git push
        git checkout dev
        cd ..
    fi
done
