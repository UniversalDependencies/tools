#!/usr/bin/env perl
# Compares the two branches of Bosque.
# Copyright © 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

sub usage
{
    print STDERR ("Usage: perl tools/mergept.pl UD_Portuguese-Bosque/pt_bosque-ud-train.conllu UD_Portuguese/pt-ud-train.conllu > pt-ud-train.conllu\n");
}

my $alexfile = shift(@ARGV);
my $danfile = shift(@ARGV);
if(!defined($alexfile) || !defined($danfile))
{
    usage();
    die("Missing argument");
}
open(AF, $alexfile) or die("Cannot read $alexfile: $!");
open(DF, $danfile) or die("Cannot read $danfile: $!");

sub read_sentence
{
    my $handle = shift;
    my @sentence;
    while(<$handle>)
    {
        my $line = $_;
        push(@sentence, $line);
        last if($line =~ m/^\s*$/);
    }
    return @sentence;
}

my $n = 0;
while(1)
{
    my @as = read_sentence(AF);
    my @ds = read_sentence(DF);
    if(scalar(@as)==0 && scalar(@ds)!=0)
    {
        die("The first file has ended and the second one has not");
    }
    elsif(scalar(@as)!=0 && scalar(@ds)==0)
    {
        die("The second file has ended and the first one has not");
    }
    last if(scalar(@as)==0 || scalar(@ds)==0);
    $n++;
    my @at = grep {m/^\#\s*text\s*=\s*/} (@as);
    my @dt = grep {m/^\#\s*text\s*=\s*/} (@ds);
    my $at = $at[0];
    my $dt = $dt[0];
    $at =~ s/^\#\s*text\s*=\s*//;
    $dt =~ s/^\#\s*text\s*=\s*//;
    $at =~ s/\s+$//;
    $dt =~ s/\s+$//;
    if($at ne $dt)
    {
        print STDERR ("Alex: $at\n");
        print STDERR ("Dan:  $dt\n");
        print STDERR ("\n");
    }
    # The output will be based on Dan's version but certain approved parts will be taken from Alex's version.
    # Print Dan's text. Add the other sentence comments (including sent_id) from Alex.
    print("\# text = $dt\n");
    my @ac = grep {m/^\#/ && !m/^\#\s*text\s+/} (@as);
    foreach my $comment (@ac)
    {
        print($comment);
    }
    # Prepare words from Alex's file so we can look at their attributes. Ignore multi-word tokens, they do not match.
    my @aw = grep {m/^\d+\t/} (@as);
    # Take the nodes from Dan's file.
    my @dn = grep {!m/^\#/} (@ds);
    foreach my $line (@dn)
    {
        if($line =~ m/^\d+\t/)
        {
            my $aw = shift(@aw);
            my @af = split(/\t/, $aw);
            my @df = split(/\t/, $line);
            # The tokenization does not always match. Check that word forms match.
            # Do not perform the full longest-common-sequence algorithm. If there is an extra token, the rest of the sentence will not match.
            if($af[1] eq $df[1])
            {
                # Copy the XPOSTAG from Alex to Dan.
                $df[4] = $af[4];
            }
            $line = join("\t", @df);
        }
        print($line);
    }
}
print STDERR ("Total $n sentences in each file.\n");
