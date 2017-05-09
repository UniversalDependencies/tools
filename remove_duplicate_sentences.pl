#!/usr/bin/env perl
# Removes duplicate sentences (text attribute), prints the rest to STDOUT.
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
# between training and test file. The sentences from the training file will not
# be printed but they will be remembered and used to check for duplicates when
# filtering the sentences from the normal input ("test data"). If we want to
# remove overlapping sentences from the training data, just swap training and
# test when calling this script.
my $train;
GetOptions
(
    'train=s' => \$train
);

my %h;
my @sentence;
if (defined($train))
{
    open(TRAIN, $train) or die("Cannot read $train: $!");
    while(<TRAIN>)
    {
        push(@sentence, $_);
        if(m/^\s*$/)
        {
            process_sentence(0, @sentence);
            @sentence = ();
        }
    }
    close(TRAIN);
}
while(<>)
{
    push(@sentence, $_);
    if(m/^\s*$/)
    {
        process_sentence(1, @sentence);
        @sentence = ();
    }
}



#------------------------------------------------------------------------------
# Processes a sentence once it is completely read from the input.
#------------------------------------------------------------------------------
sub process_sentence
{
    my $print = shift;
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
        if ($print)
        {
            foreach my $line (@s)
            {
                print($line);
            }
        }
    }
}
