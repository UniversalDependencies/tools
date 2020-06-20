#!/usr/bin/env perl
# Scans all UD treebanks for language-specific subtypes of dependency relations.
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
    print STDERR ("Usage: perl survey_deprel_subtypes.pl --tbklist udsubset.txt\n");
    print STDERR ("       --tbklist .... file with list of UD_* folders to consider (e.g. treebanks we are about to release)\n");
    print STDERR ("                      if tbklist is not present, all treebanks in datapath will be scanned\n");
}

my $tbklist;
GetOptions
(
    'tbklist=s'  => \$tbklist   # path to file with treebank list; if defined, only treebanks on the list will be surveyed
);
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

# This script expects to be invoked in the folder in which all the UD_folders
# are placed.
opendir(DIR, '.') or die('Cannot read the contents of the working folder');
my @folders = sort(grep {-d $_ && m/^UD_[A-Z]/} (readdir(DIR)));
closedir(DIR);
# We need a mapping from the English names of the languages (as they appear in folder names) to their ISO codes.
# There is now also the new list of languages in YAML in docs-automation; this one has also language families.
my $languages_from_yaml = udlib::get_language_hash("$libpath/../docs-automation/codes_and_flags.yaml");
my %langnames;
my %langcodes;
foreach my $language (keys(%{$languages_from_yaml}))
{
    # We need a mapping from language names in folder names (contain underscores instead of spaces) to language codes.
    my $usname = $language;
    $usname =~ s/ /_/g;
    # Language names in the YAML file may contain spaces (not underscores).
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
            $key = $langcode;
            $key .= '_'.lc($treebank) if($treebank ne '');
            chdir($folder) or die("Cannot enter folder $folder");
            # Look for the other files in the repository.
            opendir(DIR, '.') or die("Cannot read the contents of the folder $folder");
            my @files = readdir(DIR);
            closedir(DIR);
            my @conllufiles = grep {-f $_ && m/\.conllu$/} (@files);
            foreach my $file (@conllufiles)
            {
                # Read the file and look for language-specific subtypes in the DEPREL column.
                # We currently do not look for additional types in the DEPS column.
                open(FILE, $file) or die("Cannot read $file: $!");
                while(<FILE>)
                {
                    if(m/^\d+\t/)
                    {
                        chomp();
                        my @fields = split(/\t/, $_);
                        my $deprel = $fields[7];
                        if($deprel =~ m/:/)
                        {
                            $hash{$deprel}{$key}++;
                        }
                    }
                }
            }
            chdir('..') or die("Cannot return to the upper folder");
        }
    }
}
###!!! We currently do not take deprels from validator data if they do not occur in the data.
if(0)
{
    # Check the permitted deprels in validator data. Are there types that do not occur in the data?
    chdir('tools/data') or die("Cannot enter folder tools/data");
    opendir(DIR, '.') or die("Cannot read the contents of the folder tools/data");
    my @files = readdir(DIR);
    closedir(DIR);
    my @deprelfiles = grep {-f $_ && m/^deprel\..+/} (@files);
    foreach my $file (@deprelfiles)
    {
        $file =~ m/^deprel\.(.+)$/;
        my $key = $1;
        next if($key eq 'ud');
        open(FILE, $file) or die("Cannot read $file: $!");
        while(<FILE>)
        {
            s/\r?\n$//;
            my $deprel = $_;
            if(!m/^\s*$/ && !exists($hash{$deprel}{$key}))
            {
                $hash{$deprel}{$key} = 'ZERO BUT LISTED AS PERMITTED IN VALIDATOR DATA';
            }
        }
        close(FILE);
    }
    chdir('../..');
}
# Print the docs page with the list of language-specific deprel subtypes.
my $markdown = <<EOF
---
layout: base
title:  'Language-Specific Relations'
udver:  '2'
---

# Language-Specific Relations

In addition to the universal dependency taxonomy, it is desirable to recognize grammatical relations that are particular to one language or a small group of related languages. Such language-specific relations are necessary to accurately capture the genius of a particular language but will not involve concepts that generalize broadly. These language-specific relations should always be regarded as a subtype of an existing UD relation.

Labels of language-specific relations explictly encode the core UD relation that the language-specific relation is a subtype of, following the format *universal:extension*.
EOF
;
# Get the list of universal relations that are involved in subtyping.
my %udeprels;
my @deprels = sort(keys(%hash));
foreach my $deprel (@deprels)
{
    my $udeprel = $deprel;
    $udeprel =~ s/:.*//;
    $udeprels{$udeprel}++;
}
my @udeprels = sort(keys(%udeprels));
foreach my $udeprel (@udeprels)
{
    $markdown .= "\n\n\n## $udeprel\n";
    foreach my $deprel (@deprels)
    {
        if($deprel =~ m/^$udeprel:/)
        {
            $markdown .= "- [$deprel]():\n";
            my @folders = sort(keys(%{$hash{$deprel}}));
            my %mdlanguages; # use a hash to merge hits from different treebanks of one language
            foreach my $folder (@folders)
            {
                my $langcode = $folder;
                $langcode =~ s/_.*//;
                $mdlanguages{$langnames{$langcode}}++;
            }
            $markdown .= join(",\n", sort(keys(%mdlanguages)))."\n";
        }
    }
}
open(FILE, ">docs/ext-dep-index.md") or die("Cannot write ext-dep-index.md: $!");
print FILE ($markdown);
close(FILE);
