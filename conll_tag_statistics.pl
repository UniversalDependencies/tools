#!/usr/bin/env perl
# Reads a CoNLL 2006/2007 file, looks at the fourth column (CPOS) and counts the values found there.
# Copyright © 2013, 2015 Dan Zeman <zeman@ufal.mff.cuni.cz>
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
    $stat{$fields[3]}++;
    # We can also print example lemmas that had the tag.
    $examples{$fields[3]}{$fields[2]}++;
}
# Print the statistics in descending order.
@keys = sort {$stat{$b} <=> $stat{$a}} (keys(%stat));
foreach my $key (@keys)
{
    my @examples = sort
    {
        my $result = $examples{$key}{$b} <=> $examples{$key}{$a};
        unless($result)
        {
            $result = $a cmp $b;
        }
        $result
    }
    (keys(%{$examples{$key}}));
    splice(@examples, 10);
    #print("$key\t$stat{$key}\n");
    print('    <tag name="'.$key.'">'.$stat{$key}.'</tag><!-- ', join(', ', @examples), " -->\n");
}
print("Found total of ", scalar(@keys), " distinct values.\n");
