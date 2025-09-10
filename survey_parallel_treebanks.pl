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
    my $record = udlib::get_ud_files_and_codes($folder, $udpath);
    my $stats = udlib::collect_statistics_about_ud_treebank("$udpath/$folder", $record->{ltcode});
    @parallel = sort(keys(%{$stats->{nparallel}}));
    foreach my $collection (@parallel)
    {
        $collections{$collection}{$folder}{nsent} += $stats->{nparallel}{$collection};
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
        print("\t$treebank ($collections{$collection}{$treebank}{nsent} sentences)\n");
    }
}
