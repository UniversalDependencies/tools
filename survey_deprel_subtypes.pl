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
    }
}
