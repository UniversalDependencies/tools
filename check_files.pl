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
# Dan's sorting library
use csort;

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
my %licenses;
my %genres;
my %contributors;
my %stats;
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
            my $current_release = 1.2;
            if($metadata->{'Data available since'} =~ m/UD\s*v([0-9]+\.[0-9]+)/ && $1 < $current_release && !$metadata->{changelog})
            {
                print("$folder: Old treebank ($metadata->{'Data available since'}) but README does not contain 'ChangeLog'\n");
                $n_errors++;
            }
            # Look for the other files in the repository.
            opendir(DIR, '.') or die("Cannot read the contents of the folder $folder");
            my @files = readdir(DIR);
            my @conllufiles = grep {-f $_ && m/\.conllu$/} (@files);
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
                # This is a git repository with data.
                # Make sure it is up-to-date.
                print("git pull $folder\n");
                system('git pull');
                print(`git status`);
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
                    generate_license($metadata->{License});
                    $n_errors++;
                }
                # Check the names of the data files.
                my $key = $langcode;
                $key .= '_'.lc($treebank) if($treebank ne '');
                my $prefix = $key.'-ud';
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
                $stats{$key} = collect_statistics_about_ud_treebank('.', $key);
                # Look for additional files. (Do we want to include them in the release package?)
                my @extrafiles = map
                {
                    $_ .= '/' if(-d $_);
                    $_
                }
                grep
                {
                    !m/^(\.\.?|\.git(ignore)?|README\.(txt|md)|LICENSE\.txt|$prefix-(train|dev|test)\.conllu|cs-ud-train-[clmv]\.conllu|stats\.xml)$/
                }
                (@files);
                if(scalar(@extrafiles)>0)
                {
                    print("$folder extra files: ", join(', ', sort(@extrafiles)), "\n");
                }
                # Summarize metadata.
                if($metadata->{'License'} ne '')
                {
                    $licenses{$metadata->{'License'}}++;
                }
                if($metadata->{'Genre'} ne '')
                {
                    my @genres = split(/\s+/, $metadata->{'Genre'});
                    foreach my $genre (@genres)
                    {
                        $genres{$genre}++;
                    }
                }
                if($metadata->{'Contributors'} ne '')
                {
                    my @contributors = split(/;\s*/, $metadata->{'Contributors'});
                    foreach my $contributor (@contributors)
                    {
                        $contributor =~ s/^\s+//;
                        $contributor =~ s/\s+$//;
                        $contributors{$contributor}++;
                    }
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
my @languages = map {s/_/ /g; $_} (sort(keys(%languages_with_data)));
print(scalar(@languages), " languages with data: ", join(', ', @languages), "\n\n");
my @licenses = sort(keys(%licenses));
print(scalar(@licenses), " different licenses: ", join(', ', @licenses), "\n\n");
my @genres = sort(keys(%genres));
print(scalar(@genres), " different genres: ", join(', ', @genres), "\n\n");
my @contributors = keys(%contributors);
my %trid;
foreach my $contributor (@contributors)
{
    $trid{$contributor} = csort::zjistit_tridici_hodnoty($contributor, 'en');
}
my @contributors = sort {my $v; $v = -1 if($a eq 'Nivre, Joakim'); $v = 1 if($b eq 'Nivre, Joakim'); unless($v) { $v = $trid{$a} cmp $trid{$b}; } $v} (keys(%contributors));
#@contributors = map {my $x = $_; if($x =~ m/^(.+?),\s*(.+)$/) {$x = "$2 $1";} $x} (@contributors);
print(scalar(@contributors), " contributors: ", join('; ', @contributors), "\n\n");
print("$n_errors errors must be fixed.\n") if($n_errors>0);
# Old release.
# zen:/net/data/universal-dependencies-1.1
# mekong:C:\Users\Dan\Documents\Lingvistika\Projekty\universal-dependencies\release-1.1
my $oldpath = 'C:\Users\Dan\Documents\Lingvistika\Projekty\universal-dependencies\release-1.1';
print("Collecting statistics of $oldpath...\n");
my $stats11 = collect_statistics_about_ud_release($oldpath);
my @languages11 = sort(keys(%{$stats11}));
foreach my $l (@languages11)
{
    print("$l\tt=$stats11->{$l}{ntok}\tw=$stats11->{$l}{nword}\tf=$stats11->{$l}{nfus}\ts=$stats11->{$l}{nsent}\n");
    if($stats11->{$l}{ntok}  != $stats{$l}{ntok}  ||
       $stats11->{$l}{nword} != $stats{$l}{nword} ||
       $stats11->{$l}{nfus}  != $stats{$l}{nfus}  ||
       $stats11->{$l}{nsent} != $stats{$l}{nsent})
    {
        print(" NOW:\tt=$stats{$l}{ntok}\tw=$stats{$l}{nword}\tf=$stats{$l}{nfus}\ts=$stats{$l}{nsent}\n");
    }
}
print("\n");
# Then we may want to do this for treebanks whose size has not changed:
# zeman@zen:/ha/home/zeman/network/unidep$ for i in UD_* ; do echo $i ; cd $i ; git pull ; cd .. ; done
# zeman@zen:/net/data/universal-dependencies-1.1$ for i in German Greek English Finnish Finnish-FTB Irish Hebrew Croatian Hungarian Indonesian Swedish ; do for j in UD_$i/*.conllu ; do echo diff $j /net/work/people/zeman/unidep/$j ; ( diff $j /net/work/people/zeman/unidep/$j | head -2 ) ; done ; done
my @languages = sort(keys(%stats));
my $ntok = 0;
my $nword = 0;
my $nfus = 0;
my $nsent = 0;
foreach my $l (@languages)
{
    print("$l\tt=$stats{$l}{ntok}\tw=$stats{$l}{nword}\tf=$stats{$l}{nfus}\ts=$stats{$l}{nsent}\n");
    $ntok += $stats{$l}{ntok};
    $nword += $stats{$l}{nword};
    $nfus += $stats{$l}{nfus};
    $nsent += $stats{$l}{nsent};
}
print("TOTAL\tt=$ntok\tw=$nword\tf=$nfus\ts=$nsent\n");



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
    binmode(README, ':utf8');
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
        elsif(m/change(\s|-)*log/i)
        {
            $metadata{'changelog'} = 1;
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



#------------------------------------------------------------------------------
# Generates the LICENSE.txt file for a Creative Commons license.
#------------------------------------------------------------------------------
sub generate_license
{
    my $license = shift;
    ###!!! Currently all missing licenses are CC BY-NC-SA 3.0 so I am not going to make this more general.
    if($license ne 'CC BY-NC-SA 3.0')
    {
        print("WARNING: Cannot generate LICENSE.txt for license '$license'\n");
        return;
    }
    my $text = <<EOF
This work is licensed under the Creative Commons Attribution-NonCommercial-
ShareAlike 3.0 Generic License. To view a copy of this license, visit

http://creativecommons.org/licenses/by-nc-sa/3.0/

or send a letter to
Creative Commons, PO Box 1866, Mountain View, CA 94042, USA.
EOF
    ;
    open(LICENSE, '>LICENSE.txt') or die("Cannot write LICENSE.txt: $!");
    print LICENSE ($text);
    close(LICENSE);
    system('git add LICENSE.txt');
}



#------------------------------------------------------------------------------
# Examines a UD distribution and counts the number of tokens for every
# treebank in the distribution. The results can be used to compare the current
# release with a previous one.
#------------------------------------------------------------------------------
sub collect_statistics_about_ud_release
{
    my $release_path = shift;
    my %stats;
    opendir(DIR, $release_path) or die("Cannot read folder $release_path: $!");
    my @folders = readdir(DIR);
    closedir(DIR);
    foreach my $folder (@folders)
    {
        # The name of the folder: 'UD_' + language name + optional treebank identifier.
        # Example: UD_Ancient_Greek-PROIEL
        my $language = '';
        my $treebank = '';
        my $langcode;
        if(-d "$release_path/$folder" && $folder =~ m/^UD_([A-Za-z_]+)(?:-([A-Z]+))?$/)
        {
            $language = $1;
            $treebank = $2 if(defined($2));
            if(exists($langcodes{$language}))
            {
                $langcode = $langcodes{$language};
                my $key = $langcode;
                $key .= '_'.lc($treebank) if($treebank ne '');
                $stats{$key} = collect_statistics_about_ud_treebank("$release_path/$folder", $key);
            }
        }
    }
    return \%stats;
}



#------------------------------------------------------------------------------
# Examines a UD treebank and counts the number of tokens in all .conllu files.
#------------------------------------------------------------------------------
sub collect_statistics_about_ud_treebank
{
    my $treebank_path = shift;
    my $treebank_code = shift;
    my $prefix = "$treebank_code-ud";
    # All .conllu files with the given prefix in the given folder are considered disjunct parts of the treebank.
    # Hence we do not have to bother with Czech exceptions in file naming etc.
    # But we have to be careful if we look at a future release where the folders may not yet be clean.
    opendir(DIR, $treebank_path) or die("Cannot read folder $treebank_path: $!");
    my @files = grep {m/^$prefix-.+\.conllu$/} (readdir(DIR));
    closedir(DIR);
    my $nsent = 0;
    my $ntok = 0;
    my $nfus = 0;
    my $nword = 0;
    foreach my $file (@files)
    {
        open(CONLLU, "$treebank_path/$file") or die("Cannot read file $treebank_path/$file");
        while(<CONLLU>)
        {
            # Skip comment lines.
            next if(m/^\#/);
            # Empty lines separate sentences. There must be an empty line after every sentence including the last one.
            if(m/^\s*$/)
            {
                $nsent++;
            }
            # Lines with fused tokens do not contain features but we want to count the fusions.
            elsif(m/^(\d+)-(\d+)\t(\S+)/)
            {
                my $i0 = $1;
                my $i1 = $2;
                my $size = $i1-$i0+1;
                $ntok -= $size-1;
                $nfus++;
            }
            else
            {
                $ntok++;
                $nword++;
            }
        }
        close(CONLLU);
    }
    my $stats =
    {
        'nsent' => $nsent,
        'ntok'  => $ntok,
        'nfus'  => $nfus,
        'nword' => $nword
    };
    return $stats;
}
