#!/usr/bin/env perl
# Checks whether SpaceAfter=No does not occur at the end of a paragraph.
# If it finds such an error, it fixes the error in-place (unlike check-space-after-paragraph.pl, which only reports the error).
# Note that this script does not read STDIN. It requires one or more arguments = paths to CoNLL-U files.
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

if(scalar(@ARGV)==0)
{
    die("One or more paths to files needed. No arguments found");
}
my $tmpfile = '/tmp/'.$$;
while(my $filename = shift(@ARGV))
{
    my $ok = open(FILE, $filename);
    if($ok)
    {
        my @errors = ();
        my $iline = 0;
        my $ignore_until;
        my $spaceafternoline;
        my $sentid;
        my $spaceaftersentid;
        while(my $line = <FILE>)
        {
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
                    push(@errors, $spaceafternoline);
                    #print STDERR ("Line $iline: new paragraph or document was preceded by SpaceAfter=No on line $spaceafternoline (sentence $spaceaftersentid).\n");
                    $spaceafternoline = undef;
                    $spaceaftersentid = undef;
                }
            }
            elsif($line =~ m/^\#\s*sent_id\s*=\s*(\S+)/)
            {
                $sentid = $1;
            }
        }
        close(FILE);
        my $n = scalar(@errors);
        if($n > 0)
        {
            print STDERR ("$filename ... $n errors\n");
            open(IN, $filename) or die("Cannot read '$filename': $!");
            open(OUT, ">$tmpfile") or die("Cannot write '$tmpfile': $!");
            my $next_error = shift(@errors);
            $iline = 0;
            while(<IN>)
            {
                $iline++;
                if(defined($next_error) && $iline == $next_error)
                {
                    s/\r?\n$//;
                    my @f = split(/\t/);
                    my @misc = grep {$_ ne 'SpaceAfter=No'} (split(/\|/, $f[9]));
                    if(scalar(@misc)==0)
                    {
                        $f[9] = '_';
                    }
                    else
                    {
                        $f[9] = join('|', @misc);
                    }
                    $_ = join("\t", @f)."\n";
                    $next_error = shift(@errors);
                }
                print OUT;
            }
            close(IN);
            close(OUT);
            system("cp $filename $filename.bak");
            system("mv $tmpfile $filename");
        }
        else
        {
            print STDERR ("$filename ... no errors\n");
        }
    }
    else
    {
        print STDERR ("Cannot open '$filename' ($!), skipping.\n");
    }
}
