#!/usr/bin/env perl
# Checks files to be distributed as Universal Dependencies.
# Copyright © 2015, 2016 Dan Zeman <zeman@ufal.mff.cuni.cz>
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
# Pull the latest changes from Github and show git status of each repository?
my $pull = 0;
# Recompute statistics of all treebanks and push them to Github?
my $recompute_stats = 0;
# Tag all repositories with the new release? (The $tag variable is either empty or it contains the tag.)
my $tag = ''; # example: 'r1.0'
# Number of the current release as it is found in README files. Repositories targeting a later release will not be included.
my $current_release = 1.4;
# Path to the previous release is needed to compare the number of sentences and words.
# zen:/net/data/universal-dependencies-1.2
# mekong:C:\Users\Dan\Documents\Lingvistika\Projekty\universal-dependencies\release-1.2
my $oldpath = '/net/data/universal-dependencies-1.3';
GetOptions
(
    'future' => \$include_future,
    'pull'   => \$pull,
    'stats'  => \$recompute_stats,
    'tag=s'  => \$tag
);

# This script expects to be invoked in the folder in which all the UD_folders
# are placed.
opendir(DIR, '.') or die('Cannot read the contents of the working folder');
my @folders = sort(grep {-d $_ && m/^UD_[A-Z]/} (readdir(DIR)));
closedir(DIR);
# We need a mapping from the English names of the languages (as they appear in folder names) to their ISO codes.
my %langcodes =
(
    'Amharic'               => 'am',
    'Ancient_Greek'         => 'grc',
    'Arabic'                => 'ar',
    'Basque'                => 'eu',
    'Belarusian'            => 'be',
    'Bulgarian'             => 'bg',
    'Buryat'                => 'bxr',
    'Cantonese'             => 'yue',
    'Catalan'               => 'ca',
    'Chinese'               => 'zh',
    'Coptic'                => 'cop',
    'Croatian'              => 'hr',
    'Czech'                 => 'cs',
    'Danish'                => 'da',
    'Dutch'                 => 'nl',
    'English'               => 'en',
    'Estonian'              => 'et',
    'Faroese'               => 'fo',
    'Finnish'               => 'fi',
    'French'                => 'fr',
    'Galician'              => 'gl',
    'German'                => 'de',
    'Gothic'                => 'got',
    'Greek'                 => 'el',
    'Hebrew'                => 'he',
    'Hindi'                 => 'hi',
    'Hungarian'             => 'hu',
    'Indonesian'            => 'id',
    'Irish'                 => 'ga',
    'Italian'               => 'it',
    'Japanese'              => 'ja',
    'Kazakh'                => 'kk',
    'Korean'                => 'ko',
    'Kurmanji'              => 'kmr',
    'Latin'                 => 'la',
    'Latvian'               => 'lv',
    'Marathi'               => 'mr',
    'Norwegian'             => 'no',
    'Old_Church_Slavonic'   => 'cu',
    'Persian'               => 'fa',
    'Polish'                => 'pl',
    'Portuguese'            => 'pt',
    'Romanian'              => 'ro',
    'Russian'               => 'ru',
    'Sanskrit'              => 'sa',
    'Serbian'               => 'sr',
    'Slovak'                => 'sk',
    'Slovenian'             => 'sl',
    'Somali'                => 'so',
    'Sorani'                => 'ckb',
    'Spanish'               => 'es',
    'Swedish'               => 'sv',
    'Swedish_Sign_Language' => 'swl',
    'Tamil'                 => 'ta',
    'Turkish'               => 'tr',
    'Ukrainian'             => 'uk',
    'Urdu'                  => 'ur',
    'Uyghur'                => 'ug',
    'Vietnamese'            => 'vi'
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
    if($folder =~ m/^UD_([A-Za-z_]+)(?:-([A-Za-z]+))?$/)
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
            my $metadata = read_readme($folder, $current_release);
            if(!$metadata->{release} && !$include_future)
            {
                chdir('..') or die("Cannot return to the upper folder");
                next;
            }
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
                if($pull)
                {
                    print("git pull $folder\n");
                    system('git pull --tags');
                    print(`git status`);
                }
                if($n>0)
                {
                    $n_folders_with_data++;
                    $languages_with_data{$language}++;
                }
                my $expected_n = ($language eq 'Czech' && $treebank eq '') ? 6 : 3;
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
                if(!($language eq 'Czech' && $treebank eq '') && !-f "$prefix-train.conllu")
                {
                    print("$folder: missing $prefix-train.conllu\n");
                    $n_errors++;
                }
                elsif($language eq 'Czech' && $treebank eq '' && (!-f "$prefix-train-c.conllu" || !-f "$prefix-train-l.conllu" || !-f "$prefix-train-m.conllu" || !-f "$prefix-train-v.conllu"))
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
                    !m/^(\.\.?|\.git(ignore)?|not-to-release|README\.(txt|md)|LICENSE\.txt|$prefix-(train|dev|test)\.conllu|cs-ud-train-[clmv]\.conllu|stats\.xml)$/
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
                # Recompute statistics of the treebank and push it back to Github.
                if($recompute_stats)
                {
                    print("Recomputing statistics of $folder...\n");
                    system('cat *.conllu | ../tools/conllu-stats.pl > stats.xml');
                    print("Pushing statistics to Github...\n");
                    system('git add stats.xml');
                    system('git commit -m "Updated statistics."');
                    if($tag ne '')
                    {
                        print("Tagging $folder $tag\n");
                        system("git tag $tag");
                    }
                    system('git push');
                    system('git push --tags');
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
my @langcodes = sort(keys(%stats));
print("Treebank codes: ", join(' ', @langcodes), "\n\n");
my %langcodes1; map {my $x=$_; $x=~s/_.*//; $langcodes1{$x}++} (@langcodes);
my @langcodes1 = sort(keys(%langcodes1));
print("Language codes: ", join(' ', @langcodes1), "\n\n");
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
my @contributors_firstlast = map {my $x = $_; if($x =~ m/^(.+?),\s*(.+)$/) {$x = "$2 $1";} $x} (@contributors);
print(scalar(@contributors), " contributors: ", join('; ', @contributors), "\n\n");
print("$n_errors errors must be fixed.\n") if($n_errors>0);
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
my $ntok = 0;
my $nword = 0;
my $nfus = 0;
my $nsent = 0;
foreach my $l (@langcodes)
{
    print("$l\tt=$stats{$l}{ntok}\tw=$stats{$l}{nword}\tf=$stats{$l}{nfus}\ts=$stats{$l}{nsent}\n");
    $ntok += $stats{$l}{ntok};
    $nword += $stats{$l}{nword};
    $nfus += $stats{$l}{nfus};
    $nsent += $stats{$l}{nsent};
}
print("TOTAL\tt=$ntok\tw=$nword\tf=$nfus\ts=$nsent\n");
print("--------------------------------------------------------------------------------\n");
my $announcement = get_announcement(1.4, $n_folders_with_data, \@languages, 'less than 1,000 tokens', 'well over 1.5 million tokens', 'March 2017', \@contributors_firstlast);
print($announcement);



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
    my $current_release = shift;
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
                if($metadata{$attribute} =~ m/^UD\s+v(\d\.\d)$/ && $1 <= $current_release)
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
        if(-d "$release_path/$folder" && $folder =~ m/^UD_([A-Za-z_]+)(?:-([A-Za-z]+))?$/)
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



#------------------------------------------------------------------------------
# Generates the announcement of the release, listing all languages and
# contributors.
#------------------------------------------------------------------------------
sub get_announcement
{
    my $release = shift; # 1.4
    my $n_treebanks = shift; # 63
    my $langlistref = shift;
    my $min_size = shift; # 'about 9,000 tokens'
    my $max_size = shift; # 'well over 1.5 million tokens'
    my $next_release_available_in = shift; # 'March 2017'
    my $contlistref = shift;
    my @release_list = (1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13, 2.14);
    my @nth_vocabulary = qw(first second third fourth fifth sixth seventh eighth ninth tenth eleventh twelfth thirteenth fourteenth fifteenth sixteenth seventeenth eighteenth nineteenth twentieth);
    my $nth;
    for(my $i = 0; $i<=$#release_list; $i++)
    {
        if($release_list[$i]==$release)
        {
            $nth = $nth_vocabulary[$i];
        }
        last if($release_list[$i]>=$release);
    }
    $nth = "WARNING: UNKNOWN RELEASE '$release'" if(!defined($nth));
    my $guidelines_version = int($release);
    my @languages = @{$langlistref};
    my $n_languages = scalar(@languages);
    my $languages = join(', ', @languages);
    $languages =~ s/, ([^,]+)$/ and $1/;
    my @contributors = @{$contlistref};
    my $contributors = join(', ', @contributors);
    my $text = <<EOF
We are very happy to announce the $nth release of annotated treebanks in Universal Dependencies, v$release, available at http://universaldependencies.org/.

Universal Dependencies is a project that seeks to develop cross-linguistically consistent treebank annotation for many languages with the goal of facilitating multilingual parser development, cross-lingual learning, and parsing research from a language typology perspective (Nivre et al., 2016). The annotation scheme is based on (universal) Stanford dependencies (de Marneffe et al., 2006, 2008, 2014), Google universal part-of-speech tags (Petrov et al., 2012), and the Interset interlingua for morphosyntactic tagsets (Zeman, 2008). The general philosophy is to provide a universal inventory of categories and guidelines to facilitate consistent annotation of similar constructions across languages, while allowing language-specific extensions when necessary.

The $n_treebanks treebanks in v$release are annotated according to version $guidelines_version of the UD guidelines and represent the following $n_languages languages: $languages. Depending on the language, the treebanks range in size from $min_size to $max_size. We expect the next release to be available in $next_release_available_in.

$contributors


References

Marie-Catherine de Marneffe, Bill MacCartney, and Christopher D. Manning. 2006. Generating typed dependency parses from phrase structure parses. In Proceedings of LREC.

Marie-Catherine de Marneffe and Christopher D. Manning. 2008. The Stanford typed dependencies representation. In COLING Workshop on Cross-framework and Cross-domain Parser Evaluation.

Marie-Catherine de Marneffe, Timothy Dozat, Natalia Silveira, Katri Haverinen, Filip Ginter, Joakim Nivre, and Christopher Manning. 2014. Universal Stanford Dependencies: A cross-linguistic typology. In Proceedings of LREC.

Joakim Nivre, Marie-Catherine de Marneffe, Filip Ginter, Yoav Goldberg, Jan Hajič, Christopher D. Manning, Ryan McDonald, Slav Petrov, Sampo Pyysalo, Natalia Silveira, Reut Tsarfaty, Daniel Zeman. 2016. Universal Dependencies v1: A Multilingual Treebank Collection. In Proceedings of LREC.

Slav Petrov, Dipanjan Das, and Ryan McDonald. 2012. A universal part-of-speech tagset. In Proceedings of LREC.

Daniel Zeman. 2008. Reusable Tagset Conversion Using Tagset Drivers. In Proceedings of LREC.
EOF
    ;
    return $text;
}
