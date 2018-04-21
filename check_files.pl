#!/usr/bin/env perl
# Checks files to be distributed as Universal Dependencies.
# Copyright © 2015, 2016, 2017, 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

sub usage
{
    print STDERR ("Usage: tools/check_files.pl\n");
    print STDERR ("       Must be called from the folder where all UD repositories are cloned as subfolders.\n");
    print STDERR ("       Will produce a complete report for the next UD release.\n");
    print STDERR ("\n");
    print STDERR ("   or: tools/check_files.pl UD_Ancient_Greek-PROIEL\n");
    print STDERR ("       Will just check files and metadata of one treebank, report errors and exit.\n");
}

use Getopt::Long;
use LWP::Simple;
# Dan's sorting library
use csort;
# If this script is called from the parent folder, how can it find the UD library?
use lib 'tools';
use udlib;

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

# We need a mapping from the English names of the languages (as they appear in folder names) to their ISO codes and families.
my $languages_from_yaml = udlib::get_language_hash();

# If there is one argument, we interpret it as a treebank name, check the files
# and metadata of that treebank, and exit. We should check the arguments after
# options were read, although we do not expect options if the script is called
# on one treebank.
if(scalar(@ARGV)==1)
{
    my $folder = $ARGV[0];
    $folder =~ s:/$::;
    my $n_errors = 0;
    my @errors;
    # The name of the folder: 'UD_' + language name + optional treebank identifier.
    # Example: UD_Ancient_Greek-PROIEL
    my ($language, $treebank) = udlib::decompose_repo_name($folder);
    if(defined($language))
    {
        if(exists($languages_from_yaml->{$language}))
        {
            $langcode = $languages_from_yaml->{$language}{lcode};
            my $key = $langcode;
            $key .= '_'.lc($treebank) if($treebank ne '');
            my $prefix = $key.'-ud';
            chdir($folder) or die("Cannot enter folder $folder");
            my $files = get_files($folder, $prefix, '.');
            # Check that the expected files are present and that there are no extra files.
            check_files($folder, $prefix, $files, \@errors, \$n_errors);
            # Read the README file. We need to know whether this repository is scheduled for the upcoming release.
            my $metadata = udlib::read_readme('.');
            if(!defined($metadata))
            {
                push(@errors, "$folder: cannot read the README file: $!\n");
                $n_errors++;
            }
            # Check that all required metadata items are present in the README file.
            check_metadata($folder, $metadata, $current_release, \@errors, \$n_errors);
            chdir('..') or die("Cannot return to the upper folder");
        }
        else
        {
            push(@errors, "Unknown language $language.\n");
            $n_errors++;
        }
    }
    else
    {
        push(@errors, "Cannot parse folder name $folder.\n");
        $n_errors++;
    }
    if($n_errors>0)
    {
        print(join('', @errors));
        print("*** FAILED ***\n");
    }
    else
    {
        # Output similar to the validator.
        print("*** PASSED ***\n");
    }
    # Exit 0 is considered success by the operating system.
    exit($n_errors);
}

# This script expects to be invoked in the folder in which all the UD_folders
# are placed.
opendir(DIR, '.') or die('Cannot read the contents of the working folder');
my @folders = sort(grep {-d $_ && m/^UD_[A-Z]/} (readdir(DIR)));
closedir(DIR);
my ($validhash, $nisthash) = get_validation_results();
my %valid = %{$validhash};
my %nist = %{$nisthash};
my $n_folders_with_data = 0;
my $n_errors = 0;
my %languages_with_data;
my %families_with_data;
my %licenses;
my %genres;
my %contributors;
my %contacts;
my %stats;
my %nw; # number of words in train|dev|test|all; indexed by folder name
my @unknown_folders; # cannot parse folder name or unknown language
my @nongit_folders; # folder is not a git repository
my @empty_folders; # does not contain data
my @future_folders; # scheduled for a future release (and we did not ask to include future data in the report)
my @invalid_folders; # at least one .conllu file does not pass validation
my @released_folders;
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
            my $key = $langcode;
            $key .= '_'.lc($treebank) if($treebank ne '');
            my $prefix = $key.'-ud';
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
            my $files = get_files($folder, $prefix, '.');
            my $n = scalar(@{$files->{conllu}});
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
            # Check that the expected files are present and that there are no extra files.
            my @errors;
            if(!check_files($folder, $prefix, $files, \@errors, \$n_errors))
            {
                print(join('', @errors));
                splice(@errors);
            }
            # Read the README file. We need to know whether this repository is scheduled for the upcoming release.
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
            #------------------------------------------------------------------
            # End of skipping. If we are here, we have a versioned UD folder
            # with valid data. We know that the folder is going to be released.
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
            # Check that all required metadata items are present in the README file.
            if(!check_metadata($folder, $metadata, $current_release, \@errors, \$n_errors))
            {
                print(join('', @errors));
                splice(@errors);
            }
            if(!-f 'LICENSE.txt') ###!!! We have already reported that the file does not exist but that was a function where README contents is not known and no generating attempt was made.
            {
                print("$folder: missing LICENSE.txt (README says license is '$metadata->{License}')\n");
                generate_license($metadata->{License});
                $n_errors++;
            }
            # Check the names and sizes of the data files.
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
            # Remember the numbers of words. We will need them for some tests
            # that can only be done when all folders have been scanned.
            my $nwall = $nwtrain+$nwdev+$nwtest;
            $nw{$folder} = { 'train' => $nwtrain, 'dev' => $nwdev, 'test' => $nwtest, 'all' => $nwall };
            # For small and growing treebanks, we expect the files to appear roughly in the following order:
            # 1. test (>=10K tokens if possible); 2. train (if it can be larger than test or if this is the only treebank of the language and train is a small sample); 3. dev (if it can be at least 10K tokens and if train is larger than both test and dev).
            if($nwtest==0 && ($nwtrain>0 || $nwdev>0))
            {
                print("$folder: train or dev exists but there is no test\n");
                $n_errors++;
            }
            # Exception: PUD parallel data are currently test only, even if in some languages there is more than 20K words.
            # Exception: ParTUT can have very small dev data. There are other limitations (sync across languages and with UD_Italian)
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
            $stats{$key} = collect_statistics_about_ud_treebank('.', $key);
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
# Classify shared task treebanks by their size. We cannot do this before we
# have scanned all treebanks because one category depends on whether there are
# larger treebanks of the same language.
my $n_folders_conll = 0;
my %languages_conll;
my %languages_conll_large;
my @shared_task_large_folders; # train, dev and test exist, train is larger than either of the other two, test is at least 10K words, dev is at least 5K words
my @shared_task_small_folders; # no dev, train may be smaller than test, test at least 10K words
my @shared_task_extra_folders; # no train, no dev, test at least 10K words, the language has another large treebank
my @shared_task_lorsc_folders; # small or no train, no dev, test at least 10K words, no other large treebank of the language
my @shared_task_other_folders; # outliers if any
foreach my $folder (sort(keys(%nw)))
{
    my ($language, $treebank) = udlib::decompose_repo_name($folder);
    my ($nwtrain, $nwdev, $nwtest, $nwall) = ($nw{$folder}{train}, $nw{$folder}{dev}, $nw{$folder}{test}, $nw{$folder}{all});
    # Only count treebanks that are in the shared task.
    unless($nist{$folder})
    {
        $n_folders_conll++;
        $languages_conll{$language}++;
        # Remember languages that have at least one large treebank. It will
        # influence classification of test-only treebanks of the same language.
        if($nwtrain>$nwdev && $nwtrain>$nwtest && $nwdev>=5000 && $nwtest>=10000)
        {
            $languages_conll_large{$language}++;
        }
    }
}
foreach my $folder (sort(keys(%nw)))
{
    my ($language, $treebank) = udlib::decompose_repo_name($folder);
    my ($nwtrain, $nwdev, $nwtest, $nwall) = ($nw{$folder}{train}, $nw{$folder}{dev}, $nw{$folder}{test}, $nw{$folder}{all});
    # Only count treebanks that are in the shared task.
    unless($nist{$folder})
    {
        # Large: it has train, dev and test, train is larger than each of the other two, dev is at least 5K words, test is at least 10K words.
        # Small: it does not have dev, train is at least 3K words, test is at least 10K words.
        # Extra test: it has only test, at least 10K words. There is another treebank of the same language, and the other treebank is large.
        # Low resource: no dev, train zero or a tiny sample, test at least 10K words, and this is the only treebank of the language.
        # Other: are there treebanks that do not fit in any of the above categories?
        if($nwtrain>$nwdev && $nwtrain>$nwtest && $nwdev>=5000 && $nwtest>=10000)
        {
            push(@shared_task_large_folders, $folder);
        }
        elsif($nwtrain>=3000 && $nwdev==0 && $nwtest>=10000)
        {
            push(@shared_task_small_folders, $folder);
        }
        elsif($nwtrain==0 && $nwdev==0 && $nwtest>=10000 && $languages_conll_large{$language})
        {
            push(@shared_task_extra_folders, $folder);
        }
        elsif($nwtrain<5000 && $nwdev==0 && $nwtest>=10000 && !exists($languages_conll_large{$language}))
        {
            push(@shared_task_lorsc_folders, $folder);
        }
        else # We do not expect any treebanks that fall here.
        {
            push(@shared_task_other_folders, $folder);
        }
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
my $n_shared_task_extra = scalar(@shared_task_extra_folders);
my $n_shared_task_lorsc = scalar(@shared_task_lorsc_folders);
my $n_shared_task_other = scalar(@shared_task_other_folders);
print("$n_shared_task_large of them are considered large and will have separate training and development data in the shared task:\n\n", join(' ', @shared_task_large_folders), "\n\n");
print("$n_shared_task_small of them are considered small; they have training data but not development data:\n\n", join(' ', @shared_task_small_folders), "\n\n");
print("$n_shared_task_extra of them are extra test sets in languages where another large treebank exists:\n\n", join(' ', @shared_task_extra_folders), "\n\n");
print("$n_shared_task_lorsc of them are low-resource languages; they have no training data or just a tiny sample:\n\n", join(' ', @shared_task_lorsc_folders), "\n\n");
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
# Downloads the current validation report from the validation server. Returns
# two hash references: to the hash of valid treebanks, and to the hash of
# treebanks that are not in the shared task despite being valid.
#------------------------------------------------------------------------------
sub get_validation_results
{
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
    my @stpresel = qw(
    UD_Afrikaans-AfriBooms UD_Ancient_Greek-PROIEL UD_Ancient_Greek-Perseus
    UD_Arabic-PADT UD_Armenian-ArmTDP
    UD_Basque-BDT UD_Breton-KEB UD_Bulgarian-BTB UD_Buryat-BDT
    UD_Catalan-AnCora UD_Chinese-GSD UD_Croatian-SET
    UD_Czech-CAC UD_Czech-FicTree UD_Czech-PDT UD_Czech-PUD
    UD_Danish-DDT UD_Dutch-Alpino UD_Dutch-LassySmall
    UD_English-EWT UD_English-GUM UD_English-LinES UD_English-PUD
    UD_Estonian-EDT
    UD_Faroese-OFT UD_Finnish-FTB UD_Finnish-PUD UD_Finnish-TDT
    UD_French-GSD UD_French-Sequoia UD_French-Spoken
    UD_Galician-CTG UD_Galician-TreeGal
    UD_German-GSD UD_Gothic-PROIEL UD_Greek-GDT
    UD_Hebrew-HTB UD_Hindi-HDTB UD_Hungarian-Szeged
    UD_Indonesian-GSD UD_Irish-IDT UD_Italian-ISDT UD_Italian-PoSTWITA
    UD_Japanese-GSD UD_Japanese-Modern
    UD_Kazakh-KTB UD_Korean-GSD UD_Korean-Kaist UD_Kurmanji-MG
    UD_Latin-ITTB UD_Latin-PROIEL UD_Latin-Perseus UD_Latvian-LVTB
    UD_Naija-NSC UD_North_Sami-Giella
    UD_Norwegian-Bokmaal UD_Norwegian-Nynorsk UD_Norwegian-NynorskLIA
    UD_Old_Church_Slavonic-PROIEL UD_Old_French-SRCMF UD_Persian-Seraji
    UD_Polish-LFG UD_Polish-SZ UD_Portuguese-Bosque UD_Romanian-RRT
    UD_Russian-SynTagRus UD_Russian-Taiga UD_Serbian-SET UD_Slovak-SNK
    UD_Slovenian-SSJ UD_Slovenian-SST UD_Spanish-AnCora
    UD_Swedish-LinES UD_Swedish-PUD UD_Swedish-Talbanken
    UD_Thai-PUD UD_Turkish-IMST
    UD_Ukrainian-IU UD_Upper_Sorbian-UFAL UD_Urdu-UDTB UD_Uyghur-UDT UD_Vietnamese-VTB);
    print('Pre-selected ', scalar(@stpresel), " treebanks for the shared task.\n");
    my %sthash;
    foreach my $treebank (@stpresel)
    {
        $sthash{$treebank}++;
    }
    print("WARNING: As a temporary measure, treebanks that do not take part in the shared task will be treated as INVALID.\n");
    # Download the current validation report. (We could run the validator ourselves
    # but it would take a lot of time.)
    my @validation_report = split(/\n/, get('http://quest.ms.mff.cuni.cz/cgi-bin/zeman/unidep/validation-report.pl?text_only'));
    if(scalar(@validation_report)==0)
    {
        print STDERR ("WARNING: Could not download validation report from quest. All treebanks will be considered invalid.\n");
    }
    my %valid;
    my %nist;
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
    return (\%valid, \%nist);
}



#------------------------------------------------------------------------------
# Gets the list of files in a UD folder. Returns the list of CoNLL-U files, and
# the list of unexpected extra files.
#------------------------------------------------------------------------------
sub get_files
{
    my $folder = shift; # name of the UD repository
    my $prefix = shift; # prefix of data files, i.e., language code _ treebank code
    my $path = shift; # path to the repository (default: '.')
    $path = '.' if(!defined($path));
    opendir(DIR, $path) or die("Cannot read the contents of the folder $folder");
    my @files = readdir(DIR);
    closedir(DIR);
    my @conllufiles = grep {-f $_ && m/\.conllu$/} (@files);
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
    # The treebanks without underlying text need a program that merges the CoNLL-U files with the separately distributed text.
    # Learner corpora need extra columns to annotate "distributional tag", "distributional head", "distributional relation" and "alignment".
    ###!!! But we now have guidelines for extra columns from the PARSEME project, so there will be a CoNLL-U-Plus format, .conllup.
    @extrafiles = grep
    {!(
        $folder eq 'UD_Arabic-NYUAD' && $_ eq 'merge.jar' ||
#        $folder eq 'UD_Bulgarian-BTB' && $_ eq 'BTB-biblio.bib' ||
        $folder eq 'UD_Chinese-CFL' && $_ eq 'zh_cfl-ud-test.conllux' #||
#        $folder eq 'UD_Finnish-FTB' && $_ =~ m/^COPYING(\.LESSER)?$/
    )}
    (@extrafiles);
    my %files =
    (
        'conllu' => \@conllufiles,
        'extra'  => \@extrafiles
    );
    return \%files;
}



#------------------------------------------------------------------------------
# Checks whether a UD repository contains the expected files. Expects that the
# repository is our current folder.
#------------------------------------------------------------------------------
sub check_files
{
    my $folder = shift; # folder name, e.g. 'UD_Czech-PDT', not path
    my $prefix = shift; # prefix of names of data files, e.g. 'cs_pdt-ud'
    my $files = shift; # hash of files in the folder as collected by get_files()
    my $errors = shift; # reference to array of error messages
    my $n_errors = shift; # reference to error counter
    my $ok = 1;
    if(!-f 'README.txt' && !-f 'README.md')
    {
        $ok = 0;
        push(@{$errors}, "$folder: missing README.txt|md\n");
        $$n_errors++;
    }
    if(-f 'README.txt' && -f 'README.md')
    {
        $ok = 0;
        push(@{$errors}, "$folder: both README.txt and README.md are present\n");
        $$n_errors++;
    }
    if(!-f 'LICENSE.txt')
    {
        $ok = 0;
        push(@{$errors}, "$folder: missing LICENSE.txt\n");
        $$n_errors++;
    }
    # Check the data files.
    my $train_found = 0;
    # In general, every treebank should have at least the test data.
    # If there are more data files, zero or one of each of the following is expected: train, dev.
    # Exception: Czech PDT has four train files: train-c, train-l, train-m, train-v.
    # No other CoNLL-U files are expected.
    # It is also expected that if there is dev, there is also train.
    if($folder eq 'UD_Czech-PDT')
    {
        # The data is split into four files because of the size limits.
        if(!-f "$prefix-train-c.conllu" || !-f "$prefix-train-l.conllu" || !-f "$prefix-train-m.conllu" || !-f "$prefix-train-v.conllu")
        {
            $ok = 0;
            push(@{$errors}, "$folder: missing at least one file of $prefix-train-[clmv].conllu\n");
            $$n_errors++;
        }
        else
        {
            $train_found = 1;
        }
    }
    else # all other treebanks
    {
        if(-f "$prefix-train.conllu")
        {
            # Not finding train is not automatically an error. The treebank can be test-only.
            $train_found = 1;
        }
    }
    # Look for development data. They are optional and not finding them is not an error.
    if(-f "$prefix-dev.conllu")
    {
        # However, if there is dev data, there should also be training data!
        if(!$train_found)
        {
            $ok = 0;
            push(@{$errors}, "$folder: missing training data although there is dev data\n");
            $$n_errors++;
        }
    }
    # Look for test data. Unlike train and dev, test data is mandatory!
    if(!-f "$prefix-test.conllu")
    {
        $ok = 0;
        push(@{$errors}, "$folder: missing test data file $prefix-test.conllu\n");
        $$n_errors++;
    }
    # Extra files have already been identified but not registered as an error.
    if(scalar(@{$files->{extra}})>0)
    {
        $ok = 0;
        push(@{$errors}, "$folder extra files: ".join(', ', sort(@{$files->{extra}}))."\n");
        $$n_errors += scalar(@{$files->{extra}});
    }
    return $ok;
}



#------------------------------------------------------------------------------
# Checks whether metadata in the README file provides required information.
#------------------------------------------------------------------------------
sub check_metadata
{
    my $folder = shift; # folder name, e.g. 'UD_Czech-PDT', not path
    my $metadata = shift; # reference to hash returned by udlib::read_readme()
    my $current_release = shift; # needed to know whether changelog is required
    my $errors = shift; # reference to array of error messages
    my $n_errors = shift; # reference to error counter
    my $ok = 1;
    # New contributors sometimes forget to add it. Old contributors sometimes modify it for no good reason ('Data available since' should never change!)
    # And occasionally people delete the metadata section completely, despite being told not to do so (Hebrew team in the last minute of UD 2.0!)
    if($metadata->{'Data available since'} =~ m/UD\s*v([0-9]+\.[0-9]+)/)
    {
        my $claimed = $1;
        # The value 'Data available since' must not change from release to release.
        # It must forever refer to the first release of the treebank in UD.
        # Therefore, this script will remember the correct value, too, and shout if it changes in the README.
        my %new_treebanks_by_release =
        (
            '1.0' => ['Czech-PDT', 'English-EWT', 'Finnish-TDT', 'French-GSD', 'German-GSD', 'Hungarian-Szeged', 'Irish-IDT', 'Italian-ISDT', 'Spanish-GSD', 'Swedish-Talbanken'],
            '1.1' => ['Basque-BDT', 'Bulgarian-BTB', 'Croatian-SET', 'Danish-DDT', 'Finnish-FTB', 'Greek-GDT', 'Hebrew-HTB', 'Indonesian-GSD', 'Persian-Seraji'],
            '1.2' => ['Ancient_Greek-Perseus', 'Ancient_Greek-PROIEL', 'Arabic-PADT', 'Dutch-Alpino', 'Estonian-EDT', 'Gothic-PROIEL', 'Hindi-HDTB', 'Japanese-KTC', 'Latin-ITTB', 'Latin-Perseus', 'Latin-PROIEL', 'Norwegian-Bokmaal', 'Old_Church_Slavonic-PROIEL', 'Polish-SZ', 'Portuguese-Bosque', 'Romanian-RRT', 'Slovenian-SSJ', 'Tamil-TTB'],
            '1.3' => ['Catalan-AnCora', 'Czech-CAC', 'Czech-CLTT', 'Dutch-LassySmall', 'English-ESL', 'English-LinES', 'Galician-CTG', 'Chinese-GSD', 'Kazakh-KTB', 'Latvian-LVTB', 'Portuguese-GSD', 'Russian-GSD', 'Russian-SynTagRus', 'Slovenian-SST', 'Spanish-AnCora', 'Swedish-LinES', 'Turkish-IMST'],
            '1.4' => ['Coptic-Scriptorium', 'Galician-TreeGal', 'Japanese-GSD', 'Sanskrit-UFAL', 'Slovak-SNK', 'Swedish_Sign_Language-SSLC', 'Ukrainian-IU', 'Uyghur-UDT', 'Vietnamese-VTB'],
            '2.0' => ['Arabic-NYUAD', 'Belarusian-HSE', 'English-ParTUT', 'French-FTB', 'French-ParTUT', 'French-Sequoia', 'Italian-ParTUT', 'Korean-GSD', 'Lithuanian-HSE', 'Norwegian-Nynorsk', 'Urdu-UDTB'],
            '2.1' => ['Afrikaans-AfriBooms', 'Arabic-PUD', 'Buryat-BDT', 'Cantonese-HK', 'Czech-FicTree', 'Czech-PUD', 'English-PUD', 'Finnish-PUD', 'French-PUD', 'German-PUD', 'Hindi-PUD', 'Chinese-CFL', 'Chinese-HK', 'Chinese-PUD', 'Italian-PoSTWITA', 'Italian-PUD', 'Japanese-PUD', 'Kurmanji-MG', 'Marathi-UFAL', 'North_Sami-Giella', 'Norwegian-NynorskLIA', 'Portuguese-PUD', 'Romanian-Nonstandard', 'Russian-PUD', 'Serbian-SET', 'Spanish-PUD', 'Swedish-PUD', 'Telugu-MTG', 'Turkish-PUD', 'Upper_Sorbian-UFAL'],
            '2.2' => ['Armenian-ArmTDP', 'Breton-KEB', 'English-GUM', 'Faroese-OFT', 'French-Spoken', 'Japanese-Modern', 'Korean-Kaist', 'Naija-NSC', 'Old_French-SRCMF', 'Polish-LFG', 'Russian-Taiga', 'Thai-PUD']
        );
        my $correct;
        foreach my $release (keys(%new_treebanks_by_release))
        {
            foreach my $treebank (@{$new_treebanks_by_release{$release}})
            {
                if("UD_$treebank" eq $folder)
                {
                    $correct = $release;
                    last;
                }
            }
        }
        if(defined($correct) && $claimed ne $correct)
        {
            $ok = 0;
            push(@{$errors}, "$folder README: 'Data available since: $claimed' is not true. This treebank was first released in UD v$correct.\n");
            $$n_errors++;
        }
        elsif(!defined($correct) && $claimed < $current_release)
        {
            $ok = 0;
            push(@{$errors}, "$folder README: 'Data available since: $claimed' is not true. This treebank was not released prior to UD v$current_release.\n");
            $$n_errors++;
        }
    }
    else
    {
        $ok = 0;
        push(@{$errors}, "$folder README: Unknown format of Data available since: '$metadata->{'Data available since'}'\n");
        $$n_errors++;
    }
    if($metadata->{Genre} !~ m/\w/)
    {
        $ok = 0;
        push(@{$errors}, "$folder README: Missing list of genres: '$metadata->{Genre}'\n");
        $$n_errors++;
    }
    else
    {
        # Originally (until UD 2.2) it was not an error if people invented their genres in addition to the predefined ones.
        # However, some treebanks do not follow prescribed syntax (e.g. place commas between genres) or just have typos here
        # (e.g. besides "news" there is also "new" or "newswire"), so we better ban unregistered genres and check it automatically.
        # Note that a copy of the list of known genres is also in evaluate_treebank.pl and in docs-automation/genre_symbols.json.
        my @official_genres = ('academic', 'bible', 'blog', 'email', 'fiction', 'grammar-examples', 'learner-essays', 'legal', 'medical', 'news', 'nonfiction', 'poetry', 'reviews', 'social', 'spoken', 'web', 'wiki');
        my @genres = split(/\s+/, $metadata->{Genre});
        my @unknown_genres = grep {my $g = $_; my @found = grep {$_ eq $g} (@official_genres); scalar(@found)==0} (@genres);
        if(scalar(@unknown_genres)>0)
        {
            $ok = 0;
            my $ug = join(' ', sort(@unknown_genres));
            push(@{$errors}, "$folder README: Unknown genre '$ug'\n");
            $$n_errors++;
        }
    }
    if($metadata->{License} !~ m/\w/)
    {
        $ok = 0;
        push(@{$errors}, "$folder README: Missing identification of license in README: '$metadata->{License}'\n");
        $$n_errors++;
    }
    if($metadata->{'Includes text'} !~ m/^(yes|no)$/i)
    {
        $ok = 0;
        push(@{$errors}, "$folder README: Metadata 'Includes text' must be 'yes' or 'no' but the current value is: '$metadata->{'Includes text'}'\n");
        $$n_errors++;
    }
    foreach my $annotation (qw(Lemmas UPOS XPOS Features Relations))
    {
        if($metadata->{$annotation} !~ m/\w/)
        {
            $ok = 0;
            push(@{$errors}, "$folder README: Missing information on availability and source of $annotation\n");
            $$n_errors++;
        }
        elsif($metadata->{$annotation} !~ m/^(manual native|converted from manual|converted with corrections|automatic|automatic with corrections|not available)$/)
        {
            $ok = 0;
            push(@{$errors}, "$folder README: Unknown value of metadata $annotation: '$metadata->{$annotation}'\n");
            $$n_errors++;
        }
    }
    if($metadata->{Contributors} !~ m/\w/)
    {
        $ok = 0;
        push(@{$errors}, "$folder README: Missing list of contributors: '$metadata->{Contributors}'\n");
        $$n_errors++;
    }
    if($metadata->{Contact} !~ m/\@/)
    {
        $ok = 0;
        push(@{$errors}, "$folder README: Missing contact e-mail: '$metadata->{Contact}'\n");
        $$n_errors++;
    }
    # Check other sections of the README file.
    if($metadata->{'Data available since'} =~ m/UD\s*v([0-9]+\.[0-9]+)/ && $1 < $current_release && !$metadata->{changelog})
    {
        $ok = 0;
        push(@{$errors}, "$folder: Old treebank ($metadata->{'Data available since'}) but README does not contain 'ChangeLog'\n");
        $$n_errors++;
    }
    # Add a link to the guidelines for README files. Add it to the last error message.
    # Do not make it a separate error message (just in case we get rid of $n_errors and use scalar(@errors) in the future).
    unless($ok)
    {
        $errors->[-1] .= "See http://universaldependencies.org/release_checklist.html#treebank-metadata for guidelines on machine-readable metadata.\n";
        $errors->[-1] .= "See http://universaldependencies.org/release_checklist.html#the-readme-file for general guidelines on README files.\n";
    }
    return $ok;
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
