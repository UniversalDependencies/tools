#!/usr/bin/env perl
# Normalizes lemmas in UD_Latin-Perseus. (The same has been done to UD_Czech-PDT and others.)
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

while(<>)
{
    if(m/^\d+\t/)
    {
        s/\r?\n$//;
        my @f = split(/\t/, $_);
        my $form = $f[1];
        my $lemma = $f[2];
        my @misc;
        unless($f[9] eq '_')
        {
            @misc = split(/\|/, $f[9]);
        }
        # Lemma of punctuation symbols should be the symbols themselves, as in most other treebanks.
        if($form =~ m/^\pP+$/ && $lemma =~ m/\PP/)
        {
            $f[2] = $form;
            @misc = grep {!m/^LId=/} (@misc);
            push(@misc, "LId=$lemma");
        }
        # Lemma should not contain a numerical suffix that disambiguates word senses.
        # Such disambiguation, if desired, should go to the LId attribute in MISC.
        elsif($form !~ m/\d/ && $lemma =~ m/(.*\D)-?\d+$/)
        {
            $f[2] = $1;
            @misc = grep {!m/^LId=/} (@misc);
            push(@misc, "LId=$lemma");
        }
        if(scalar(@misc) >= 1)
        {
            $f[9] = join('|', @misc);
        }
        else
        {
            $f[9] = '_';
        }
        $_ = join("\t", @f)."\n";
    }
    print;
}
