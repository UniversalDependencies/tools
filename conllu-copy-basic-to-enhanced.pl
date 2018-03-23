#!/usr/bin/env perl
# Copies basic dependencies to enhanced dependencies.
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
        my @f = split(/\t/, $_);
        my $head = $f[6];
        my $deprel = $f[7];
        my $deps = $f[8];
        my @deps;
        if($deps ne '_')
        {
            @deps = split(/\|/, $deps);
        }
        my $newdep = "$head:$deprel";
        unless(grep {$_ eq $newdep} (@deps))
        {
            push(@deps, $newdep);
            @deps = sort(@deps);
            $deps = join('|', @deps);
            $f[8] = $deps;
            $_ = join("\t", @f);
        }
    }
    print;
}
