#!/usr/bin/env perl
# Reads a CoNLL-U file and splits it to ten parts with approximately the same
# number of tokens.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# We will read the file twice: first count the tokens, then create the parts.
# Therefore we do not want to read from STDIN. We require a filename argument.
my $infile = shift(@ARGV);
if(!defined($infile))
{
    die("Usage: conllu-tenfold.pl inputfile.conllu");
}
my $nw = 0;
my $ns = 0;
open(IN, $infile) or die("Cannot read $infile: $!");
while(<IN>)
{
    if(m/^\d+\t/)
    {
        $nw++;
    }
    elsif(m/^\s*$/)
    {
        $ns++;
    }
}
close(IN);
if($ns<10)
{
    die("Cannot create 10 folds when there are only $ns sentences.");
    ###!!! Even if there are more sentences it is not guaranteed that we will succeed.
    ###!!! If there are 10 sentences, sentences 1-9 have 1 token each, and sentence 10 has 91 tokens, we will consume all sentences for the first part of 10+ tokens.
}
my $np = sprintf("%d", $nw/10+0.5);
print STDERR ("Found $ns sentences and $nw words. Will try to create 10 files with approximately $np words each.\n");
$nw = 0;
$ns = 0;
my $ip = 1;
my $nwp = 0;
my $nsp = 0;
open(IN, $infile) or die("Cannot read $infile: $!");
open(OUT, '>01.conllu') or die("Cannot write 01.conllu: $!");
while(<IN>)
{
    print OUT;
    if(m/^\d+\t/)
    {
        $nw++;
        $nwp++;
    }
    # We can switch to another output file at sentence boundary.
    elsif(m/^\s*$/)
    {
        $ns++;
        $nsp++;
        if($ip < 10 && $nw >= $ip * $np)
        {
            close(OUT);
            print STDERR ("Part $ip: $nsp sentences, $nwp words.\n");
            $ip++;
            my $filename = sprintf("%02d.conllu", $ip);
            open(OUT, ">$filename") or die("Cannot write $filename: $!");
            $nwp = 0;
            $nsp = 0;
        }
    }
}
close(OUT);
close(IN);
print STDERR ("Part $ip: $nsp sentences, $nwp words.\n");
# The training data for each part is the concatenation of the other parts.
for(my $i = 1; $i <= 10; $i++)
{
    my @files = map {sprintf("%02d.conllu", $_)} (grep {$_ != $i} (1..10));
    my $command = sprintf("cat %s > train%02d.conllu", join(' ', @files), $i);
    print STDERR ("$command\n");
    system($command);
}
# for i in 01 02 03 04 05 06 07 08 09 10 ; do udpipe --train --tokenizer=none --tagger=none model$i.udpipe train$i.conllu ; done
# for i in 01 02 03 04 05 06 07 08 09 10 ; do udpipe --accuracy --parse model$i.udpipe $i.conllu ; done
