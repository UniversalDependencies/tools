#!/usr/bin/env perl
# Looks for duplicate sentences within CoNLL-U input. Compares the text attribute.
# Copyright © 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my %h;
while(<>)
{
    s/\r?\n$//;
    if(m/^\#\s*text\s*=\s*(.+)/)
    {
        my $text = $1;
        $text =~ s/\s+$//;
        $h{$text}++;
    }
}
my @duplicates = sort {my $r = length($b)<=>length($a); unless($r) {$r = $h{$b}<=>$h{$a}} $r;} (grep {$h{$_}>1} (keys(%h)));
foreach my $d (@duplicates)
{
    printf("%d × %s\n", $h{$d}, $d);
}
