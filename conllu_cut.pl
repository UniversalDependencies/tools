#!/usr/bin/env perl
# Takes a CoNLL-U file, cuts a section out of it, and prints the section.
# The section is identified by the id of the first and the last sentence.
# Copyright © 2022 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;

sub usage
{
    print STDERR ("Usage: perl conllu_cut.pl --first sent350 --last sent367 < whole.conllu > section.conllu\n");
    print STDERR ("       where sent350 and sent367 are sent_ids of the first and the last sentence included in the output\n");
    print STDERR ("       if --first is omitted, section starts at the beginning of the input file\n");
    print STDERR ("       if --last is omitted, section ends at the end of the input file\n");
}

my $firstsid;
my $lastsid;
GetOptions
(
    'first=s' => \$firstsid,
    'last=s'  => \$lastsid
);
if(!defined($firstsid) && !defined($lastsid))
{
    print STDERR ("WARNING: Neither the first nor the last sentence specified; the entire input will be passed through.\n");
}

my $inside = !defined($firstsid);
my @sentence = ();
while(<>)
{
    s/\r?\n$//;
    push(@sentence, $_);
    if(m/^\s*$/)
    {
        process_sentence(@sentence);
        @sentence = ();
    }
}
# If we encountered the end of the section, we exited the script in process_sentence().
# Being here means that we either want the section to reach the end of the input,
# or we failed to find the beginning of the section.
if(!$inside)
{
    print STDERR ("WARNING: The first sentence of the section, '$firstsid', was not found.\n");
}
elsif(defined($lastid))
{
    print STDERR ("WARNING: The last sentence of the section, '$lastsid', was not found.\n");
}

sub process_sentence()
{
    my @sentence = @_;
    # Get the sentence id.
    my $sid;
    foreach my $line (@sentence)
    {
        if($line =~ m/^\#\s*sent_id\s*=\s*(\S+)$/)
        {
            $sid = $1;
            last;
        }
    }
    if(!defined($sid))
    {
        print STDERR ("WARNING: Sentence has no sent_id\n");
        $sid = '';
    }
    if(!$inside && $sid eq $firstsid)
    {
        $inside = 1;
    }
    if($inside)
    {
        print(join("\n", @sentence), "\n");
        if(defined($lastsid) && $sid eq $lastsid)
        {
            # No need to read the rest of the input.
            exit(0);
        }
    }
}
