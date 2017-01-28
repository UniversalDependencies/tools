#!/usr/bin/env perl
# Collects statistics about multi-word tokens in a CoNLL-U file.
# Copyright © 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

while(<>)
{
    if(m/^(\d+)-(\d+)\t(.+?)\t/)
    {
        $current_from = $1;
        $current_to = $2;
        $current_mwt = lc($3);
    }
    elsif(m/^(\d+)\t(.+?)\t(.+?)\t(.+?)\t/)
    {
        $id = $1;
        $form = lc($2);
        $lemma = $3;
        $upos = $4;
        if(defined($current_from))
        {
            # Merge verb+clitic combinations in Romance languages.
            if($current_to-$current_from == 1 && $id == $current_from && $upos =~ m/^(VERB|AUX)$/ && $current_mwt =~ s/^$form/VERB/)
            {
                $form = 'VERB';
            }
            push(@current_words, $form);
            if($id == $current_to)
            {
                $hash{$current_mwt}{join(' ', @current_words)}++;
                $current_from = $current_to = $current_mwt = undef;
                @current_words = ();
            }
        }
    }
}
foreach my $mwt (sort(keys(%hash)))
{
    foreach my $sequence (sort(keys(%{$hash{$mwt}})))
    {
        print("$mwt\t$sequence\t$hash{$mwt}{$sequence}\n");
    }
}
