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
