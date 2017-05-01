#!/usr/bin/env perl
# Removes duplicate sentences (text attribute), prints the rest to STDOUT.
# Copyright © 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my %h;
my @sentence;
while(<>)
{
    push(@sentence, $_);
    if(m/^\s*$/)
    {
        process_sentence(@sentence);
        @sentence = ();
    }
}



#------------------------------------------------------------------------------
# Processes a sentence once it is completely read from the input.
#------------------------------------------------------------------------------
sub process_sentence
{
    my @s = @_;
    # Get the sentence text.
    my $text;
    foreach my $line (@s)
    {
        if($line =~ m/^\#\s*text\s*=\s*(.+)/)
        {
            $text = $1;
            $text =~ s/\s+$//;
            last;
        }
    }
    if(!defined($text))
    {
        print STDERR ("WARNING: Sentence attribute text not found.\n");
    }
    # Only proceed if we have not seen this sentence before.
    unless(exists($h{$text}))
    {
        $h{$text}++;
        foreach my $line (@s)
        {
            print($line);
        }
    }
}
