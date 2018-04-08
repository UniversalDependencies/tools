#!/usr/bin/env perl
# Checks files to be distributed as Universal Dependencies.
# Copyright © 2015, 2016, 2017, 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
use LWP::Simple;
# Dan's sorting library
use csort;
# If this script is called from the parent folder, how can it find the UD library?
use lib 'tools';
use udlib;

# Preliminary UD 2.2 release: only the training data of the shared task treebanks
# (but their test data will be frozen as well, they just won't be released yet).
# After we used this script to select the shared task treebanks automatically,
# we are now freezing the list, and we may even do manual adjustments, such as
# removing treebanks with unreliable lemmatization. From now on, the script will
# work only with treebanks that have been approved for the shared task.
###!!! Manually removed:
# UD_Russian-GSD
# UD_Spanish-GSD
# UD_Turkish-PUD
# Note: After some discussion with Giuseppe, UD_Latin-Perseus will be fixed but not removed.
# So we have 81 shared task treebanks: 63 large and 18 small.
my @stlarge = qw(UD_Afrikaans-AfriBooms UD_Ancient_Greek-PROIEL UD_Ancient_Greek-Perseus
UD_Arabic-PADT UD_Basque-BDT UD_Bulgarian-BTB UD_Catalan-AnCora UD_Chinese-GSD UD_Croatian-SET
UD_Czech-CAC UD_Czech-FicTree UD_Czech-PDT UD_Danish-DDT UD_Dutch-Alpino UD_Dutch-LassySmall
UD_English-EWT UD_English-GUM UD_English-LinES UD_Estonian-EDT UD_Faroese-OFT
UD_Finnish-FTB UD_Finnish-TDT
UD_French-GSD UD_French-Sequoia UD_French-Spoken UD_Galician-CTG UD_German-GSD UD_Gothic-PROIEL
UD_Greek-GDT UD_Hebrew-HTB UD_Hindi-HDTB UD_Hungarian-Szeged UD_Indonesian-GSD
UD_Italian-ISDT UD_Italian-PoSTWITA UD_Japanese-GSD UD_Korean-GSD UD_Latin-ITTB UD_Latin-PROIEL
UD_Latvian-LVTB UD_North_Sami-Giella UD_Norwegian-Bokmaal UD_Norwegian-Nynorsk
UD_Old_Church_Slavonic-PROIEL UD_Persian-Seraji UD_Polish-LFG UD_Polish-SZ UD_Portuguese-Bosque
UD_Romanian-RRT UD_Russian-SynTagRus UD_Russian-Taiga
UD_Serbian-SET UD_Slovak-SNK UD_Slovenian-SSJ UD_Slovenian-SST
UD_Spanish-AnCora UD_Swedish-LinES UD_Swedish-Talbanken
UD_Turkish-IMST UD_Ukrainian-IU UD_Urdu-UDTB UD_Uyghur-UDT UD_Vietnamese-VTB);
my @stsmall = qw(UD_Armenian-ArmTDP UD_Breton-KEB UD_Buryat-BDT UD_Czech-PUD
UD_English-PUD UD_Finnish-PUD UD_Galician-TreeGal UD_Irish-IDT UD_Japanese-Modern
UD_Kazakh-KTB UD_Kurmanji-MG UD_Latin-Perseus UD_Naija-NSC UD_Norwegian-NynorskLIA
UD_Old_French-SRCMF UD_Swedish-PUD UD_Thai-PUD UD_Upper_Sorbian-UFAL);
print('Pre-selected ', scalar(@stlarge), " large treebanks for the shared task.\n");
print('Pre-selected ', scalar(@stsmall), " small treebanks for the shared task.\n");
my %sthash;
foreach my $treebank (@stlarge, @stsmall)
{
    $sthash{$treebank}++;
}
print("WARNING: As a temporary measure, treebanks that do not take part in the shared task will be treated as INVALID.\n");

# Include reports on future repositories (not scheduled for the upcoming release)?
# (If there is no README file, we will include the repository in the report and complain about the missing README.)
my $include_future = 0;
# Pull the latest changes from Github and show git status of each repository?
my $pull = 0;
# Validate all CoNLL-U files and report invalid ones?
my $validate = 0;
# Recompute statistics of all treebanks and push them to Github?
my $recompute_stats = 0;
# Tag all repositories with the new release? (The $tag variable is either empty or it contains the tag.)
my $tag = ''; # example: 'r1.0'
# Number of the current release as it is found in README files. Repositories targeting a later release will not be included.
my $current_release = 2.2;
# Path to the previous release is needed to compare the number of sentences and words.
# zen:/net/data/universal-dependencies-1.2
# mekong:C:\Users\Dan\Documents\Lingvistika\Projekty\universal-dependencies\release-1.2
my $oldpath = '/net/data/universal-dependencies-2.1';
GetOptions
(
    'future'   => \$include_future,
    'pull'     => \$pull,
    'validate' => \$validate,
    'stats'    => \$recompute_stats,
    'tag=s'    => \$tag
);

# This script expects to be invoked in the folder in which all the UD_folders
# are placed.
opendir(DIR, '.') or die('Cannot read the contents of the working folder');
my @folders = sort(grep {-d $_ && m/^UD_[A-Z]/} (readdir(DIR)));
closedir(DIR);
# We need a mapping from the English names of the languages (as they appear in folder names) to their ISO codes and families.
my $languages_from_yaml = udlib::get_language_hash();
# Download the current validation report. (We could run the validator ourselves
# but it would take a lot of time.)
my @validation_report = split(/\n/, get('http://quest.ms.mff.cuni.cz/cgi-bin/zeman/unidep/validation-report.pl?text_only'));
if(scalar(@validation_report)==0)
{
    print STDERR ("WARNING: Could not download validation report from quest. All treebanks will be considered invalid.\n");
}
my %valid;
foreach my $line (@validation_report)
{
    if($line =~ m/^(UD_.+?):\s*VALID/)
    {
        ###!!! Temporary measure: treebank is not valid if it is not in the shared task.
        if(exists($sthash{$1}))
        {
            $valid{$1} = 1;
        }
    }
    # There are different requirements for treebanks that are released but are not in the CoNLL 2018 shared task.
    # The validation report also tells us which valid treebanks will not take part in the task.
    if($line =~ m/^(UD_.+?):.*not in shared task/)
    {
        $nist{$1} = 1;
    }
}
my $n_folders_with_data = 0;
my $n_folders_conll = 0;
my $n_errors = 0;
my %languages_with_data;
my %families_with_data;
my %languages_conll;
my %licenses;
my %genres;
my %contributors;
my %contacts;
my %stats;
my @unknown_folders; # cannot parse folder name or unknown language
my @nongit_folders; # folder is not a git repository
my @empty_folders; # does not contain data
my @future_folders; # scheduled for a future release (and we did not ask to include future data in the report)
my @invalid_folders; # at least one .conllu file does not pass validation
my @released_folders;
my @shared_task_large_folders; # train, dev and test exist, train is larger than either of the other two, test is at least 10K words, dev is at least 5K words
my @shared_task_small_folders; # no dev, train may be smaller than test, test at least 10K words
my @shared_task_other_folders; # outliers if any
foreach my $folder (@folders)
{
    # The name of the folder: 'UD_' + language name + optional treebank identifier.
    # Example: UD_Ancient_Greek-PROIEL
    my ($language, $treebank) = udlib::decompose_repo_name($folder);
    my $langcode;
    if(defined($language))
    {
        if(exists($languages_from_yaml->{$language}))
        {
            $langcode = $languages_from_yaml->{$language}{lcode};
            chdir($folder) or die("Cannot enter folder $folder");
            # Skip folders that are not Git repositories even if they otherwise look OK.
            if(!-d '.git')
            {
                push(@nongit_folders, $folder);
                chdir('..') or die("Cannot return to the upper folder");
                next;
            }
            # This is a git repository with data.
            # Make sure it is up-to-date.
            if($pull)
            {
                print("git pull $folder\n");
                system('git pull --tags');
                print(`git status`);
            }
            # Skip folders that do not contain any data, i.e. CoNLL-U files.
            opendir(DIR, '.') or die("Cannot read the contents of the folder $folder");
            my @files = readdir(DIR);
            my @conllufiles = grep {-f $_ && m/\.conllu$/} (@files);
            my $n = scalar(@conllufiles);
            if($n==0)
            {
                push(@empty_folders, $folder);
                chdir('..') or die("Cannot return to the upper folder");
                next;
            }
            if(!$valid{$folder})
            {
                push(@invalid_folders, $folder);
                chdir('..') or die("Cannot return to the upper folder");
                next;
            }
            # Read the README file. We need to know whether this repository is scheduled for the upcoming release.
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
            my $metadata = udlib::read_readme('.');
            if(!defined($metadata))
            {
                print("$folder: cannot read the README file: $!\n");
                $n_errors++;
            }
            if(exists($metadata->{firstrelease}) && $metadata->{firstrelease} <= $current_release)
            {
                $metadata->{release} = 1;
            }
            if(!$metadata->{release} && !$include_future)
            {
                push(@future_folders, $folder);
                chdir('..') or die("Cannot return to the upper folder");
                next;
            }
            # If we are here, we know that this folder is going to be released.
            # Count it and check it for possible problems.
            $n_folders_with_data++;
            push(@released_folders, $folder);
            $languages_with_data{$language}++;
            my $family = $languages_from_yaml->{$language}{family};
            if(defined($family))
            {
                $family =~ s/^IE/Indo-European/;
                # Keep only the family, discard the genus if present.
                $family =~ s/,.*//;
                $families_with_data{$family}++;
            }
            my $is_in_shared_task = 0;
            unless($nist{$folder})
            {
                $is_in_shared_task = 1;
            }
            if($metadata->{'Data available since'} =~ m/UD\s*v([0-9]+\.[0-9]+)/ && $1 < $current_release && !$metadata->{changelog})
            {
                print("$folder: Old treebank ($metadata->{'Data available since'}) but README does not contain 'ChangeLog'\n");
                $n_errors++;
            }
            # Check that all required metadata items are present in the README file.
            # New contributors sometimes forget to add it. Old contributors sometimes modify it for no good reason ('Data available since' should never change!)
            # And occasionally people delete the metadata section completely, despite being told not to do so (Hebrew team in the last minute of UD 2.0!)
            if($metadata->{'Data available since'} !~ m/UD\s*v([0-9]+\.[0-9]+)/)
            {
                print("$folder: Unknown format of Data available since: '$metadata->{'Data available since'}'\n");
                $n_errors++;
            }
            if($metadata->{Genre} !~ m/\w/)
            {
                print("$folder: Missing list of genres: '$metadata->{Genre}'\n");
                $n_errors++;
            }
            if($metadata->{License} !~ m/\w/)
            {
                print("$folder: Missing identification of license in README: '$metadata->{License}'\n");
                $n_errors++;
            }
            if($metadata->{Contributors} !~ m/\w/)
            {
                print("$folder: Missing list of contributors: '$metadata->{Contributors}'\n");
                $n_errors++;
            }
            if($metadata->{Contact} !~ m/\@/)
            {
                print("$folder: Missing contact e-mail: '$metadata->{Contact}'\n");
                $n_errors++;
            }
            ###!!! Since UD 2.1 we allow that a treebank has only the test file.
            ###!!! But maybe we should require that there is training, dev and test if the total size is 30,000 words or more.
            #my $expected_n = ($language eq 'Czech' && $treebank eq '') ? 6 : 3;
            #unless($n==$expected_n)
            #{
            #    print("$folder: expected $expected_n CoNLL-U files, found $n\n");
            #    $n_errors++;
            #}
            if(!-f 'LICENSE.txt')
            {
                print("$folder: missing LICENSE.txt (README says license is '$metadata->{License}')\n");
                generate_license($metadata->{License});
                $n_errors++;
            }
            # Check the names and sizes of the data files.
            my $key = $langcode;
            $key .= '_'.lc($treebank) if($treebank ne '');
            my $prefix = $key.'-ud';
            my $nwtrain = 0;
            my $nwdev = 0;
            my $nwtest = 0;
            # In general, every treebank should have at least the test data.
            # If there are more data files, zero or one of each of the following is expected: train, dev.
            # Exception: Czech has four train files: train-c, train-l, train-m, train-v.
            # No other CoNLL-U files are expected.
            # It is also expected that if there is dev, there is also train.
            # And if there is train, it should be same size or larger (in words) than both dev and test.
            if($folder eq 'UD_Czech-PDT')
            {
                # The data is split into four files because of the size limits.
                if(!-f "$prefix-train-c.conllu" || !-f "$prefix-train-l.conllu" || !-f "$prefix-train-m.conllu" || !-f "$prefix-train-v.conllu")
                {
                        print("$folder: missing at least one file of $prefix-train-[clmv].conllu\n");
                        $n_errors++;
                }
                my $stats = collect_statistics_about_ud_file("$prefix-train-c.conllu");
                $nwtrain = $stats->{nword};
                $stats = collect_statistics_about_ud_file("$prefix-train-l.conllu");
                $nwtrain += $stats->{nword};
                $stats = collect_statistics_about_ud_file("$prefix-train-m.conllu");
                $nwtrain += $stats->{nword};
                $stats = collect_statistics_about_ud_file("$prefix-train-v.conllu");
                $nwtrain += $stats->{nword};
            }
            else # all other treebanks
            {
                if(-f "$prefix-train.conllu")
                {
                    my $stats = collect_statistics_about_ud_file("$prefix-train.conllu");
                    $nwtrain = $stats->{nword};
                    # If required, check that the file is valid.
                    if($validate && !is_valid_conllu("$prefix-train.conllu", $key))
                    {
                        print("$folder: invalid file $prefix-train.conllu\n");
                        $n_errors++;
                    }
                }
            }
            # Look for development data.
            if(-f "$prefix-dev.conllu")
            {
                my $stats = collect_statistics_about_ud_file("$prefix-dev.conllu");
                $nwdev = $stats->{nword};
                # If required, check that the file is valid.
                if($validate && !is_valid_conllu("$prefix-dev.conllu", $key))
                {
                    print("$folder: invalid file $prefix-dev.conllu\n");
                    $n_errors++;
                }
            }
            # Look for test data.
            if(-f "$prefix-test.conllu")
            {
                my $stats = collect_statistics_about_ud_file("$prefix-test.conllu");
                $nwtest = $stats->{nword};
                # If required, check that the file is valid.
                if($validate && !is_valid_conllu("$prefix-test.conllu", $key))
                {
                    print("$folder: invalid file $prefix-test.conllu\n");
                    $n_errors++;
                }
            }
            # For small and growing treebanks, we expect the files to appear roughly in the following order:
            # 1. test (>=10K tokens if possible); 2. train (if it can be larger than test or if this is the only treebank of the language and train is a small sample); 3. dev (if it can be at least 10K tokens and if train is larger than both test and dev).
            if($nwtest==0 && ($nwtrain>0 || $nwdev>0))
            {
                print("$folder: train or dev exists but there is no test\n");
                $n_errors++;
            }
            # Exception: PUD parallel data are currently test only, even if in some languages there is more than 20K words.
            # Exception: ParTUT can have very small dev data. There are other limitations (sync across languages and with UD_Italian)
            my $nwall = $nwtrain+$nwdev+$nwtest;
            if($nwall>10000 && $nwtest<10000)
            {
                print("$folder: more than 10K words (precisely: $nwall) available but test has only $nwtest words\n");
                $n_errors++;
            }
            if($nwall>20000 && $nwtrain<10000 && $folder !~ m/-(PUD|ParTUT)$/)
            {
                print("$folder: more than 20K words (precisely: $nwall) available but train has only $nwtrain words\n");
                $n_errors++;
            }
            if($nwall>30000 && $nwdev<5000 && $folder !~ m/-(PUD|ParTUT)$/)
            {
                print("$folder: more than 30K words (precisely: $nwall) available but dev has only $nwdev words\n");
                $n_errors++;
            }
            # Classify shared task treebanks by their size.
            if($is_in_shared_task)
            {
                $n_folders_conll++;
                $languages_conll{$language}++;
                # Large: it has train, dev and test, train is larger than each of the other two, dev is at least 5K words, test is at least 10K words.
                # Small: it does not have dev, train is at least 5K words, test is at least 10K words.
                # Extra test: it has only test, at least 10K words. There is another treebank of the same language, and the other treebank is large.
                # Low resource: no dev, train zero or a tiny sample, test at least 10K words, and this is the only treebank of the language.
                # Other: are there treebanks that do not fit in any of the above categories?
                if($nwtrain>$nwdev && $nwtrain>$nwtest && $nwdev>=5000 && $nwtest>=10000)
                {
                    push(@shared_task_large_folders, $folder);
                }
                elsif($nwtrain>=5000 && $nwdev==0 && $nwtest>=10000)
                {
                    push(@shared_task_small_folders, $folder);
                }
                else # We do not expect any treebanks that fall here.
                {
                    push(@shared_task_other_folders, $folder);
                }
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
                !m/^(\.\.?|\.git(ignore)?|not-to-release|README\.(txt|md)|LICENSE\.txt|$prefix-(train|dev|test)\.conllu|cs_pdt-ud-train-[clmv]\.conllu|stats\.xml)$/
            }
            (@files);
            # Some treebanks have exceptional extra files that have been approved and released previously.
            @extrafiles = grep
            {!(
                $folder eq 'UD_Arabic-NYUAD' && $_ eq 'merge.jar' ||
                $folder eq 'UD_Bulgarian' && $_ eq 'BTB-biblio.bib' ||
                $folder eq 'UD_Chinese-CFL' && $_ eq 'zh_cfl-ud-test.conllux' ||
                $folder eq 'UD_Finnish-FTB' && $_ =~ m/^COPYING(\.LESSER)?$/
            )}
            (@extrafiles);
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
            if($metadata->{'Contact'} ne '')
            {
                my @contacts = split(/[,;]\s*/, $metadata->{'Contact'});
                foreach my $contact (@contacts)
                {
                    $contact =~ s/^\s+//;
                    $contact =~ s/\s+$//;
                    $contacts{$contact}++;
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
            closedir(DIR);
            chdir('..') or die("Cannot return to the upper folder");
        }
        else
        {
            print("Unknown language $language.\n");
            push(@unknown_folders, $folder);
        }
    }
    else
    {
        print("Cannot parse folder name $folder.\n");
        push(@unknown_folders, $folder);
    }
}
print("$n_errors errors must be fixed.\n") if($n_errors>0);
print("\n");
print("Found ", scalar(@folders), " folders.\n");
if(scalar(@unknown_folders) > 0)
{
    print(scalar(@unknown_folders), " folders skipped because their language cannot be identified: ", join(', ', @unknown_folders), "\n");
}
if(scalar(@nongit_folders) > 0)
{
    print(scalar(@nongit_folders), " folders ignored because they are not git repositories: ", join(', ', @nongit_folders), "\n");
}
if(scalar(@empty_folders) > 0)
{
    print(scalar(@empty_folders), " folders ignored because they are empty: ", join(', ', @empty_folders), "\n");
}
if(scalar(@future_folders) > 0)
{
    print(scalar(@future_folders), " folders ignored because their README says they should be released later: ", join(', ', @future_folders), "\n");
}
if(scalar(@invalid_folders) > 0)
{
    print(scalar(@invalid_folders), " folders ignored because at least one file does not pass validation: ", join(', ', @invalid_folders), "\n");
}
# Do not separate names of released folders by commas. We will want to copy the list as arguments for the packaging script.
print("$n_folders_with_data folders are git repositories and contain valid data:\n\n", join(' ', @released_folders), "\n\n");
print("$n_folders_conll of those will take part in the CoNLL shared task.\n");
my $n_shared_task_large = scalar(@shared_task_large_folders);
my $n_shared_task_small = scalar(@shared_task_small_folders);
my $n_shared_task_other = scalar(@shared_task_other_folders);
print("$n_shared_task_large of them are considered large and will have separate training and development data in the shared task:\n\n", join(' ', @shared_task_large_folders), "\n\n");
print("$n_shared_task_small of them are considered small; they have training data but not development data:\n\n", join(' ', @shared_task_small_folders), "\n\n");
print("$n_shared_task_other of them do not meet conditions of either large or small shared task treebanks:\n\n", join(' ', @shared_task_other_folders), "\n\n");
my @families = sort(keys(%families_with_data));
print(scalar(@families), " families with data: ", join(', ', @families), "\n\n");
my @languages = map {s/_/ /g; $_} (sort(keys(%languages_with_data)));
print(scalar(@languages), " languages with data: ", join(', ', @languages), "\n\n");
my @languages_conll = map {s/_/ /g; $_} (sort(keys(%languages_conll)));
print(scalar(@languages_conll), " languages in the shared task: ", join(', ', @languages_conll), "\n\n");
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
my @contacts = sort(keys(%contacts));
print(scalar(@contacts), " contacts: ", join(', ', @contacts), "\n\n");
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
my $announcement = get_announcement
(
    $current_release,
    $n_folders_with_data,
    \@languages,
    \@families,
    'less than 1,000 tokens',
    'well over 1.5 million tokens',
    'November 2018', # expected next release
    \@contributors_firstlast,
    # Temporary for UD 2.0: shared task information
    $n_folders_conll,
    \@languages_conll
);
print($announcement);



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
        # The name of the folder: 'UD_' + language name + treebank identifier.
        # Example: UD_Ancient_Greek-PROIEL
        my ($language, $treebank) = udlib::decompose_repo_name($folder);
        my $langcode;
        if(-d "$release_path/$folder" && defined($language))
        {
            if(exists($languages_from_yaml->{$language}))
            {
                $langcode = $languages_from_yaml->{$language}{lcode};
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
        my $stats = collect_statistics_about_ud_file("$treebank_path/$file");
        $nsent += $stats->{nsent};
        $ntok += $stats->{ntok};
        $nfus += $stats->{nfus};
        $nword += $stats->{nword};
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
# Counts the number of tokens in a .conllu file.
#------------------------------------------------------------------------------
sub collect_statistics_about_ud_file
{
    my $file_path = shift;
    my $nsent = 0;
    my $ntok = 0;
    my $nfus = 0;
    my $nword = 0;
    open(CONLLU, $file_path) or die("Cannot read file $file_path: $!");
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
    my $famlistref = shift;
    my $min_size = shift; # 'about 9,000 tokens'
    my $max_size = shift; # 'well over 1.5 million tokens'
    my $next_release_available_in = shift; # 'March 2017'
    my $contlistref = shift;
    my $n_conll = shift;
    my $langlistconllref = shift;
    my @release_list   =   (1.0,  1.1,   1.2,  1.3,   1.4,  2.0,  2.1,    2.2,   2.3,  2.4,  2.5,     2.6,    2.7,       2.8,       2.9,      2.10,     2.11,       2.12,      2.13,      2.14);
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
    my @families = @{$famlistref};
    my $n_families = scalar(@families);
    my $families = join(', ', @families);
    $families =~ s/, ([^,]+)$/ and $1/;
    my @languages_conll = @{$langlistconllref};
    my $n_languages_conll = scalar(@languages_conll);
    my $languages_conll = join(', ', @languages_conll);
    $languages_conll =~ s/, ([^,]+)$/ and $1/;
    my @contributors = @{$contlistref};
    my $contributors = join(', ', @contributors);
    # Extra text in 2.0 announcement, removed for 2.1 but kept commented for 2.2
    #This release is special in that the treebanks will be used as training/development data in the CoNLL 2017 shared task (http://universaldependencies.org/conll17/). Test data are not released, except for the few treebanks that do not take part in the shared task. $n_conll treebanks will be in the shared task, and they correspond to the following $n_languages_conll languages: $languages_conll. Registration of shared task participants is still open!
    #
    #REMINDER: ADD ANNOUNCEMENT ABOUT THE RAW DATA, AND ABOUT THE BASELINE MODELS (UDPIPE + SYNTAXNET) WE WANT TO PUBLISH AROUND MID MARCH.
    #BESIDES THE USUAL MAILING LISTS, SEND THIS ANNOUNCEMENT ALSO DIRECTLY TO ALL THE REGISTERED PARTICIPANTS.
    my $text = <<EOF
We are very happy to announce the $nth release of annotated treebanks in Universal Dependencies, v$release, available at http://universaldependencies.org/.

Universal Dependencies is a project that seeks to develop cross-linguistically consistent treebank annotation for many languages with the goal of facilitating multilingual parser development, cross-lingual learning, and parsing research from a language typology perspective (Nivre et al., 2016). The annotation scheme is based on (universal) Stanford dependencies (de Marneffe et al., 2006, 2008, 2014), Google universal part-of-speech tags (Petrov et al., 2012), and the Interset interlingua for morphosyntactic tagsets (Zeman, 2008). The general philosophy is to provide a universal inventory of categories and guidelines to facilitate consistent annotation of similar constructions across languages, while allowing language-specific extensions when necessary.

The $n_treebanks treebanks in v$release are annotated according to version $guidelines_version of the UD guidelines and represent the following $n_languages languages: $languages. The $n_languages languages belong to $n_families families: $families. Depending on the language, the treebanks range in size from $min_size to $max_size. We expect the next release to be available in $next_release_available_in.

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



#------------------------------------------------------------------------------
# Runs the external validator on a CoNLL-U file. Returns 1 when the file passes
# the validation, 0 otherwise.
#------------------------------------------------------------------------------
sub is_valid_conllu
{
    my $path = shift;
    my $lcode = shift;
    # This script is always run from the main UD folder.
    # But it steps in the individual repositories and back up again; this function does not know where the tools are.
    system("validate.py $path --lang $lcode >/dev/null 2>&1");
    # The external program does not exist, is not executable or the execution failed for other reasons.
    die("ERROR: Failed to execute validate.py: $!") if($?==-1);
    # We were able to start the external program but its execution failed.
    if($? & 127)
    {
        printf STDERR ("ERROR: Execution of validate.py\n  died with signal %d, %s coredump\n",
            ($? & 127), ($? & 128) ? 'with' : 'without');
        die;
    }
    else
    {
        my $exitcode = $? >> 8;
        # Exit code 0 means successful validation. Nonzero means an error.
        print STDERR ("Exit code: $exitcode\n") if($exitcode);
        return ! $exitcode;
    }
    # We should never arrive here.
}
