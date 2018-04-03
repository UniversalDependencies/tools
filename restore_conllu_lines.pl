#!/usr/bin/env perl
# Merges a CoNLL-X and a CoNLL-U file. CoNLL-X is an output from an old parser,
# CoNLL-U is the desired output format, which will be compared to the gold
# standard. All node lines will be copied from the CoNLL-X file, only CoNLL-U
# specific lines will be taken from the CoNLL-U file. These include sentence
# level comments, empty nodes and, most importantly, multi-word token lines.
# Copyright © 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# Usage: restore_conllu_lines.pl x.conll x.conllu > x-merged.conllu

my $xin = $ARGV[0];
my $uin = $ARGV[1];
open(XIN, $xin) or die("Cannot read $xin: $!");
open(UIN, $uin) or die("Cannot read $uin: $!");
while(<UIN>)
{
    if(m/^\#/ ||
       m/^\d+\./ ||
       m/^\d+-/)
    {
        print;
    }
    else # node line or empty line after a sentence
    {
        my $uline = $_;
        my $xline = <XIN>;
        print($xline);
    }
}
close(XIN);
close(UIN);
