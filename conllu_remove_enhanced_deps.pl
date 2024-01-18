#!/usr/bin/env perl
# Removes all enhanced dependencies from the DEPS column of a CoNLL-U file.
# Prints the result to STDOUT.
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

while(<>)
{
    if(m/^\d/)
    {
        my @f = split(/\t/, $_);
        $f[8] = '_';
        $_ = join("\t", @f);
    }
    print;
}
