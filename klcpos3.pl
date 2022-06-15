#!/usr/bin/env perl
# Computes KLcpos3 (target, source).
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my $tgtdistfile = shift(@ARGV);
my $srcdistfile = shift(@ARGV);
open(TGT, $tgtdistfile) or die("Cannot read $tgtdistfile: $!");
while(<TGT>)
{
    s/\r?\n$//;
    my ($trigram, $count, $relcount) = split(/\t/, $_);
    $tgt{$trigram} = $count;
    $rtgt{$trigram} = $relcount;
    # Prepare add-1 smoothing for source distribution.
    $src{$trigram} = 1;
}
close(TGT);
open(SRC, $srcdistfile) ord die("Cannot read $srcdistfile: $!");
while(<SRC>)
{
    s/\r?\n$//;
    my ($trigram, $count, $relcount) = split(/\t/, $_);
    $src{$trigram} += $count;
    $srctotal += $src{$trigram};
}
close(SRC);
foreach my $trigram (keys(%src))
{
    $rsrc{$trigram} = $src{$trigram}/$srctotal;
}
# Compute KLcpos3(tgt, src).
foreach my $trigram (keys(%tgt))
{
    $klcpos3 += $rtgt{$trigram} * log($rtgt{$trigram}/$rsrc{$trigram});
}
print("KLcpos3 = $klcpos3\n");
