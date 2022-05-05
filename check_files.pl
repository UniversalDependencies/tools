#!/usr/bin/env perl
# Checks files to be distributed as Universal Dependencies.
# Copyright © 2015, 2016, 2017, 2018, 2022 Dan Zeman <zeman@ufal.mff.cuni.cz>
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
my $current_release = 2.10;
# Month and year when the next release is expected. We use it in the announcement.
my $next_release_expected = 'November 2022';
my $announcement_min_size = 'less than 1,000 tokens';
my $announcement_max_size = 'over 3 million tokens';
# Path to the previous release is needed to compare the number of sentences and words.
# zen:/net/data/universal-dependencies-1.2
# mekong:C:\Users\Dan\Documents\Lingvistika\Projekty\universal-dependencies\release-1.2
my $oldpath = '/net/data/universal-dependencies-2.9';
GetOptions
(
    'release=s'       => \$current_release,
    'next-expected=s' => \$next_release_expected,
    'ann-min-size=s'  => \$announcement_min_size,
    'ann-max-size=s'  => \$announcement_max_size,
    'oldpath=s'       => \$oldpath,
    'future'          => \$include_future,
    'pull'            => \$pull,
    'validate'        => \$validate,
    'stats'           => \$recompute_stats,
    'tag=s'           => \$tag
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
            # Check that the expected files are present and that there are no extra files.
            udlib::check_files('..', $folder, $key, \@errors, \$n_errors);
            # Read the README file. We need to know whether this repository is scheduled for the upcoming release.
            my $metadata = udlib::read_readme('.');
            if(!defined($metadata))
            {
                push(@errors, "$folder: cannot read the README file: $!\n");
                $n_errors++;
            }
            # Check that all required metadata items are present in the README file.
            udlib::check_metadata($folder, $metadata, $current_release, \@errors, \$n_errors);
            chdir('..') or die("Cannot return to the upper folder");
            # Check that the language-specific documentation has at least the index (summary) page.
            check_documentation($folder, $langcode, \@errors, \$n_errors);
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
my $validhash = get_validation_results();
my %valid = %{$validhash};
my $n_folders_with_data = 0;
my $n_errors = 0;
my %languages_with_data;
my %families_with_data;
my %licenses;
my %genres;
my %contributors;
my %contributions; # for each contributor find treebanks they contributed to
my %contacts;
my %stats;
my %nw; # number of words in train|dev|test|all; indexed by folder name
my @unknown_folders; # cannot parse folder name or unknown language
my @nongit_folders; # folder is not a git repository
my @empty_folders; # does not contain data
my @future_folders; # scheduled for a future release (and we did not ask to include future data in the report)
my @invalid_folders; # at least one .conllu file does not pass validation
my @released_folders;
my %tcode_to_treebank_name;
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
            $tcode_to_treebank_name{$key} = join(' ', ($language, $treebank));
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
            if(!udlib::check_files('..', $folder, $key, \@errors, \$n_errors))
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
            if(exists($metadata->{firstrelease}) && udlib::cmp_release_numbers($metadata->{firstrelease}, $current_release) <= 0)
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
            if(!udlib::check_metadata($folder, $metadata, $current_release, \@errors, \$n_errors))
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
            # Exception 1: Czech PDT has four train files: train-c, train-l, train-m, train-v.
            # Exception 2: German HDT has two train files: train-a, train-b.
            # Exception 3: Russian SynTagRus has three train files: train-a, train-b, train-c.
            # No other CoNLL-U files are expected.
            # It is also expected that if there is dev, there is also train.
            # And if there is train, it should be same size or larger (in words) than both dev and test.
            if($folder eq 'UD_Czech-PDT')
            {
                # The data is split into four files because of the size limits.
                my $stats = udlib::collect_statistics_about_ud_file("$prefix-train-c.conllu");
                $nwtrain = $stats->{nword};
                $stats = udlib::collect_statistics_about_ud_file("$prefix-train-l.conllu");
                $nwtrain += $stats->{nword};
                $stats = udlib::collect_statistics_about_ud_file("$prefix-train-m.conllu");
                $nwtrain += $stats->{nword};
                $stats = udlib::collect_statistics_about_ud_file("$prefix-train-v.conllu");
                $nwtrain += $stats->{nword};
            }
            elsif($folder eq 'UD_German-HDT')
            {
                # The data is split into four files because of the size limits.
                my $stats = udlib::collect_statistics_about_ud_file("$prefix-train-a-1.conllu");
                $nwtrain = $stats->{nword};
                $stats = udlib::collect_statistics_about_ud_file("$prefix-train-a-2.conllu");
                $nwtrain += $stats->{nword};
                $stats = udlib::collect_statistics_about_ud_file("$prefix-train-b-1.conllu");
                $nwtrain += $stats->{nword};
                $stats = udlib::collect_statistics_about_ud_file("$prefix-train-b-2.conllu");
                $nwtrain += $stats->{nword};
            }
            elsif($folder eq 'UD_Russian-SynTagRus')
            {
                # The data is split into three files because of the size limits.
                my $stats = udlib::collect_statistics_about_ud_file("$prefix-train-a.conllu");
                $nwtrain = $stats->{nword};
                $stats = udlib::collect_statistics_about_ud_file("$prefix-train-b.conllu");
                $nwtrain += $stats->{nword};
                $stats = udlib::collect_statistics_about_ud_file("$prefix-train-c.conllu");
                $nwtrain += $stats->{nword};
            }
            else # all other treebanks
            {
                if(-f "$prefix-train.conllu")
                {
                    my $stats = udlib::collect_statistics_about_ud_file("$prefix-train.conllu");
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
                my $stats = udlib::collect_statistics_about_ud_file("$prefix-dev.conllu");
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
                my $stats = udlib::collect_statistics_about_ud_file("$prefix-test.conllu");
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
            # 1. test (>=10K tokens if possible);
            # 2. train (if it can be larger than test or if this is the only treebank of the language and train is a small sample);
            # 3. dev (if it can be at least 10K tokens and if train is larger than both test and dev).
            if($nwtest==0 && ($nwtrain>0 || $nwdev>0))
            {
                print("$folder: train or dev exists but there is no test\n");
                $n_errors++;
            }
            # Exception: ParTUT has some portions smaller because of other limitations (sync across languages and with UD_Italian).
            # Exception: PUD parallel data (including Japanese-PUDLUW) are currently test only, even if in some languages there is more than 20K words.
            # UD_Akkadian-RIAO: I think they told me that the treebank would grow; in the first version, they have only 20K test and no train.
            # UD_Czech-CLTT: The data needs a lot of fixes but ultimately I may want to re-split it, too. No exception at the moment.
            # Exception: UD_Armenian-ArmTDP decided to have only about 5K test, do not ping them.
            # Exception: UD_English-Atis keeps the train-dev-test split from the original corpus (it is small but it is roughly 80-10-10%).
            # Exception: UD_English-ESL are just below 10K test, and they do not participate in shared tasks anyway.
            # Exception: UD_English-GUMReddit has just 1840 words test. It does not participate in shared tasks (and if so, it can be merged with GUM).
            # Exception: UD_Faroese-FarPaHC has 8644 words test. I think I did not ask them about it but they have already relased it this way.
            # Exception: UD_French-FQB is a test-only treebank (or use cross-validation, or add it to training data of Sequoia).
            # Exception: UD_French-ParisStories is just below 10K test, and the total treebank is slightly below 30K.
            # Exception: UD_French-Rhapsodie (formerly Spoken) is just below 10K test, and the total treebank is only slightly over 30K.
            # Exception: UD_German-LIT is a test-only treebank (intended primarily for linguistic research).
            # Exception: UD_Hindi_English-HIENCS has only 3K test; they do not participate in shared tasks.
            # Exception: UD_Italian-TWITTIRO overlaps with POSTWITA and tries to match its data split.
            # UD_Manx-Cadhan: No exception but wait. 2021-05-06 Kevin writes: I have another 20k words that are mostly correct but need one more editing pass. I decided to stick with the 20k in test for now, with the aim of doing a 3-way split for the next release (if that's ok). My aim is to eventually get to 100k total.
            # UD_Old_East_Slavic-RNC: No exception but wait. 2021-05-05 Olga writes: Another 20k portion of the RNC orv data is planned as dev, it has not been released yet. I would keep it as is if possible: the current 20 k test were reported as test in some of our experiments.
            # Exception: UD_Sanskrit-Vedic is just below 10K test, and the total treebank is only slightly over 20K.
            # Exception: UD_Scottish_Gaelic-ARCOSG is close to 10K test tokens but they could not get there if they did not want to split documents.
            # Exception: UD_Turkish-Atis is parallel with UD_English-Atis (see above) and uses the same split.
            # Exception: UD_Turkish-FrameNet uses a 80-10-10% split, although the treebank is rather small (also, the sizes are computed in terms of number of frames rather than words).
            # Exception: UD_Turkish-Penn keeps the train-dev-test split from the original treebank where there are only 3K words dev and 4K words test.
            if($nwall>10000 && $nwtest<10000 && $folder !~ m/^UD_(.+-Atis|.+-ParTUT|Armenian-ArmTDP|English-(ESL|GUMReddit)|Faroese-FarPaHC|French-(ParisStories|Rhapsodie|Spoken)|Hindi_English-HIENCS|Italian-TWITTIRO|Sanskrit-Vedic|Scottish_Gaelic-ARCOSG|Turkish-FrameNet|Turkish-Penn)$/)
            {
                print("$folder: more than 10K words (precisely: $nwall) available but test has only $nwtest words\n");
                $n_errors++;
            }
            if($nwall>20000 && $nwtrain<10000 && $folder !~ m/^UD_(.+-PUD(LUW)?|.+-ParTUT|Akkadian-RIAO|French-FQB|German-LIT)$/)
            {
                print("$folder: more than 20K words (precisely: $nwall) available but train has only $nwtrain words\n");
                $n_errors++;
            }
            if($nwall>30000 && $nwdev<5000 && $folder !~ m/^UD_(.+-Atis|.+-PUD(LUW)?|.+-ParTUT|German-LIT|Turkish-Penn)$/)
            {
                print("$folder: more than 30K words (precisely: $nwall) available but dev has only $nwdev words\n");
                $n_errors++;
            }
            $stats{$key} = udlib::collect_statistics_about_ud_treebank('.', $key);
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
                    $contributions{$contributor}{$folder}++;
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
my @families = sort(keys(%families_with_data));
print(scalar(@families), " families with data: ", join(', ', @families), "\n\n");
my @languages = map {s/_/ /g; $_} (sort(keys(%languages_with_data)));
print(scalar(@languages), " languages with data: ", join(', ', @languages), "\n\n");
my @langcodes = sort(keys(%stats));
print("Treebank codes: ", join(' ', @langcodes), "\n\n");
my %langcodes1; map {my $x=$_; $x=~s/_.*//; $langcodes1{$x}++} (@langcodes);
my @langcodes1 = sort(keys(%langcodes1));
print("Language codes: ", join(' ', @langcodes1), "\n\n");
# Sometimes we need the ISO 639-3 codes (as opposed to the mix of -1 and -3 codes),
# e.g. when listing the languages in Lindat.
my %lcode2iso3;
foreach my $lname (keys(%{$languages_from_yaml}))
{
    $lcode2iso3{$languages_from_yaml->{$lname}{lcode}} = $languages_from_yaml->{$lname}{iso3};
}
my @iso3codes = sort(grep {defined($_) && $_ ne '' && !m/^q[a-t][a-z]$/} (map {$lcode2iso3{$_}} (@langcodes1)));
print(scalar(@iso3codes), " ISO 639-3 codes: ", join(' ', @iso3codes), "\n\n");
my @licenses = sort(keys(%licenses));
print(scalar(@licenses), " different licenses: ", join(', ', @licenses), "\n\n");
my @genres = sort(keys(%genres));
print(scalar(@genres), " different genres: ", join(', ', @genres), "\n\n");
my @contributors = keys(%contributors);
my %tridl, %tridf;
foreach my $contributor (@contributors)
{
    # We want to sort by last names first, and only look at first names when the
    # last names are identical. If we compared the whole names directly, we would
    # see "Morioka, Tomohiko" between "Mori, Keiko" and "Mori, Shinsuke"; we do
    # not want this to happen.
    my $lastname = $contributor;
    my $firstname = '';
    if($contributor =~ m/^([^,]+),\s*(.+)$/)
    {
        $lastname = $1;
        $firstname = $2;
    }
    $tridl{$contributor} = csort::zjistit_tridici_hodnoty($lastname, 'en');
    $tridf{$contributor} = csort::zjistit_tridici_hodnoty($firstname, 'en');
}
# Since release 2.5 we go by "Zeman, Nivre, and alphabetically others".
# Normal trid values are numeric strings. Prepend '!' and it will sort before
# any numeric value.
$tridl{'Zeman, Daniel'} = '!01';
$tridl{'Nivre, Joakim'} = '!02';
@contributors = sort {my $r = $tridl{$a} cmp $tridl{$b}; unless($r) {$r = $tridf{$a} cmp $tridf{$b}} $r} (keys(%contributors));
# Is the same person spelled differently in different treebanks?
get_potentially_misspelled_contributors(\%contributions, @contributors);
my @contributors_firstlast = map {my $x = $_; if($x =~ m/^(.+?),\s*(.+)$/) {$x = "$2 $1";} $x} (@contributors);
print(scalar(@contributors), " contributors: ", join('; ', @contributors), "\n\n");
my @contacts = sort(keys(%contacts));
print(scalar(@contacts), " contacts: ", join(', ', @contacts), "\n\n");
# Find treebanks whose data size has changed.
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
# Treebanks can appear, disappear and reappear. Get the list of all treebanks
# that are part either of this or of the previous release.
my %lastcurrtreebanks;
foreach my $t (@langcodes, @languages11)
{
    $lastcurrtreebanks{$t}++;
}
# Find treebanks whose size has changed by more than 10%.
my @changedsize;
my $codemaxl = 0;
my $namemaxl = 0;
my $oldmaxl = 0;
my $newmaxl = 0;
foreach my $t (sort(keys(%lastcurrtreebanks)))
{
    my $oldsize = exists($stats11->{$t}) ? $stats11->{$t}{nword} : 0;
    my $newsize = exists($stats{$t}) ? $stats{$t}{nword} : 0;
    if($newsize > $oldsize * 1.1 || $newsize < $oldsize * 0.9)
    {
        my %record =
        (
            'code' => $t,
            'name' => $tcode_to_treebank_name{$t},
            'old'  => $oldsize,
            'new'  => $newsize
        );
        push(@changedsize, \%record);
        $codemaxl = length($t) if(length($t) > $codemaxl);
        $namemaxl = length($record{name}) if(length($record{name}) > $namemaxl);
        $oldmaxl = length($oldsize) if(length($oldsize) > $oldmaxl);
        $newmaxl = length($newsize) if(length($newsize) > $newmaxl);
    }
}
my $nchangedsize = scalar(@changedsize);
my $changelog = "The size of the following $nchangedsize treebanks changed significantly since the last release:\n";
foreach my $r (sort {$a->{name} cmp $b->{name}} (@changedsize))
{
    my $padding = ' ' x ($namemaxl - length($r->{name}));
    $changelog .= sprintf("    %s: %${oldmaxl}d → %${newmaxl}d\n", $r->{name}.$padding, $r->{old}, $r->{new}); # right arrow is \x{2192}
}
# Collect statistics of the current treebanks. Especially the total number of
# sentences, tokens and words is needed for the metadata in Lindat.
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
    $announcement_min_size,
    $announcement_max_size,
    $next_release_expected,
    \@contributors_firstlast,
    $changelog
);
print($announcement);



#------------------------------------------------------------------------------
# Downloads the current validation report from the validation server. Returns
# a reference to the hash of valid treebanks.
#------------------------------------------------------------------------------
sub get_validation_results
{
    my %valid;
    # After we used this script to select the treebanks automatically,
    # we typically freeze the list in an external file called
    # released_treebanks.txt (see http://universaldependencies.org/release_checklist_task_force.html#determining-which-treebanks-will-be-released).
    # Download the current validation report. (We could run the validator ourselves
    # but it would take a lot of time.)
    my @validation_report = split(/\n/, get('https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/validation-report.pl?text_only'));
    if(scalar(@validation_report)==0)
    {
        print STDERR ("WARNING: Could not download validation report from quest. All treebanks will be considered invalid.\n");
    }
    foreach my $line (@validation_report)
    {
        if($line =~ m/^(UD_.+): (VALID|LEGACY)/)
        {
            $valid{$1}++;
        }
    }
    return \%valid;
}



#------------------------------------------------------------------------------
# Gets the list of files in a UD folder. Returns the list of CoNLL-U files.
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
    my %files =
    (
        'conllu' => \@conllufiles
    );
    return \%files;
}



#------------------------------------------------------------------------------
# Checks whether documentation contains a summary page about a language.
#------------------------------------------------------------------------------
sub check_documentation
{
    my $folder = shift; # folder name, e.g. 'UD_Czech-PDT', not path
    my $lcode = shift;
    my $errors = shift; # reference to array of error messages
    my $n_errors = shift; # reference to error counter
    my $ok = 1;
    ###!!! For now assume that a clone of the docs repository is accessible as
    ###!!! the docs subfolder of the current folder.
    my $indexpath = "docs/_$lcode/index.md";
    if(! -f $indexpath)
    {
        $ok = 0;
        push(@{$errors}, "[L0 Repo lang-spec-doc] $folder: Language '$lcode' does not have the one-page documentation summary in the docs repository.\nSee http://universaldependencies.org/contributing_language_specific.html for instructions on how to write documentation.\n");
        $$n_errors++;
    }
    else
    {
        # So the file exists but does it really contain anything useful?
        # Some people just create an almost empty file without bothering to put the contents there (e.g., Sebastian for English).
        my $doc;
        open(IDX, $indexpath);
        while(<IDX>)
        {
            $doc .= $_;
        }
        close(IDX);
        # Czech documentation has over 16000 B.
        # Swedish documentation has over 4500 B.
        # Yoruba is probably incomplete but it still has over 3500 B.
        # Let's require 2500 B as a minimum and hope that people don't just put a sequence of whitespace characters there.
        if(length($doc) < 2500)
        {
            $ok = 0;
            push(@{$errors}, "[L0 Repo lang-spec-doc] $folder: Language '$lcode' does not have the one-page documentation summary in the docs repository (the file exists but it seems incomplete).\nSee http://universaldependencies.org/contributing_language_specific.html for instructions on how to write documentation.\n");
            $$n_errors++;
        }
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
                $stats{$key} = udlib::collect_statistics_about_ud_treebank("$release_path/$folder", $key);
            }
        }
    }
    return \%stats;
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
    my $changelog = shift;
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
    my @contributors = @{$contlistref};
    my $contributors = join(', ', @contributors);
    my $text = <<EOF
We are very happy to announce the $nth release of annotated treebanks in Universal Dependencies, v$release, available at http://universaldependencies.org/.

Universal Dependencies is a project that seeks to develop cross-linguistically consistent treebank annotation for many languages with the goal of facilitating multilingual parser development, cross-lingual learning, and parsing research from a language typology perspective (de Marneffe et al., 2021; Nivre et al., 2020). The annotation scheme is based on (universal) Stanford dependencies (de Marneffe et al., 2006, 2008, 2014), Google universal part-of-speech tags (Petrov et al., 2012), and the Interset interlingua for morphosyntactic tagsets (Zeman, 2008). The general philosophy is to provide a universal inventory of categories and guidelines to facilitate consistent annotation of similar constructions across languages, while allowing language-specific extensions when necessary.

The $n_treebanks treebanks in v$release are annotated according to version $guidelines_version of the UD guidelines and represent the following $n_languages languages: $languages. The $n_languages languages belong to $n_families families: $families. Depending on the language, the treebanks range in size from $min_size to $max_size. We expect the next release to be available in $next_release_available_in.

$changelog
$contributors


References

Marie-Catherine de Marneffe, Christopher Manning, Joakim Nivre, Daniel Zeman. 2021. Universal Dependencies. In Computational Linguistics 47:2, pp. 255–308.

Joakim Nivre, Marie-Catherine de Marneffe, Filip Ginter, Jan Hajič, Christopher D. Manning, Sampo Pyysalo, Sebastian Schuster, Francis Tyers, Daniel Zeman. 2020. Universal Dependencies v2: An Evergrowing Multilingual Treebank Collection. In Proceedings of LREC.

--------------------------------------------------------------------------------

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



#------------------------------------------------------------------------------
# A contributor may be listed at more than one treebank. If their name is not
# spelled always the same way, they will be listed as multiple people. This
# function tries to identify such cases and issue warnings.
#------------------------------------------------------------------------------
sub get_potentially_misspelled_contributors
{
    # Other tests we could try:
    # - If people use comma instead of semicolon to separate two contributors,
    #   we will think it is one person with multiple given names and multiple
    #   surnames. I do not know how to detect this; Spanish people can have
    #   two given names and two surnames. But this error has happened already.
    # - The overlap computed here may not work if an author has a middle name which is sometimes omitted ("Francis (Morton) Tyers").
    #   Hence try also overlap of characters per word: if there are at least two words with 80%+ character overlap,
    #   and one or more other words that have no clear counterpart on the other side, report suspicion.
    my $contributions = shift; # hashref: for each contributor, hash of treebanks they contributed to
    my $ok = 1;
    my @contributors = @_;
    my @character_hashes;
    my %problematic_names;
    for(my $i = 0; $i <= $#contributors; $i++)
    {
        $character_hashes[$i] = get_character_hash($contributors[$i]);
        # If there is no comma in the name, it means the name is not divided to given names and surnames.
        # This is rarely correct, so we will issue a warning.
        if(!exists($character_hashes[$i]{','}) || $character_hashes[$i]{','} < 1)
        {
            print("WARNING: '$contributors[$i]' is not divided to given names and surnames.\n");
            $ok = 0;
            $problematic_names{$contributors[$i]}++;
        }
        # If there are two or more commas in the name, it is an error.
        # Most likely someone used commas instead of semicolons to separate persons.
        elsif($character_hashes[$i]{','} > 1)
        {
            print("WARNING: '$contributors[$i]' contains too many commas. There should be only one, separating surname from given names.\n");
            $ok = 0;
            $problematic_names{$contributors[$i]}++;
        }
    }
    # We must compare every name with every other name (N^2).
    # Hashing will not help us identify suspicious pairs.
    for(my $i = 0; $i <= $#contributors; $i++)
    {
        for(my $j = $i+1; $j <= $#contributors; $j++)
        {
            my $similarity = get_character_overlap($contributors[$i], $contributors[$j], $character_hashes[$i], $character_hashes[$j]);
            # Threshold found empirically to minimize false alarms.
            if($similarity >= 0.83)
            {
                print("WARNING: '$contributors[$i]' is similar ($similarity) to '$contributors[$j]'\n");
                $ok = 0;
                $problematic_names{$contributors[$i]}++;
                $problematic_names{$contributors[$j]}++;
            }
        }
    }
    # Print an empty line if there were warnings.
    # Also report the treebanks the problematic contributors contributed to.
    if(!$ok)
    {
        my @pn = sort(keys(%problematic_names));
        foreach my $pn (@pn)
        {
            print("$pn: ", join(', ', sort(keys(%{$contributions->{$pn}}))), "\n");
        }
        print("\n");
    }
}



#------------------------------------------------------------------------------
# Gets character frequencies from a string so that string similarity can be
# assessed.
#------------------------------------------------------------------------------
sub get_character_hash
{
    my $name = shift;
    # Get list of characters. Do not even lowercase them (case change would also
    # prevent us from merging the names as one person in global metadata).
    my @characters = split(//, $name);
    my %characters;
    foreach my $c (@characters)
    {
        $characters{$c}++;
    }
    return \%characters;
}



#------------------------------------------------------------------------------
# Compares character frequencies of two strings relatively to the lengths of
# the strings and returns a similarity measure (maximum is similarity = 1) for
# identical strings.
#------------------------------------------------------------------------------
sub get_character_overlap
{
    my $name1 = shift;
    my $name2 = shift;
    my $ch1 = shift;
    my $ch2 = shift;
    my %chunion;
    foreach my $c (keys(%{$ch1}), keys(%{$ch2}))
    {
        $chunion{$c}++;
    }
    my $diff = 0;
    foreach my $c (keys(%chunion))
    {
        $diff += abs($ch1->{$c} - $ch2->{$c});
        # my $ldiff = abs($ch1->{$c} - $ch2->{$c});
        # print("character = '$c'; left = $ch1->{$c}; right = $ch2->{$c}; diff = $ldiff\n");
    }
    # If 1 character is replaced by 1 character (e.g. "ž" --> "z"), we have 2 diff points but we will count it as 1.
    # Consequently, if a character is inserted on one side (no counterpart on the other side), we count it as 0.5.
    $diff /= 2;
    my $avglength = (length($name1) + length($name2)) / 2;
    # my $nuc = scalar(keys(%chunion));
    # print("name1 = '$name1'; name2 = '$name2'; unique chars = $nuc; diff = $diff; avglength = $avglength\n");
    return 1 - ($diff / $avglength);
}
