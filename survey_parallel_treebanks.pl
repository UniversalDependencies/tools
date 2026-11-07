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
use Getopt::Long;
# We need to tell Perl where to find my UD and graph modules.
BEGIN
{
    use Cwd;
    my $path = $0;
    my $currentpath = getcwd();
    $currentpath =~ s/\r?\n$//;
    $libpath = $currentpath;
    if($path =~ m:/:)
    {
        $path =~ s:/[^/]*$:/:;
        chdir($path);
        $libpath = getcwd();
        chdir($currentpath);
    }
    $libpath =~ s/\r?\n$//;
    #print STDERR ("libpath=$libpath\n");
}
use lib $libpath;
use udlib;

sub usage
{
    print STDERR ("Usage: perl survey_parallel_treebanks.pl --datapath /net/projects/ud --tbklist udsubset.txt\n");
    print STDERR ("       --datapath ... path to the folder where all UD_* treebank repositories reside\n");
    print STDERR ("       --tbklist .... file with list of UD_* folders to consider (e.g. treebanks we are about to release)\n");
    print STDERR ("                      if tbklist is not present, all treebanks in datapath will be scanned\n");
}

my $datapath = '.';
my $tbklist;
GetOptions
(
    'datapath=s' => \$datapath, # UD_* folders will be sought in this folder
    'tbklist=s'  => \$tbklist   # path to file with treebank list; if defined, only treebanks on the list will be surveyed
);
# We need absolute path because we will be changing the current folder.
if($datapath =~ m/^\./)
{
    my $currentpath = getcwd();
    if($datapath eq '.')
    {
        $datapath = $currentpath;
    }
    else
    {
        $datapath = "$currentpath/$datapath";
    }
}
my %treebanks;
if(defined($tbklist))
{
    open(TBKLIST, $tbklist) or die("Cannot read treebank list from '$tbklist': $!");
    while(<TBKLIST>)
    {
        s/^\s+//;
        s/\s+$//;
        my @treebanks = split(/\s+/, $_);
        foreach my $t (@treebanks)
        {
            $t =~ s:/$::;
            $treebanks{$t}++;
        }
    }
    close(TBKLIST);
}

my @folders = udlib::list_ud_folders($datapath);
my $n = scalar(@folders);
print STDERR ("Found $n UD folders in '$datapath'.\n");
if(defined($tbklist))
{
    my $n = scalar(keys(%treebanks));
    print STDERR ("We will only scan those listed in $tbklist (the list contains $n treebanks but we have not checked yet which of them exist in the folder).\n");
}
else
{
    print STDERR ("Warning: We will scan them all, whether their data is valid or not!\n");
}
if($datapath eq '.')
{
    print STDERR ("Use the --datapath option to scan a different folder with UD treebanks.\n");
}
sleep(5);
my %collections;
foreach my $folder (@folders)
{
    # If we received the list of treebanks to be released, skip all other treebanks.
    if(defined($tbklist) && !exists($treebanks{$folder}))
    {
        next;
    }
    my $metadata = udlib::read_readme($folder, $datapath);
    next if($metadata->{Parallel} eq 'no' || $metadata->{Parallel} eq '');
    my @parallel = split(/\s+/, $metadata->{Parallel});
    foreach my $collection (@parallel)
    {
        $collections{$collection}{$folder}{existence}++;
        $collections{$collection}{$folder}{nsent} = 0 if(!defined($collections{$collection}{$folder}{nsent}));
    }
    # Read the data and count the parallel sentences.
    # We need more details than those provided by udlib::collect_statistics_about_ud_treebank().
    opendir(DIR, "$datapath/$folder") or die("Cannot read folder '$datapath/$folder': $!");
    my @files = grep {m/\.conllu$/} (readdir(DIR));
    closedir(DIR);
    foreach my $file (@files)
    {
        open(my $fh, "$datapath/$folder/$file") or die("Cannot read '$datapath/$folder/$file': $!");
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
