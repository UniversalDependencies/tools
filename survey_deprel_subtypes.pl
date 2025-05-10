#!/usr/bin/env perl
# Scans all UD treebanks for language-specific subtypes of dependency relations.
# Copyright © 2016-2018, 2020-2021 Dan Zeman <zeman@ufal.mff.cuni.cz>
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
    $libpath = $currentpath;
    $path =~ s:\\:/:g;
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
    print STDERR ("Usage: perl survey_deprel_subtypes.pl --datapath /net/projects/ud --tbklist udsubset.txt --countby language|treebank > relations.md\n");
    print STDERR ("       --datapath ... path to the folder where all UD_* treebank repositories reside\n");
    print STDERR ("       --tbklist .... file with list of UD_* folders to consider (e.g. treebanks we are about to release)\n");
    print STDERR ("                      if tbklist is not present, all treebanks in datapath will be scanned\n");
    print STDERR ("       --countby .... count occurrences separately for each language (default) or for each treebank?\n");
    print STDERR ("       --help ....... print usage and exit\n");
    print STDERR ("The overview will be printed to STDOUT.\n");
}

my $datapath = '.';
my $tbklist;
my $countby = 'language'; # or treebank
my $help = 0;
GetOptions
(
    'datapath=s' => \$datapath, # UD_* folders will be sought in this folder
    'tbklist=s'  => \$tbklist,  # path to file with treebank list; if defined, only treebanks on the list will be surveyed
    'countby=s'  => \$countby,  # count items by treebank or by language?
    'help'       => \$help
);
if($help)
{
    usage();
    exit 0;
}
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
# Look for deprels in the data.
my %hash;
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
            if($countby eq 'treebank' && $treebank ne '')
            {
                $key = $langcode.'_'.lc($treebank);
            }
            else
            {
                # In the MarkDown output, we want full language names rather than just codes.
                $key = $language;
                $key =~ s/_/ /g;
            }
            # Look for CoNLL-U files in the repository.
            opendir(DIR, "$datapath/$folder") or die("Cannot read the contents of the folder '$datapath/$folder': $!");
            my @files = readdir(DIR);
            closedir(DIR);
            my @conllufiles = grep {-f "$datapath/$folder/$_" && m/\.conllu$/} (@files);
            foreach my $file (@conllufiles)
            {
                read_conllu_file("$datapath/$folder/$file", \%hash, $key);
            }
        }
    }
}
print_markdown(\%hash);



#------------------------------------------------------------------------------
# Reads one CoNLL-U file and notes all relations in the global hash. Returns
# the number of relation occurrences observed in this file.
# We currently do not look for additional relation types in the DEPS column.
#------------------------------------------------------------------------------
sub read_conllu_file
{
    my $path = shift;
    my $hash = shift;
    my $key = shift;
    my $nhits = 0;
    open(FILE, $path) or die("Cannot read '$path': $!");
    while(<FILE>)
    {
        if(m/^\d+\t/)
        {
            chomp();
            my @fields = split(/\t/, $_);
            my $deprel = $fields[7];
            $hash{$deprel}{$key}++;
            $nhits++;
        }
    }
    close(FILE);
    return $nhits;
}



#------------------------------------------------------------------------------
# Prints an overview of relations and their subtypes as a MarkDown page.
#------------------------------------------------------------------------------
sub print_markdown
{
    my $hash = shift;
    my @features = sort(keys(%{$hash}));
    print <<EOF
---
layout: base
title:  'Relation Subtypes'
udver: '2'
---

# Relation Subtypes in the Data

In addition to the universal dependency taxonomy, it is desirable to recognize grammatical relations that are particular to one language or a small group of related languages.
Such language-specific relations are necessary to accurately capture the genius of a particular language but will not involve concepts that generalize broadly.
These language-specific relations should always be regarded as a subtype of an existing UD relation.

Labels of language-specific relations explictly encode the core UD relation that the language-specific relation is a subtype of, following the format *universal:extension*.

This is an automatically generated list of relation subtypes that occur in the UD data.
EOF
    ;
    # Get the list of universal relations that are involved in subtyping.
    my %udeprels;
    my @deprels = sort(keys(%{$hash}));
    foreach my $deprel (@deprels)
    {
        my $udeprel = $deprel;
        $udeprel =~ s/:.*//;
        $udeprels{$udeprel}++;
    }
    my @udeprels = sort(keys(%udeprels));
    foreach my $udeprel (@udeprels)
    {
        print("\n\n\n## $udeprel\n");
        foreach my $deprel (@deprels)
        {
            if($deprel =~ m/^$udeprel:/)
            {
                my @keys = sort(keys(%{$hash->{$deprel}}));
                #my @keys_with_frequencies = map {"$_&nbsp;($hash->{$deprel}{$_})"} (@keys);
                print("* [$deprel](): ".join(', ', @keys)."\n");
            }
        }
    }
}
