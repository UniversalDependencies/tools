#!/usr/bin/env perl
# Looks for duplicate sentences within CoNLL-U input. Compares the text attribute.
# Copyright © 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;

# An extra file can be designated as "training" data. This is useful if we are
# not concerned about duplicates within one file but rather about overlap
# between training and test file. If train is given, only sentences that occur
# in it and outside of it will be reported.
my $train;
GetOptions
(
    'train=s' => \$train
);

my %h;
if (defined($train))
{
    open(TRAIN, $train) or die("Cannot read $train: $!");
    while(<TRAIN>)
    {
        s/\r?\n$//;
        if(m/^\#\s*text\s*=\s*(.+)/)
        {
            my $text = $1;
            $text =~ s/\s+$//;
            # Count only one occurrence of every sentence in the training data. No intra-train duplicates are counted!
            $h{$text} = 1;
        }
    }
    close(TRAIN);
}
while(<>)
{
    s/\r?\n$//;
    if(m/^\#\s*text\s*=\s*(.+)/)
    {
        my $text = $1;
        $text =~ s/\s+$//;
        if (defined($train))
        {
            $h{$text}++ if (exists($h{$text}));
        }
        else
        {
            $h{$text}++;
        }
    }
}
my @duplicates = sort {my $r = length($b)<=>length($a); unless($r) {$r = $h{$b}<=>$h{$a}} $r;} (grep {$h{$_}>1} (keys(%h)));
foreach my $d (@duplicates)
{
    printf("%d × %s\n", $h{$d}, $d);
}
