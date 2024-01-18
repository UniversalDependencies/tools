#!/usr/bin/env perl
# Breaks cycles in a UD treebank. Otherwise CoNLL-U readers in Treex and Udapi
# would not read it. The script only fixes basic UD trees. It does not touch
# enhanced UD graphs, if present.
# Copyright © 2011, 2022 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use strict;
use warnings;
use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# Empty first element of @tokens corresponds to the artificial root node.
my @tokens = ([]);
# We need a second array to keep all lines including multiword tokens and empty nodes.
my @lines = ();
while(<>)
{
    # Skip comment lines.
    if(m/^\#/)
    {
        print;
        next;
    }
    # Remove the line break.
    s/\r?\n$//;
    # Empty line separates sentences.
    if(m/^\s*$/)
    {
        if(scalar(@lines)>0)
        {
            # $ord, $form, $lemma, $cpos, $pos, $feat, $head, $deprel, $phead, $pdeprel
            # Build the tree, watch for cycles.
            my @parents = map {$_->[6]} (@tokens);
            for(my $i = 1; $i<=$#parents; $i++)
            {
                # Start at the i-th node, go to root, watch for cycles.
                my @map;
                my $lastj;
                for(my $j = $i; $j!=0; $j = defined($parents[$j]) ? $parents[$j] : 0)
                {
                    # If we visited the j-th node before, there is a cycle.
                    if($map[$j])
                    {
                        # Save the information about the original parent in MISC.
                        save_in_misc($tokens[$lastj], $j);
                        # Break the cycle.
                        $tokens[$lastj][6] = 0;
                        $parents[$lastj] = 0;
                    }
                    else # no cycle so far
                    {
                        $map[$j] = 1;
                        $lastj = $j;
                    }
                }
            }
            # Write the corrected tree.
            foreach my $line (@lines)
            {
                if($line->[0] =~ m/^\d+$/)
                {
                    print(join("\t", @{$tokens[$line->[0]]}), "\n");
                }
                else
                {
                    print(join("\t", @{$line}), "\n");
                }
            }
            print("\n");
        }
        # Erase all tokens but keep the artificial root node at $tokens[0].
        @tokens = ([]);
        @lines = ();
    }
    else
    {
        my @token = split(/\t/, $_);
        my $n = scalar(@token);
        if($n!=10)
        {
            print STDERR ("WARNING! A CoNLL line (token) should have 10 fields but this one has $n:\n");
            print STDERR ("$_\n");
        }
        # Keep all non-comment lines in @lines.
        # Keep only basic nodes (but not MWT lines or empty nodes) in @tokens.
        push(@lines, \@token);
        if($token[0] =~ m/^\d+$/)
        {
            push(@tokens, \@token);
        }
    }
}



#------------------------------------------------------------------------------
# Saves information about the former cycle-forming parent in MISC.
#------------------------------------------------------------------------------
sub save_in_misc
{
    my $token = shift; # array reference
    my $j = shift;
    my @misc = $token->[9] eq '_' ? () : split(/\|/, $token->[9]);
    my @cycle = grep {m/^Cycle=/} (@misc);
    @misc = grep {!m/^Cycle=/} (@misc);
    if(scalar(@cycle) > 1)
    {
        print STDERR ("WARNING! MISC already contains multiple Cycle= attributes\n");
    }
    if(scalar(@cycle) > 0)
    {
        $cycle[-1] .= ":$j";
    }
    else
    {
        push(@cycle, "Cycle=$j");
    }
    push(@misc, @cycle);
    $token->[9] = join('|', @misc);
}
