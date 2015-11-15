This repository contains various scripts in Perl and Python that can be used as tools for Universal Dependencies.



==============================
validate.py
==============================

Reads a CoNLL-U file and verifies that it complies with the UD specification. It must be run with the language /
treebank code and there must exist corresponding lists of treebank-specific features and dependency relations in order
to check that they are valid, too.

  cat la_proiel-ud-train.conllu | validate.py --lang la_proiel



==============================
conllu-stats.py
conllu-stats.pl
==============================

Reads a CoNLL-U file, collects various statistics and prints them. These two scripts, one in Python and the other in
Perl, are independent of each other. The statistics they collect overlap but are not the same. The Perl script
(conllu-stats.pl) was used to generate the stats.xml files in each data repository.



==============================
overlap.py
==============================

Compares two CoNLL-U files and searches for sentences that occur in both (verbose duplicates of token sequences). Some
treebanks, especially those where the original text had been acquired from the web, contained duplicate documents that
were found at different addresses and downloaded twice. This tool helps to find out whether one of the duplicates fell
in the training data and the other in development or test. The output has to be verified manually, as some “duplicates”
are repetitions that occur naturally in the language (in particular short sentences such as “Thank you.”)

The script can also help to figure out whether training-dev-test data split has been changed between two releases so
that a previously training sentence is now in test or vice versa. That is something we want to avoid.



==============================
conll_convert_tags_to_uposf.pl
==============================

This script takes the CoNLL columns CPOS, POS and FEAT and converts their combined values to the universal POS tag and
features.

You need Perl. On Linux, you probably already have it; on Windows, you may have to download and install Strawberry Perl.
You also need the Interset libraries. Once you have Perl, it is easy to get them via the following (call "cpan" instead
of "cpanm" if you do not have cpanm).

  cpanm Lingua::Interset

Then use the script like this:

  perl conll_convert_tags_to_uposf.pl -f source_tagset < input.conll > output.conll

The source tagset is the identifier of the tagset used in your data and known to Interset. Typically it is the language
code followed by two colons and "conll", e.g. "sl::conll" for the Slovenian data of CoNLL 2006. See the tagset conversion
tables at http://universaldependencies.github.io/docs/tagset-conversion/index.html for more tagset codes.

It assumes the CoNLL-X (2006 and 2007) file format. If your data is in another format (including CoNLL 2008/2009, which
is not identical to 2006/2007), you have to modify the data or the script.



==============================
check_files.pl
==============================

This script must be run in a folder where all the data repositories (UD_*) are stored as subfolders. It checks the
contents of the data repositories for various issues that we want to solve before a new release of UD is published.
