#!/usr/bin/env perl
# Scans all UD treebanks for morphological features and values.
# Copyright © 2016-2018, 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
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
    print STDERR ("Usage: perl survey_features.pl --datapath /net/projects/ud --tbklist udsubset.txt --countby treebank|language > features.md\n");
    print STDERR ("       --datapath ... path to the folder where all UD_* treebank repositories reside\n");
    print STDERR ("       --tbklist .... file with list of UD_* folders to consider (e.g. treebanks we are about to release)\n");
    print STDERR ("                      if tbklist is not present, all treebanks in datapath will be scanned\n");
    print STDERR ("       --countby .... count occurrences separately for each treebank or for each language?\n");
    print STDERR ("The overview will be printed to STDOUT in MarkDown format.\n");
}

my $datapath = '.';
my $tbklist;
my $countby = 'treebank';
GetOptions
(
    'datapath=s' => \$datapath, # UD_* folders will be sought in this folder
    'tbklist=s'  => \$tbklist,  # path to file with treebank list; if defined, only treebanks on the list will be surveyed
    'countby=s'  => \$countby   # count items by treebank or by language?
);
if($countby =~ m/^t/i)
{
    $countby = 'treebank';
}
else
{
    $countby = 'language';
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

opendir(DIR, $datapath) or die("Cannot read the contents of '$datapath': $!");
my @folders = sort(grep {-d "$datapath/$_" && m/^UD_[A-Z]/} (readdir(DIR)));
closedir(DIR);
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
# We need a mapping from the English names of the languages (as they appear in folder names) to their ISO codes.
# There is now also the new list of languages in YAML in docs-automation; this one has also language families.
my $languages_from_yaml = udlib::get_language_hash("$libpath/../docs-automation/codes_and_flags.yaml");
my %langnames;
my %langcodes;
foreach my $language (keys(%{$languages_from_yaml}))
{
    # We need a mapping from language names in folder names (contain underscores instead of spaces) to language codes.
    # Language names in the YAML file may contain spaces (not underscores).
    my $usname = $language;
    $usname =~ s/ /_/g;
    $langcodes{$usname} = $languages_from_yaml->{$language}{lcode};
    $langnames{$languages_from_yaml->{$language}{lcode}} = $language;
}
# Look for features in the data.
my %hash; # $hash{$feature}{$value}{$treebank/$language} = $count
my %poshash; # $poshash{$upos}{$feature}{$value}{$treebank/$language} = $count
my %hittreebanks;
foreach my $folder (@folders)
{
    # If we received the list of treebanks to be released, skip all other treebanks.
    if(defined($tbklist) && !exists($treebanks{$folder}))
    {
        next;
    }
    # The name of the folder: 'UD_' + language name + optional treebank identifier.
    # Example: UD_Ancient_Greek-PROIEL
    my $language = '';
    my $treebank = '';
    my $langcode;
    my $key;
    if($folder =~ m/^UD_([A-Za-z_]+)(?:-([A-Za-z]+))?$/)
    {
        print STDERR ("$folder\n");
        $language = $1;
        $treebank = $2 if(defined($2));
        if(exists($langcodes{$language}))
        {
            $langcode = $langcodes{$language};
            $key = $langcode;
            if($countby eq 'treebank' && $treebank ne '')
            {
                $key .= '_'.lc($treebank);
            }
            my $nhits = 0;
            # Look for the other files in the repository.
            opendir(DIR, "$datapath/$folder") or die("Cannot read the contents of the folder '$datapath/$folder': $!");
            my @files = readdir(DIR);
            closedir(DIR);
            my @conllufiles = grep {-f "$datapath/$folder/$_" && m/\.conllu$/} (@files);
            foreach my $file (@conllufiles)
            {
                $nhits += read_conllu_file("$datapath/$folder/$file", \%hash, \%poshash, $key);
            }
            # Remember treebanks where we found something.
            if($nhits>0)
            {
                $hittreebanks{$key}++;
            }
        }
    }
}
print_markdown(\%hash);



#------------------------------------------------------------------------------
# Reads one CoNLL-U file and notes all features in the global hash. Returns the
# number of feature-value pair occurrences observed in this file.
#------------------------------------------------------------------------------
sub read_conllu_file
{
    my $path = shift;
    my $hash = shift;
    my $poshash = shift;
    my $key = shift;
    my $nhits = 0;
    open(FILE, $path) or die("Cannot read '$path': $!");
    while(<FILE>)
    {
        if(m/^\d+\t/)
        {
            chomp();
            my @fields = split(/\t/, $_);
            my $upos = $fields[3];
            my $features = $fields[5];
            unless($features eq '_')
            {
                my @features = split(/\|/, $features);
                foreach my $feature (@features)
                {
                    my ($f, $vv) = split(/=/, $feature);
                    # There may be several values delimited by commas.
                    my @values = split(/,/, $vv);
                    foreach my $v (@values)
                    {
                        $hash->{$f}{$v}{$key}++;
                        $poshash->{$upos}{$f}{$v}{$key}++;
                        $nhits++;
                    }
                }
            }
        }
    }
    close(FILE);
    return $nhits;
}



#------------------------------------------------------------------------------
# Prints an overview of features and their values as a MarkDown page.
#------------------------------------------------------------------------------
sub print_markdown
{
    my $hash = shift;
    my @features = sort(keys(%{$hash}));
    print <<EOF
---
layout: base
title:  'Features and Values'
udver: '2'
---

This is an automatically generated list of features and values (both universal and language-specific) that occur in the UD data.
EOF
    ;
    foreach my $f (@features)
    {
        my %ffolders;
        my @values = sort(keys(%{$hash->{$f}}));
        print("\#\# $f\n\n");
        print("[$f]()\n\n");
        foreach my $v (@values)
        {
            my @folders = sort(keys(%{$hash->{$f}{$v}}));
            foreach my $folder (@folders)
            {
                print("* $f=$v\t$folder\t$hash->{$f}{$v}{$folder}\n");
                $ffolders{$folder}++;
            }
        }
        print("\n");
    }
}
