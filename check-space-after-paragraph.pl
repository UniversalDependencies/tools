#!/usr/bin/env perl
# Checks whether SpaceAfter=No does not occur at the end of a paragraph.
# Note that such errors cause malfunction of conllu_to_text.pl, which generates the new paragraph and ignores SpaceAfter=No.
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my $iline = 0;
my $ignore_until;
my $spaceafternoline;
my $sentid;
my $spaceaftersentid;
while(<>)
{
    my $line = $_;
    chomp($line);
    $iline++;
    # Remember SpaceAfter=No.
    if($line =~ m/^\d/)
    {
        my @f = split(/\t/, $line);
        # Multi-word tokens need a special treatment.
        if($f[0] =~ m/^(\d+)-(\d+)$/)
        {
            my $id0 = $1;
            my $id1 = $2;
            $ignore_until = $id1;
        }
        if($f[0] =~ m/^\d+$/ && defined($ignore_until) && $f[0] > $ignore_until)
        {
            $ignore_until = undef;
        }
        if($f[0] =~ m/^\d+-\d+$/ || !defined($ignore_until))
        {
            my @misc = split(/\|/, $f[9]);
            if(grep {$_ eq 'SpaceAfter=No'} (@misc))
            {
                $spaceafternoline = $iline;
                $spaceaftersentid = $sentid;
            }
            else
            {
                $spaceafternoline = undef;
                $spaceaftersentid = undef;
            }
        }
    }
    elsif($line =~ m/^\s*$/)
    {
        # Reset $ignore_until at the end of the sentence if we did not reset it earlier.
        $ignore_until = undef;
    }
    elsif($line =~ m/^\#\s*new(doc|par)(\s|$)/)
    {
        # It is possible that there is no space between two sentences.
        # But it is not possible between two paragraphs or documents.
        if(defined($spaceafternoline))
        {
            print STDERR ("Line $iline: new paragraph or document was preceded by SpaceAfter=No on line $spaceafternoline (sentence $spaceaftersentid).\n");
            $spaceafternoline = undef;
            $spaceaftersentid = undef;
        }
    }
    elsif($line =~ m/^\#\s*sent_id\s*=\s*(\S+)/)
    {
        $sentid = $1;
    }
}
