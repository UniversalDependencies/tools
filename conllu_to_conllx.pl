#!/usr/bin/env perl
# Converts a CoNLL-U file (Universal Dependencies) to the older CoNLL-X format.
# The conversion is by definition lossy. It is a lightweight converter: we do not check for validity of the CoNLL-U input!
# Copyright © 2015 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

while(<>)
{
    # Discard sentence-level comment lines.
    next if(m/^\#/);
    # Discard lines of fused surface tokens. Syntactic words will be the node-level unit in the output file.
    next if(m/^\d+-\d+/);
    if(m/\t/)
    {
        s/\r?\n$//;
        my @fields = split(/\t/, $_);
        # Some tools (MaltParser?) may not expect POSTAG to be empty if we have non-empty CPOSTAG. Copy CPOSTAG to POSTAG if POSTAG is empty.
        $fields[4] = $fields[3] if($fields[4] eq '_');
        # The last two columns ([8] and [9]) had different meaning in CoNLL-X.
        # In many cases it is probably harmless to keep their contents from CoNLL-U, but some tools may rely on their expectations about these columns,
        # especially in [8] they may require either '_' or a numeric value. Let's erase the contents of these columns to be on the safe side.
        $fields[8] = $fields[9] = '_';
        $_ = join("\t", @fields)."\n";
    }
    print;
}
