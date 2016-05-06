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
conllu_to_conllx.pl
==============================

Converts a file in the CoNLL-U format to the old CoNLL-X format. Useful with old tools (e.g. parsers) that require
CoNLL-X as their input. Usage:

  perl conllu_to_conllx.pl < file.conllu > file.conll



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

IMPORTANT:
The script assumes the CoNLL-X (2006 and 2007) file format. If your data is in another format (most notably CoNLL-U, but
also e.g. CoNLL 2008/2009, which is not identical to 2006/2007), you have to modify the data or the script. Furthermore,
you have to know something about the tagset driver (-f source_tagset above) you are going to use. Some drivers do not
expect to receive three values joined by TAB characters. Some expect two values and many expect just a single tag,
perhaps the one you have in your POS column. These factors may also require you to adapt the script to your needs. You
may want to consult the documentation at https://metacpan.org/pod/Lingua::Interset. Go to Browse / Interset / Tagset,
look up your language code and tagset name, then locate the list() function in the source code. That will give you an
idea of what the input tags should look like (usually the driver is able to decode even some tags that are not on the
list but have the same structure and feature values).



==============================
check_files.pl
==============================

This script must be run in a folder where all the data repositories (UD_*) are stored as subfolders. It checks the
contents of the data repositories for various issues that we want to solve before a new release of UD is published.
