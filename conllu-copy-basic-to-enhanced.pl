#!/usr/bin/env perl
# Copies basic dependencies to enhanced dependencies. If there are already
# enhanced dependencies, the basic ones are added to them, unless it is
# explicitly required that the previous enhanced graph is removed first.
# Copyright © 2018, 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
my $replace = 0;
GetOptions
(
    'replace' => \$replace
);

while(<>)
{
    if(m/^\d+\t/)
    {
        my @f = split(/\t/, $_);
        my $head = $f[6];
        my $deprel = $f[7];
        my $deps = $f[8];
        my @deps;
        if($deps ne '_' && !$replace)
        {
            @deps = split(/\|/, $deps);
        }
        my $newdep = "$head:$deprel";
        unless(grep {$_ eq $newdep} (@deps))
        {
            push(@deps, $newdep);
            my @deps2 = map {my ($h, $d); if(m/^(\d+):(.+)$/) {$h=$1; $d=$2} else {$h=$_; $d=''} [$h, $d]} (@deps);
            @deps2 = sort {my $r = $a->[0] <=> $b->[0]; unless($r) {$r = $a->[1] cmp $b->[1]} $r} (@deps2);
            @deps = map {join(':', @{$_})} (@deps2);
            $deps = join('|', @deps);
            $f[8] = $deps;
            $_ = join("\t", @f);
        }
    }
    print;
}
