#!/usr/bin/env perl
# Checks files to be distributed as Universal Dependencies.
# Copyright © 2015 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;

# Include reports on future repositories (not scheduled for the upcoming release)?
# (If there is no README file, we will include the repository in the report and complain about the missing README.)
my $include_future = 0;
GetOptions
(
    'future' => \$include_future
);

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
    'Catalan'             => 'ca',
    'Croatian'            => 'hr',
    'Czech'               => 'cs',
    'Danish'              => 'da',
    'Dutch'               => 'nl',
    'English'             => 'en',
    'Estonian'            => 'et',
    'Finnish'             => 'fi',
    'French'              => 'fr',
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
    'Norwegian'           => 'no',
    'Old_Church_Slavonic' => 'cu',
    'Persian'             => 'fa',
    'Polish'              => 'pl',
    'Portuguese'          => 'pt',
    'Romanian'            => 'ro',
    'Russian'             => 'ru',
    'Slovak'              => 'sk',
    'Slovenian'           => 'sl',
    'Spanish'             => 'es',
    'Swedish'             => 'sv',
    'Tamil'               => 'ta',
    'Turkish'             => 'tr'
);
my $n_folders_with_data = 0;
my $n_errors = 0;
my %languages_with_data;
foreach my $folder (@folders)
{
    # The name of the folder: 'UD_' + language name + optional treebank identifier.
    # Example: UD_Ancient_Greek-PROIEL
    my $language = '';
    my $treebank = '';
    my $langcode;
    if($folder =~ m/^UD_([A-Za-z_]+)(?:-([A-Z]+))?$/)
    {
        $language = $1;
        $treebank = $2 if(defined($2));
        if(exists($langcodes{$language}))
        {
            $langcode = $langcodes{$language};
            chdir($folder) or die("Cannot enter folder $folder");
            # Read the README file first. We need to know whether this repository is scheduled for the upcoming release.
            if(!-f 'README.txt' && !-f 'README.md')
            {
                print("$folder: missing README.txt|md\n");
                $n_errors++;
            }
            if(-f 'README.txt' && -f 'README.md')
            {
                print("$folder: both README.txt and README.md are present\n");
                $n_errors++;
            }
            my $metadata = read_readme($folder);
            if(!$metadata->{release} && !$include_future)
            {
                chdir('..') or die("Cannot return to the upper folder");
                next;
            }
            # Look for the other files in the repository.
            opendir(DIR, '.') or die("Cannot read the contents of the folder $folder");
            my @conllufiles = grep {-f $_ && m/\.conllu$/} (readdir(DIR));
            my $n = scalar(@conllufiles);
            if($n==0)
            {
                print("No data in $folder\n");
            }
            elsif(!-d '.git')
            {
                print("Not a git repository: $folder\n");
            }
            else
            {
                if($n>0)
                {
                    $n_folders_with_data++;
                    $languages_with_data{$language}++;
                }
                my $expected_n = $langcode eq 'cs' ? 6 : 3;
                unless($n==$expected_n)
                {
                    print("$folder: expected $expected_n CoNLL-U files, found $n\n");
                    $n_errors++;
                }
                if(!-f 'LICENSE.txt')
                {
                    print("$folder: missing LICENSE.txt (README says license is '$metadata->{License}')\n");
                    $n_errors++;
                }
                # Check the names of the data files.
                my $prefix = $langcode;
                $prefix .= '_'.lc($treebank) if($treebank ne '');
                $prefix .= '-ud';
                if($langcode ne 'cs' && !-f "$prefix-train.conllu")
                {
                    print("$folder: missing $prefix-train.conllu\n");
                    $n_errors++;
                }
                elsif($langcode eq 'cs' && (!-f "$prefix-train-c.conllu" || !-f "$prefix-train-l.conllu" || !-f "$prefix-train-m.conllu" || !-f "$prefix-train-v.conllu"))
                {
                    print("$folder: missing at least one file of $prefix-train-[clmv].conllu\n");
                    $n_errors++;
                }
                if(!-f "$prefix-dev.conllu")
                {
                    print("$folder: missing $prefix-dev.conllu\n");
                    $n_errors++;
                }
                if(!-f "$prefix-test.conllu")
                {
                    print("$folder: missing $prefix-test.conllu\n");
                    $n_errors++;
                }
            }
            closedir(DIR);
            chdir('..') or die("Cannot return to the upper folder");
        }
        else
        {
            print("Unknown language $language.\n");
        }
    }
    else
    {
        print("Cannot parse folder name $folder.\n");
    }
}
print("Found ", scalar(@folders), " repositories.\n");
print("$n_folders_with_data are git repositories and contain data.\n");
my @languages = sort(keys(%languages_with_data));
print(scalar(@languages), " languages with data: ", join(' ', @languages), "\n");
print("$n_errors errors must be fixed.\n") if($n_errors>0);



#------------------------------------------------------------------------------
# Reads the README file of a treebank and finds the metadata lines. Example:
#=== Machine-readable metadata ================================================
#Documentation status: partial
#Data source: automatic
#Data available since: UD v1.2
#License: CC BY-NC-SA 2.5
#Genre: fiction
#Contributors: Celano, Giuseppe G. A.; Zeman, Daniel
#==============================================================================
#------------------------------------------------------------------------------
sub read_readme
{
    # Assumption: The current folder is a UD data repository.
    # Nevertheless, we want to know the folder name so we can use it in messages.
    my $folder = shift;
    my $filename = (-f 'README.txt') ? 'README.txt' : 'README.md';
    open(README, $filename) or return;
    my %metadata;
    my @attributes = ('Documentation status', 'Data source', 'Data available since', 'License', 'Genre', 'Contributors');
    my $attributes_re = join('|', @attributes);
    while(<README>)
    {
        s/\r?\n$//;
        s/^\s+//;
        s/\s+$//;
        s/\s+/ /g;
        if(m/^($attributes_re):\s*(.*)$/i)
        {
            my $attribute = $1;
            my $value = $2;
            $value = '' if(!defined($value));
            if(exists($metadata{$attribute}))
            {
                print("WARNING: Repeated definition of '$attribute' in $folder/$filename\n");
            }
            $metadata{$attribute} = $value;
            if($attribute eq 'Data available since')
            {
                if($metadata{$attribute} =~ m/^UD v1\.(\d)$/ && $1 <= 2)
                {
                    $metadata{'release'} = 1;
                }
            }
        }
    }
    close(README);
    if(!$metadata{'release'} && !$include_future)
    {
        return;
    }
    # Check the values of the metadata.
    foreach my $attribute (@attributes)
    {
        if(!exists($metadata{$attribute}))
        {
            print("WARNING: Attribute '$attribute' not defined in $folder/$filename\n");
        }
        elsif($attribute eq 'License')
        {
            if($metadata{$attribute} eq '')
            {
                print("WARNING: unknown license in $folder/$filename\n");
            }
        }
        elsif($attribute eq 'Genre')
        {
            if($metadata{$attribute} eq '')
            {
                print("WARNING: unknown genre in $folder/$filename\n");
            }
        }
        elsif($attribute eq 'Contributors')
        {
            if($metadata{$attribute} eq '')
            {
                print("WARNING: unknown contributors in $folder/$filename\n");
            }
        }
    }
    return \%metadata;
}
