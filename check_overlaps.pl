#!/usr/bin/env perl
# Checks for possible overlaps between training and dev/test sentences.
# Takes a list of treebanks (UD repositories) and cross-checks all treebanks
# of the same language. Note that non-empty overlap does not automatically
# mean an error. There might be naturally recurring sentences, especially short
# ones.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my @treebanks = map {s:/$::; $_} (@ARGV);
my %languages;
foreach my $treebank (@treebanks)
{
    my $language = $treebank;
    $language =~ s/-.*//;
    $languages{$language}++;
}
my @languages = sort(keys(%languages));
foreach my $language (@languages)
{
    # Get all CoNLL-U files of all treebanks of the current language.
    my @ltreebanks = grep {m/^$language/} (@treebanks);
    my @files;
    foreach my $treebank (@ltreebanks)
    {
        opendir(DIR, $treebank) or die("Cannot read $treebank: $!");
        my @tfiles = map {"$treebank/$_"} (grep {m/-ud-(train|dev|test)\.conllu$/} (readdir(DIR)));
        closedir(DIR);
        push(@files, @tfiles);
    }
    # Test each pair of files where unnatural overlap is undesirable.
    for(my $i = 0; $i <= $#files; $i++)
    {
        my $ifile = $files[$i];
        my $itype = '';
        if($ifile =~ m/-ud-(train|dev|test)\.conllu$/)
        {
            $itype = $1;
        }
        for(my $j = $i+1; $j <= $#files; $j++)
        {
            my $jfile = $files[$j];
            my $jtype = '';
            if($jfile =~ m/-ud-(train|dev|test)\.conllu$/)
            {
                $jtype = $1;
            }
            unless($itype eq $jtype)
            {
                my $command = "overlap.py $ifile $jfile";
                print("$command\n");
                system($command);
            }
        }
    }
}
