#!/usr/bin/env perl
# Computes statistics for Alessio. Expects CoNLL-U input.
# Copyright © 2019 Dan Zeman <zeman@ufal.mff.cuni.cz>
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
        my @f = split(/\t/, $_);
        unless($f[6]==0)
        {
            my $deplength = abs($f[6]-$f[0]);
            $total_deplength += $deplength;
            $n_nonroot_deps++;
        }
        $total{$f[7]}++;
        $rtl{$f[7]}++ if($f[6] > $f[0]);
    }
}
my $average_deplength = $total_deplength / $n_nonroot_deps;
print("Average non-root dependency length = $average_deplength\n");
foreach my $deprel (sort(keys(%total)))
{
    $rtl{$deprel} = 0 if(!defined($rtl{$deprel}));
    my $percent = $rtl{$deprel} / $total{$deprel} * 100;
    print("$deprel\ttotal $total{$deprel}\tright-to-left $rtl{$deprel}, i.e.,\t$percent \%\n");
}
