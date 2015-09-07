#!/usr/bin/env perl
# Reads a CoNLL 2006/2007 file, looks at the eighth column (DEPREL) and counts the values found there.
# Copyright © 2015 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

while(<>)
{
    # Skip comment lines (new in CoNLL-U).
    next if(m/^\#/);
    # Skip empty lines, they separate sentences.
    next if(m/^\s*$/);
    # Skip lines with fused tokens (they do not contain deprels; this is new in CoNLL-U).
    next if(m/^(\d+)-(\d+)\t/);
    # Remove the line-ending character(s).
    s/\r?\n$//;
    # Decompose the line into fields.
    my @fields = split(/\t/, $_);
    # Remember the occurrence of the value of the field we are interested in.
    $stat{$fields[7]}++;
}
# Print the statistics in descending order.
@keys = sort {$stat{$b} <=> $stat{$a}} (keys(%stat));
foreach my $key (@keys)
{
    print("$key\t$stat{$key}\n");
}
print("Found total of ", scalar(@keys), " distinct values.\n");
