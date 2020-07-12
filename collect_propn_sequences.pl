#!/usr/bin/env perl
# Reads a CoNLL-U file and watches for sequences of words tagged PROPN. In certain
# treebanks, especially the UD treebanks donated by Google, multi-word named entities
# were all tagged PROPN, regardless of the fact that some words were not proper
# nouns and not even nouns. This approach does not comply with the UD guidelines
# and it should be corrected; however, the information that there is a multi-word
# named entity is interesting and we don't want to lose it, so we will keep it
# in the MISC field.
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my %ne;
my $current_ne = '';
my $mwtto = 0;
while(<>)
{
    s/\r?\n$//;
    if(m/^\d+-(\d+)\t/)
    {
        $mwtto = $1;
        my @f = split(/\t/, $_);
        if($f[3] eq 'PROPN')
        {
            $current_ne .= $f[1];
            unless(grep {m/^SpaceAfter=No$/} (split(/\|/, $f[9])))
            {
                $current_ne .= ' ';
            }
        }
        else
        {
            if($current_ne ne '')
            {
                $current_ne =~ s/\s+$//;
                $ne{$current_ne}++;
            }
            $current_ne = '';
        }
    }
    elsif(m/^(\d+)\t/ && $1 > $mwtto)
    {
        my @f = split(/\t/, $_);
        if($f[3] eq 'PROPN')
        {
            $current_ne .= $f[1];
            unless(grep {m/^SpaceAfter=No$/} (split(/\|/, $f[9])))
            {
                $current_ne .= ' ';
            }
        }
        else
        {
            if($current_ne ne '')
            {
                $current_ne =~ s/\s+$//;
                $ne{$current_ne}++;
            }
            $current_ne = '';
        }
    }
    elsif(m/^\s*$/)
    {
        if($current_ne ne '')
        {
            $current_ne =~ s/\s+$//;
            $ne{$current_ne}++;
        }
        $current_ne = '';
        $mwtto = 0;
    }
}
my @ne = sort {my $r = $ne{$b} <=> $ne{$a}; unless($r) {$r = $a cmp $b} $r} (keys(%ne));
foreach my $ne (@ne)
{
    print("$ne\t$ne{$ne}\n");
}
