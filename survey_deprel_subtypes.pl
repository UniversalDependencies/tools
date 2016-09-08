#!/usr/bin/env perl
# Scans all UD treebanks for language-specific subtypes of dependency relations.
# Copyright © 2016 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# This script expects to be invoked in the folder in which all the UD_folders
# are placed.
opendir(DIR, '.') or die('Cannot read the contents of the working folder');
my @folders = sort(grep {-d $_ && m/^UD_[A-Z]/} (readdir(DIR)));
closedir(DIR);
# We need a mapping from the English names of the languages (as they appear in folder names) to their ISO codes.
my %langcodes =
(
    'Amharic'             => 'am',
    'Ancient_Greek'       => 'grc',
    'Arabic'              => 'ar',
    'Basque'              => 'eu',
    'Bulgarian'           => 'bg',
    'Buryat'              => 'bxr',
    'Catalan'             => 'ca',
    'Chinese'             => 'zh',
    'Coptic'              => 'cop',
    'Croatian'            => 'hr',
    'Czech'               => 'cs',
    'Danish'              => 'da',
    'Dutch'               => 'nl',
    'English'             => 'en',
    'Estonian'            => 'et',
    'Finnish'             => 'fi',
    'French'              => 'fr',
    'Galician'            => 'gl',
    'German'              => 'de',
    'Gothic'              => 'got',
    'Greek'               => 'el',
    'Hebrew'              => 'he',
    'Hindi'               => 'hi',
    'Hungarian'           => 'hu',
    'Indonesian'          => 'id',
    'Irish'               => 'ga',
    'Italian'             => 'it',
    'Japanese'            => 'ja',
    'Kazakh'              => 'kk',
    'Korean'              => 'ko',
    'Latin'               => 'la',
    'Latvian'             => 'lv',
    'Norwegian'           => 'no',
    'Old_Church_Slavonic' => 'cu',
    'Persian'             => 'fa',
    'Polish'              => 'pl',
    'Portuguese'          => 'pt',
    'Romanian'            => 'ro',
    'Russian'             => 'ru',
    'Sanskrit'            => 'sa',
    'Slovak'              => 'sk',
    'Slovenian'           => 'sl',
    'Spanish'             => 'es',
    'Swedish'             => 'sv',
    'Tamil'               => 'ta',
    'Turkish'             => 'tr',
    'Ukrainian'           => 'uk',
    'Uyghur'              => 'ug',
    'Vietnamese'          => 'vi'
);
my %langnames;
foreach my $language (keys(%langcodes))
{
    my $lnicename = $language;
    $lnicename =~ s/_/ /g;
    $langnames{$langcodes{$language}} = $lnicename;
}
# Look for deprels in the data.
my %hash;
foreach my $folder (@folders)
{
    # The name of the folder: 'UD_' + language name + optional treebank identifier.
    # Example: UD_Ancient_Greek-PROIEL
    my $language = '';
    my $treebank = '';
    my $langcode;
    my $key;
    if($folder =~ m/^UD_([A-Za-z_]+)(?:-([A-Za-z]+))?$/)
    {
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
        chomp();
        my $deprel = $_;
        if(!m/^\s*$/ && !exists($hash{$deprel}{$key}))
        {
            $hash{$deprel}{$key} = 'ZERO BUT LISTED AS PERMITTED IN VALIDATOR DATA';
        }
    }
    close(FILE);
}
chdir('../..');
my @deprels = sort(keys(%hash));
foreach my $deprel (@deprels)
{
    my @folders = sort(keys(%{$hash{$deprel}}));
    foreach my $folder (@folders)
    {
        print("$deprel\t$folder\t$hash{$deprel}{$folder}\n");
        # Does documentation contain a corresponding page?
        chdir('docs') or die("Cannot enter folder docs");
        my $langcode = $folder;
        $langcode =~ s/_.*//;
        my $filename = $deprel;
        $filename =~ s/:/-/;
        my $docspath = '_'.$langcode.'-dep/'.$filename.'.md';
        if($hash{$deprel}{$folder} !~ m/^ZERO/ && !-f $docspath)
        {
            my $template = <<EOF
---
layout: relation
title: '$deprel'
shortdef: '$deprel'
---

This document is a placeholder for the language-specific documentation
for \`$deprel\`.
EOF
            ;
            open(FILE, ">$docspath") or die("Cannot write $docspath: $!");
            print FILE ($template);
            close(FILE);
            system("git add $docspath");
        }
        chdir('..');
    }
}
# Print the docs page with the list of language-specific deprel subtypes.
my $markdown = <<EOF
---
layout: base
title:  'Language-specific relations'
---

# Language-specific relations

In addition to the universal dependency taxonomy, it is desirable to recognize grammatical relations that are particular to one language or a small group of related languages. Such language-specific relations are necessary to accurately capture the genius of a particular language but will not involve concepts that generalize broadly. These language-specific relations should always be regarded as a subtype of an existing UD relation.

Labels of language-specific relations explictly encode the core UD relation that the language-specific relation is a subtype of, following the format *universal:extension*.
EOF
;
# Get the list of universal relations that are involved in subtyping.
my %udeprels;
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
            $markdown .= "- \`$deprel\`:\n";
            my @folders = sort(keys(%{$hash{$deprel}}));
            my %mdlanguages;
            foreach my $folder (@folders)
            {
                my $langcode = $folder;
                $langcode =~ s/_.*//;
                $mdlanguages{$langnames{$langcode}} = "[$langnames{$langcode}]($langcode-dep/$deprel)";
            }
            $markdown .= join(",\n", map {$mdlanguages{$_}} (sort(keys(%mdlanguages))))."\n";
        }
    }
}
open(FILE, ">docs/ext-dep-index.md") or die("Cannot write ext-dep-index.md: $!");
print FILE ($markdown);
close(FILE);
