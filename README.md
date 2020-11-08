# UD Tools

[![alt text](https://avatars0.githubusercontent.com/u/7457237?s=200&v=4 "Universal Dependencies")](http://universaldependencies.org/)

This repository contains various scripts in Perl and Python that can be used as tools for Universal Dependencies.

## [validate.py](https://github.com/UniversalDependencies/tools/blob/master/validate.py)
Reads a CoNLL-U file and verifies that it complies with the UD specification. It must be run with the language code and there must exist corresponding lists of treebank-specific features and dependency relations in order to check that they are valid, too.

The script runs under Python 3 and needs the third-party module **regex**. If you do not have the **regex** module, install it using `pip install --user regex`.

NOTE: Depending on the configuration of your system, it is possible that both Python 2 and 3 are installed; then you may have to run `python3` instead of `python`, and `pip3` instead of `pip`.

```
cat la_proiel-ud-train.conllu | python validate.py --lang la --max-err=0
```


You can run `python validate.py --help` for a list of available options.

## [check_sentence_ids.pl](https://github.com/UniversalDependencies/tools/blob/master/check_sentence_ids.pl)


Reads CoNLL-U files from STDIN and verifies that every sentence has a unique id in the sent_id comment. All files of one treebank (repository) must be supplied at once in order to test treebank-wide id uniqueness.
```
cat *.conllu | perl check_sentence_ids.pl
```

## [normalize_unicode.pl](https://github.com/UniversalDependencies/tools/blob/master/normalize_unicode.pl)
Converts Unicode to the NFC normalized form. Can be applied to any UTF-8-encoded text file, including CoNLL-U. As a result, if there are character combinations that by definition must look the same, the same sequence of bytes will be used to represent the glyph, thus improving accuracy of models (as long as they are applied to normalized data too).

**Beware**: The output may slightly differ depending on your version of Perl because the Unicode standard evolves and newer Perl versions incorporate newer versions of Unicode data.
```
perl normalize_unicode.pl < input.conllu > normalized_output.conllu
```

## [conllu-stats.pl](https://github.com/UniversalDependencies/tools/blob/master/conllu-stats.pl)

Reads a CoNLL-U file, collects various statistics and prints them. This Perl script
should not be confused with conll-stats.py, an old Python 2 program that collects
just a few very basic statistics. The Perl script (conllu-stats.pl) is used to generate the stats.xml files in each data repository.
```
perl conllu-stats.pl *.conllu > stats.xml
```

## [mwtoken-stats.pl](https://github.com/UniversalDependencies/tools/blob/master/mwtoken-stats.pl)
Reads a CoNLL-U file, collects statistics of multi-word tokens and prints them.
```
cat *.conllu | perl mwtoken-stats.pl > mwtoken-stats.txt
```

## [enhanced_graph_properties.pl](https://github.com/UniversalDependencies/tools/blob/master/enhanced_graph_properties.pl)
Reads a CoNLL-U file, collects statistics about the enhanced graphs in the DEPS column and prints them. This script uses the modules Graph.pm and Node.pm that lie in the same folder. On UNIX-like systems it should be able to tell Perl where to find the modules even if the script is invoked from a remote folder. If that does not work, use `perl -I libfolder script` to invoke it. Also note that other third-party modules are needed that are not automatically included in the installation of Perl: Moose, MooseX::SemiAffordanceAccessor, List::MoreUtils. You may need to install these modules using the `cpan` tool (simply go to commandline and type `sudo cpan Moose`).
```
cat *.conllu | perl enhanced_graph_properties.pl > eud-stats.txt
```

## [enhanced_collapse_empty_nodes.pl](https://github.com/UniversalDependencies/tools/blob/master/enhanced_collapse_empty_nodes.pl)
Reads a CoNLL-U file, removes empty nodes and adjusts the enhanced graphs so
that a path traversing one or more empty nodes is contracted into a single edge: if there was a "conj" edge from node 27 to node 33.1, and a **nsubj** edge from node 33.1 to node 33, the resulting graph will have an edge from 27 to 33, labeled **conj>nsubj**

This script uses the modules Graph.pm and Node.pm that lie in the same folder.
On UNIX-like systems it should be able to tell Perl where to find the modules even if the script is invoked from a remote folder. If that does not work, use `perl -I libfolder script` to invoke it. Also note that other third-party modules are needed that are not automatically included in the installation of Perl: Moose, MooseX::SemiAffordanceAccessor, List::MoreUtils. You may need to install these modules using the `cpan` tool (simply go to commandline and type `sudo cpan Moose`).
```
perl enhanced_collapse_empty_nodes.pl enhanced.conllu > collapsed.conllu
```

## [overlap.py](https://github.com/UniversalDependencies/tools/blob/master/overlap.py)
Compares two CoNLL-U files and searches for sentences that occur in both (verbose duplicates of token sequences). Some treebanks, especially those where the original text had been acquired from the web, contained duplicate documents that
were found at different addresses and downloaded twice. This tool helps to find out whether one of the duplicates fell in the training data and the other in development or test. The output has to be verified manually, as some “duplicates”
are repetitions that occur naturally in the language (in particular short sentences such as “Thank you.”)

The script can also help to figure out whether training-dev-test data split has been changed between two releases so that a previously training sentence is now in test or vice versa. That is something we want to avoid.

## [find_duplicate_sentences.pl](https://github.com/UniversalDependencies/tools/blob/master/find_duplicate_sentences.pl) & [remove_duplicate_sentences.pl](https://github.com/UniversalDependencies/tools/blob/master/remove_duplicate_sentences.pl)
Similar to overlap.py but it works with the sentence-level attribute **text**. It remembers all sentences from STDIN or from input files whose names are given as arguments. The find script prints the duplicate sentences (ordered by length and number of occurrences) to STDOUT. The remove script works as a filter: it prints the CoNLL-U data from the input, except for the second and any subsequent occurrence of the duplicate sentences.

## [conllu_to_conllx.pl](https://github.com/UniversalDependencies/tools/blob/master/conllu_to_conllx.pl)
Converts a file in the CoNLL-U format to the old CoNLL-X format. Useful with old tools (e.g. parsers) that require CoNLL-X as their input. Usage:
```
perl conllu_to_conllx.pl < file.conllu > file.conll
```

## [restore_conllu_lines.pl](https://github.com/UniversalDependencies/tools/blob/master/restore_conllu_lines.pl)

Merges a CoNLL-X and a CoNLL-U file, taking only the CoNLL-U-specific lines from CoNLL-U. Can be used to merge the output of an old parser that only works with CoNLL-X with the original annotation that the parser could not read.
```
restore_conllu_lines.pl file-parsed.conll file.conllu
```

## [conllu_to_text.pl](https://github.com/UniversalDependencies/tools/blob/master/conllu_to_text.pl)

Converts a file in the CoNLL-U format to plain text, word-wrapped to lines of 80 characters (but the output line will be longer if there is a word that is longer than the limit). The script can use either the sentence-level text attribute, or the word forms plus the SpaceAfter=No MISC attribute to output detokenized text. It also observes the sentence-level newdoc and newpar attributes, and the NewPar=Yes MISC attribute, if they are present, and prints an empty line between paragraphs or documents.

Optionally, the script takes the language code as a parameter. Codes 'zh' and 'ja' will trigger a different word-wrapping algorithm that is more suitable for Chinese and Japanese.

**Usage**:
```
perl conllu_to_text.pl --lang zh < file.conllu > file.txt
```

## [conll_convert_tags_to_uposf.pl](https://github.com/UniversalDependencies/tools/blob/master/conll_convert_tags_to_uposf.pl)
This script takes the CoNLL columns CPOS, POS and FEAT and converts their combined values to the universal POS tag and features.

You need Perl. On Linux, you probably already have it; on Windows, you may have to download and install Strawberry Perl. You also need the Interset libraries. Once you have Perl, it is easy to get them via the following (call `cpan` instead of `cpanm` if you do not have cpanm).
```
cpanm Lingua::Interset
```
Then use the script like this:
```
perl conll_convert_tags_to_uposf.pl -f source_tagset < input.conll > output.conll
```
The source tagset is the identifier of the tagset used in your data and known to Interset. Typically it is the language code followed by two colons and **conll**, e.g. **sl::conll** for the Slovenian data of CoNLL 2006. See the [tagset conversion tables](http://universaldependencies.github.io/docs/tagset-conversion/index.html) for more tagset codes.

**IMPORTANT**:

The script assumes the CoNLL-X (2006 and 2007) file format. If your data is in another format (most notably CoNLL-U, but also e.g. CoNLL 2008/2009, which is not identical to 2006/2007), you have to modify the data or the script. Furthermore,
you have to know something about the tagset driver (-f source_tagset above) you are going to use. Some drivers do not expect to receive three values joined by TAB characters. Some expect two values and many expect just a single tag, perhaps the one you have in your POS column. These factors may also require you to adapt the script to your needs. You may want to consult the [documentation](https://metacpan.org/pod/Lingua::Interset). Go to Browse / Interset / Tagset, look up your language code and tagset name, then locate the list() function in the source code. That will give you an idea of what the input tags should look like (usually the driver is able to decode even some tags that are not on the list but have the same structure and feature values).

## [check_files.pl](https://github.com/UniversalDependencies/tools/blob/master/check_files.pl)
This script must be run in a folder where all the data repositories (UD_*) are stored as subfolders. It checks the contents of the data repositories for various issues that we want to solve before a new release of UD is published.

## [conllu_align_tokens.pl](https://github.com/UniversalDependencies/tools/blob/master/conllu_align_tokens.pl)
Compares tokenization and word segmentation of two CoNLL-U files. Assumes that no normalization was performed, that is, the sequence of non-whitespace characters is identical on both sides. Use case: We want to merge a gold-standard file, which has no lemmas, with lemmatization predicted by an external tool. But the tool also performed tokenization and we have no guarantee that it matches the gold-standard tokenization. Despite its name, the script now does exactly that, i.e., copies the system lemma to the gold-standard annotation if the tokens match, and prints the merged file to STDOUT. If something else than lemma shall be copied, the source code must be adjusted.
```
perl conllu_align_tokens.pl UD_Turkish-PUD/tr_pud-ud-test.conllu media/conll17-ud-test-2017-05-09/UFAL-UDPipe-1-2/2017-05-15-02-00-38/output/tr_pud.conllu
```