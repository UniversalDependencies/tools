#!/usr/bin/env perl
# Merges a CoNLL-X and a CoNLL-U file. CoNLL-X is an output from an old parser,
# CoNLL-U is the desired output format, which will be compared to the gold
# standard. All node lines will be copied from the CoNLL-X file, except for the
# FORM field, which will be taken from the CoNLL-U file, and any CoNLL-U
# specific lines will also be taken from the CoNLL-U file. These include sentence
# level comments, empty nodes and, most importantly, multi-word token lines.
# Copyright © 2017, 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
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
        # If the original CoNLL-U file contains a word with spaces, the spaces have been replaced by underscores
        # in CoNLL-X because spaces are not allowed there. Furthermore, if the CoNLL-X parser performed any
        # token normalization in the FORM field, the resulting file would now be invalid because the FORM would
        # not match the value of the sentence text comment. Therefore we take the FORM (but not the LEMMA) from
        # the original file (we do it with multi-word tokens anyway).
        if($xline =~ m/^\d+\t/)
        {
            my @xf = split(/\t/, $xline);
            my @uf = split(/\t/, $uline);
            $xf[1] = $uf[1];
            $xline = join("\t", @xf);
        }
        print($xline);
    }
}
close(XIN);
close(UIN);
