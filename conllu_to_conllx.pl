#!/usr/bin/env perl
# Converts a CoNLL-U file (Universal Dependencies) to the older CoNLL-X format.
# The conversion is by definition lossy. It is a lightweight converter: we do not check for validity of the CoNLL-U input!
# Copyright © 2015, 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
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
    # Discard lines with empty nodes from the enhanced representation.
    next if(m/^\d+\./);
    if(m/\t/)
    {
        s/\r?\n$//;
        my @fields = split(/\t/, $_);
        # CoNLL-U v2 (December 2016) allows spaces in FORM and LEMMA but older tools may not survive it.
        # Replace spaces by underscores.
        $fields[1] =~ s/ /_/g;
        $fields[2] =~ s/ /_/g;
        # CoNLL-X specification did not allow POSTAG to be empty if there was CPOSTAG, and some tools rely on it.
        # Also, some tools rely on POSTAG being a fine-grained version of CPOSTAG, i.e. CPOSTAG should be always
        # inferrable from POSTAG. This is not an explicit requirement in the format specification but we will
        # enforce it anyway.
        # Copy CPOSTAG to POSTAG if POSTAG is empty. Otherwise, prepend CPOSTAG to POSTAG.
        if($fields[4] eq '_')
        {
            $fields[4] = $fields[3];
        }
        else
        {
            $fields[4] = $fields[3].'_'.$fields[4];
        }
        # The last two columns ([8] and [9]) had different meaning in CoNLL-X.
        # In many cases it is probably harmless to keep their contents from CoNLL-U, but some tools may rely on their expectations about these columns,
        # especially in [8] they may require either '_' or a numeric value. Let's erase the contents of these columns to be on the safe side.
        $fields[8] = $fields[9] = '_';
        $_ = join("\t", @fields)."\n";
    }
    print;
}
