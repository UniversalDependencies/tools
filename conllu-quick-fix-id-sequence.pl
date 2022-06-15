#!/usr/bin/env perl
# Reads a CoNLL-U file and tries to fix errors in the node ID sequences; writes the fixed file to STDOUT.
# Usage: perl conllu-quick-fix-id-sequence.pl < input.conllu > fixed.conllu
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my @sentence = ();
my $isent = 0;
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
# Once a sentence has been read, processes it and prints it.
#------------------------------------------------------------------------------
sub process_sentence
{
    $isent++; # global counter
    my @sentence = @_;
    my $iword = 0;
    my $ok = 1;
    my %idmap; # old ID => new ID
    ###!!! We currently ignore the ranges of multi-word tokens, empty nodes, and the contents of the DEPS column!
    foreach my $line (@sentence)
    {
        # Lines that start with a number correspond to nodes (words).
        # The numbers must form a sequence with the increment of 1.
        if($line =~ m/^\d+\t/)
        {
            $iword++;
            my @f = split(/\t/, $line);
            $idmap{$f[0]} = $iword unless(exists($idmap{$f[0]}));
            if($f[0] != $iword)
            {
                $ok = 0;
            }
        }
    }
    # We need to act only if we encountered a wrong ID (out of place).
    unless($ok)
    {
        $iword = 0;
        foreach my $line (@sentence)
        {
            if($line =~ m/^\d+\t/)
            {
                my @f = split(/\t/, $line);
                # Fix the node ID. We cannot use the hash map here because the original ids might be duplicated.
                $iword++;
                $f[0] = $iword;
                # Fix the ID reference to the HEAD. We will use the hash map here. If there were duplicated IDs, the first of them will be the head.
                $f[6] = $idmap{$f[6]} if(exists($idmap{$f[6]}));
                $line = join("\t", @f);
            }
        }
    }
    # Print the fixed sentence.
    print(join('', @sentence));
}
