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
my $mwt_form = '';
my $mwt_no_space_after = 0;
my $mwt_is_propn;
while(<>)
{
    s/\r?\n$//;
    if(m/^\d+-(\d+)\t/)
    {
        $mwtto = $1;
        my @f = split(/\t/, $_);
        $mwt_form = $f[1];
        $mwt_no_space_after = scalar(grep {m/^SpaceAfter=No$/} (split(/\|/, $f[9])));
        $mwt_is_propn = 1; # any non-PROPN word within the MWT will clear this flag
    }
    elsif(m/^(\d+)\t/)
    {
        my @f = split(/\t/, $_);
        if($mwtto > 0 && $f[0] <= $mwtto)
        {
            # We are in a non-final word of a multi-word token and it is not a PROPN.
            # If the buffer contains a named entity, it will not include any part of
            # the MWT, even if its initial words were PROPN.
            if($f[3] ne 'PROPN')
            {
                if($current_ne ne '')
                {
                    $current_ne =~ s/\s+$//;
                    $ne{$current_ne}++;
                }
                $current_ne = '';
                $mwt_is_propn = 0;
            }
            if($f[0] == $mwtto)
            {
                if($mwt_is_propn)
                {
                    $current_ne .= $mwt_form;
                    unless($mwt_no_space_after)
                    {
                        $current_ne .= ' ';
                    }
                }
                $mwtto = 0;
                $mwt_form = '';
                $mwt_no_space_after = 0;
                $mwt_is_propn = undef;
            }
        }
        # Normal word/token that is not part of a multi-word token.
        else
        {
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
        $mwt_form = '';
        $mwt_no_space_after = 0;
        $mwt_is_propn = undef;
    }
}
my @ne = sort {my $r = $ne{$b} <=> $ne{$a}; unless($r) {$r = $a cmp $b} $r} (keys(%ne));
foreach my $ne (@ne)
{
    print("$ne\t$ne{$ne}\n");
}
