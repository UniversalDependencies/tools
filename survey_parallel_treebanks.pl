#!/usr/bin/env perl
# Surveys all UD treebanks in a given folder and checks their README files to
# see if they are part of a parallel treebank collection. Reports the findings
# to STDOUT.
# Copyright © 2025 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use udlib;

my $udpath = '.'; ###!!! to be customized later
my @folders = udlib::list_ud_folders($udpath);
my %collections;
foreach my $folder (@folders)
{
    my $metadata = udlib::read_readme($folder, $udpath);
    next if($metadata->{Parallel} eq 'no' || $metadata->{Parallel} eq '');
    my @parallel = split(/\s+/, $metadata->{Parallel});
    foreach my $collection (@parallel)
    {
        $collections{$collection}{$folder}{existence}++;
        $collections{$collection}{$folder}{nsent} = 0 if(!defined($collections{$collection}{$folder}{nsent}));
    }
    # Read the data and count the parallel sentences.
    # We need more details than those provided by udlib::collect_statistics_about_ud_treebank().
    opendir(DIR, "$udpath/$folder") or die("Cannot read folder '$udpath/$folder': $!");
    my @files = grep {m/\.conllu$/} (readdir(DIR));
    closedir(DIR);
    foreach my $file (@files)
    {
        open(my $fh, "$udpath/$folder/$file") or die("Cannot read '$udpath/$folder/$file': $!");
        while(<$fh>)
        {
            chomp;
            if(m/^\#\s*parallel_id\s*=\s*([a-z]+)\/([-0-9a-z]+)(?:\/(?:alt([0-9]+))?(?:part([0-9]+))?)?/)
            {
                my $colid = $1;
                my $sntid = $2;
                my $alt = $3; # undef or positive integer
                my $part = $4; # undef or positive integer
                $collections{$colid}{$folder}{sentences}{$sntid}++;
                $collections{$colid}{$folder}{nsent}++; # number of sentences including alternative and partial translations
            }
        }
        close($fh);
    }
}
my @collections = sort(keys(%collections));
print("Found the following parallel treebank collections:\n");
foreach my $collection (@collections)
{
    my @treebanks = sort(keys(%{$collections{$collection}}));
    my $n = scalar(@treebanks);
    print("$collection ($n treebanks)\n");
    foreach my $treebank (@treebanks)
    {
        my $nsent_with_altpart = $collections{$collection}{$treebank}{nsent};
        my $nsent_core = scalar(keys(%{$collections{$collection}{$treebank}{sentences}}));
        my $naltpart_extra = $nsent_with_altpart-$nsent_core;
        print("\t$treebank ($nsent_core sentences");
        if($naltpart_extra)
        {
            print(" with $naltpart_extra additional alternative or partial translations");
        }
        print(")\n");
    }
}
