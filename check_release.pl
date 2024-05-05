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
    print STDERR ("Usage: tools/check_release.pl --release 2.10 --next-expected 'November 2022' --oldpath /net/data/universal-dependencies-2.9 |& tee release-2.10-report.txt | less\n");
    print STDERR ("       Must be called from the folder where all UD repositories are cloned as subfolders.\n");
    print STDERR ("       Will produce a complete report for the next UD release.\n");
}

use Getopt::Long;
use LWP::Simple;
# Dan's sorting library
use csort;
# We need to tell Perl where to find my udlib module (same folder as this script).
# While we are at it, we will also remember the path to the superordinate folder,
# which should be the UD root (all UD treebanks should be its subfolders).
BEGIN
{
    use Cwd;
    my $path = $0;
    $path =~ s:\\:/:g;
    my $currentpath = getcwd();
    $libpath = $currentpath;
    if($path =~ m:/:)
    {
        $path =~ s:/[^/]*$:/:;
        chdir($path);
        $libpath = getcwd();
    }
    chdir('..');
    $udpath = getcwd();
    chdir($currentpath);
    #print STDERR ("libpath=$libpath\n");
}
use lib $libpath;
use udlib;

# Include reports on future repositories (not scheduled for the upcoming release)?
# (If there is no README file, we will include the repository in the report and complain about the missing README.)
my $include_future = 0;
# Pull the latest changes from Github and show git status of each repository?
my $pull = 0;
# Validate all CoNLL-U files and report invalid ones?
my $validate = 0;
# Number of the current release as it is found in README files. Repositories targeting a later release will not be included.
my $current_release;
# Month and year when the next release is expected. We use it in the announcement.
my $next_release_expected;
my $announcement_min_size = 'less than 1,000 tokens';
my $announcement_max_size = 'over 3 million tokens';
# Path to the previous release is needed to compare the number of sentences and words.
# zen:/net/data/universal-dependencies-1.2
# mekong:C:\Users\Dan\Documents\Lingvistika\Projekty\universal-dependencies\release-1.2
my $oldpath;
GetOptions
(
    'release=s'       => \$current_release,
    'next-expected=s' => \$next_release_expected,
    'ann-min-size=s'  => \$announcement_min_size,
    'ann-max-size=s'  => \$announcement_max_size,
    'oldpath=s'       => \$oldpath,
    'future'          => \$include_future,
    'pull'            => \$pull,
    'validate'        => \$validate
);
# Options that change with every release have no defaults and must be specified
# on the command line. Check that we received them.
if(!defined($current_release) || !defined($next_release_expected) || !defined($oldpath))
{
    usage();
    die("Missing option");
}

# We need a mapping from the English names of the languages (as they appear in folder names) to their ISO codes and families.
my $languages_from_yaml = udlib::get_language_hash();

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
my @nongit_folders; # folder is not a git repository
my @empty_folders; # does not contain data
my @future_folders; # scheduled for a future release (and we did not ask to include future data in the report)
my @invalid_folders; # at least one .conllu file does not pass validation
my @released_folders;

# Get mappings between language names, language codes, folder names, ltcodes,
# and human-friendly treebank names.
my @unknown_folders; # cannot parse folder name or unknown language
my @known_folders; # can parse folder name and known language
my %folder_codes_names;
foreach my $folder (@folders)
{
    my $record = get_folder_codes_and_names($folder, $languages_from_yaml);
    if(defined($record))
    {
        $folder_codes_names{$folder} = $record;
        push(@known_folders, $folder);
    }
    else
    {
        # One of two possible error messages has been printed in get_folder_codes_and_names().
        push(@unknown_folders, $folder);
    }
}

# Now examine in more detail those folders for which we know the language.
foreach my $folder (@known_folders)
{
    my $language = $folder_codes_names{$folder}{lname};
    my $ltcode = $folder_codes_names{$folder}{ltcode};
    my $family = $folder_codes_names{$folder}{family};
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
    my $n = get_number_of_conllu_files('.');
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
    my $udlibstats = {};
    if(!udlib::check_files('..', $folder, $ltcode, \@errors, \$n_errors, $udlibstats))
    {
        print(join('', @errors));
        splice(@errors);
    }
    ###!!! We may want to consolidate somehow the ways how we collect and
    ###!!! store various statistics. This hash-in-hash is another by-product
    ###!!! of checking the files in udlib.
    $stats{$folder} = $udlibstats->{stats};
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
    if(defined($family))
    {
        # Keep only the family, discard the genus if present.
        $family =~ s/,.*//;
        $families_with_data{$family}++;
    }
    # Check that all required metadata items are present in the README file.
    if(!udlib::check_metadata('..', $folder, $metadata, \@errors, \$n_errors))
    {
        print(join('', @errors));
        splice(@errors);
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
    chdir('..') or die("Cannot return to the upper folder");
}
print("$n_errors errors must be fixed.\n") if($n_errors>0);
print("\n");
print("Found ", scalar(@folders), " folders.\n\n");
if(scalar(@unknown_folders) > 0)
{
    print(scalar(@unknown_folders), " folders skipped because their language cannot be identified: ", join(', ', @unknown_folders), "\n\n");
}
if(scalar(@nongit_folders) > 0)
{
    print(scalar(@nongit_folders), " folders ignored because they are not git repositories: ", join(', ', @nongit_folders), "\n\n");
}
if(scalar(@empty_folders) > 0)
{
    print(scalar(@empty_folders), " folders ignored because they are empty: ", join(', ', @empty_folders), "\n\n");
}
if(scalar(@future_folders) > 0)
{
    print(scalar(@future_folders), " folders ignored because their README says they should be released later: ", join(', ', @future_folders), "\n\n");
}
if(scalar(@invalid_folders) > 0)
{
    print(scalar(@invalid_folders), " folders ignored because at least one file does not pass validation: ", join(', ', @invalid_folders), "\n\n");
}
# Do not separate names of released folders by commas. We will want to copy the list as arguments for the packaging script.
print("$n_folders_with_data folders are git repositories and contain valid data:\n\n", join(' ', @released_folders), "\n\n");
my @families = sort(keys(%families_with_data));
print(scalar(@families), " families with data: ", join(', ', @families), "\n\n");
my @languages = map {s/_/ /g; $_} (sort(keys(%languages_with_data)));
print(scalar(@languages), " languages with data: ", join(', ', @languages), "\n\n");
my @folders_with_data = sort(keys(%stats));
my @ltcodes = map {$folder_codes_names{$_}{ltcode}} (@folders_with_data);
print("Treebank codes: ", join(' ', @ltcodes), "\n\n");
my %lcodes; map {$lcodes{$folder_codes_names{$_}{lcode}}++} (@folders_with_data);
my @lcodes = sort(keys(%lcodes));
print("Language codes: ", join(' ', @lcodes), "\n\n");
# Sometimes we need the ISO 639-3 codes (as opposed to the mix of -1 and -3 codes),
# e.g. when listing the languages in Lindat.
my %iso3codes; map {$iso3codes{$folder_codes_names{$_}{iso3}}++} (@folders_with_data);
my @iso3codes = sort(grep {defined($_) && $_ ne '' && !m/^q[a-t][a-z]$/} (keys(%iso3codes)));
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
my ($changelog, $newlanguages) = compare_with_previous_release($oldpath, \%stats, \%folder_codes_names, $languages_from_yaml);
# Summarize the statistics of the current treebanks. Especially the total
# number of sentences, tokens and words is needed for the metadata in Lindat.
print("\nSizes of treebanks in the new release:\n\n");
my ($nsent, $ntok, $nfus, $nword, $table, $maxl) = summarize_statistics(\%stats);
foreach my $row (@{$table})
{
    my @out;
    for(my $i = 0; $i <= $#{$row}; $i++)
    {
        my $npad = $maxl->[$i]-length($row->[$i]);
        if($i == 0)
        {
            push(@out, $row->[$i].' '.('.' x $npad));
        }
        else
        {
            push(@out, (' ' x $npad).$row->[$i]);
        }
        push(@out, $padded);
    }
    print(join('   ', @out), "\n");
}
print("--------------------------------------------------------------------------------\n");
my @newlanguages = sort(keys(%{$newlanguages}));
my $nnl = scalar(@newlanguages);
if($nnl > 0)
{
    print("The following $nnl languages are new in this release:\n");
    my $maxl = 0;
    foreach my $l (@newlanguages)
    {
        if(length($l) > $maxl)
        {
            $maxl = length($l);
        }
    }
    foreach my $l (@newlanguages)
    {
        my $pad = ' ' x ($maxl-length($l));
        print("$newlanguages->{$l}{lcode}\t$newlanguages->{$l}{iso3}\t$l$pad\t($newlanguages->{$l}{family})\n");
    }
}
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
    $changelog,
    $nsent,
    $ntok,
    $nword
);
print($announcement);



#------------------------------------------------------------------------------
# Takes a folder name, collects related language / treebank codes and names,
# puts them in a hash and returns it as a reference. If the folder name does
# not have expected form or the language is unknown, returns undef.
#------------------------------------------------------------------------------
sub get_folder_codes_and_names
{
    my $folder = shift;
    my $languages_from_yaml = shift;
    # The name of the folder: 'UD_' + language name + optional treebank identifier.
    # Example: UD_Ancient_Greek-PROIEL
    my ($language, $treebank) = udlib::decompose_repo_name($folder);
    if(defined($language))
    {
        if(exists($languages_from_yaml->{$language}))
        {
            my %record =
            (
                'lname'  => $language,
                'lcode'  => $languages_from_yaml->{$language}{lcode},
                'iso3'   => $languages_from_yaml->{$language}{iso3},
                'family' => $languages_from_yaml->{$language}{family},
                'tname'  => $treebank,
                'ltcode' => udlib::get_ltcode_from_repo_name($folder, $languages_from_yaml),
                'hname'  => join(' ', ($language, $treebank)) # human-friendly language + treebank name (no 'UD' in the beginning, spaces instead of underscores)
            );
            $record{family} =~ s/^IE/Indo-European/;
            return \%record;
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
    return undef;
}



#------------------------------------------------------------------------------
# Downloads the current validation report from the validation server. Returns
# a reference to the hash of valid treebanks.
#------------------------------------------------------------------------------
sub get_validation_results
{
    my %valid;
    # After we used this script to select the treebanks automatically,
    # we typically freeze the list in an external file called
    # released_treebanks.txt (see https://universaldependencies.org/release_checklist_task_force.html#determining-which-treebanks-will-be-released).
    # Download the current validation report. (We could run the validator ourselves
    # but it would take a lot of time.)
    my @validation_report = split(/\n/, get('https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/validation-report.pl?text_only'));
    if(scalar(@validation_report)==0)
    {
        print STDERR ("WARNING: Could not download validation report from quest. All treebanks will be considered invalid.\n");
    }
    foreach my $line (@validation_report)
    {
        if($line =~ m/^(UD_.+): (SAPLING|CURRENT|RETIRED) (VALID|ERROR LEGACY)/)
        {
            $valid{$1}++;
        }
    }
    return \%valid;
}



#------------------------------------------------------------------------------
# Gets the number of CoNLL-U files in a UD treebank folder. We need to know
# whether the treebank is empty (but we will not say that it is empty if it
# contains one empty CoNLL-U file).
#------------------------------------------------------------------------------
sub get_number_of_conllu_files
{
    my $path = shift; # path to the repository (default: '.')
    $path = '.' if(!defined($path));
    opendir(DIR, $path) or die("Cannot read folder '$path': $!");
    my @files = readdir(DIR);
    closedir(DIR);
    my @conllufiles = grep {-f $_ && m/\.conllu$/} (@files);
    return scalar(@conllufiles);
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
        if(-d "$release_path/$folder" && defined($language))
        {
            if(exists($languages_from_yaml->{$language}))
            {
                my $ltcode = $languages_from_yaml->{$language}{lcode};
                $ltcode .= '_'.lc($treebank) if($treebank ne '');
                $stats{$folder} = udlib::collect_statistics_about_ud_treebank("$release_path/$folder", $ltcode);
            }
        }
    }
    return \%stats;
}



#------------------------------------------------------------------------------
# Summarizes statistics of the current treebanks. Especially the total number
# of sentences, tokens and words is needed for the metadata in Lindat.
#------------------------------------------------------------------------------
sub summarize_statistics
{
    my $stats = shift; # hash reference
    my $nsent = 0;
    my $ntok = 0;
    my $nfus = 0;
    my $nword = 0;
    my @table;
    my @maxl;
    add_table_row(\@table, \@maxl, 'TREEBANK', 'SENTENCES', 'TOKENS', 'FUSED', 'WORDS');
    my @folders = sort(keys(%{$stats}));
    foreach my $folder (@folders)
    {
        add_table_row(\@table, \@maxl, $folder, $stats->{$folder}{nsent}, $stats->{$folder}{ntok}, $stats->{$folder}{nfus}, $stats->{$folder}{nword});
        $nsent += $stats->{$folder}{nsent};
        $ntok += $stats->{$folder}{ntok};
        $nfus += $stats->{$folder}{nfus};
        $nword += $stats->{$folder}{nword};
    }
    add_table_row(\@table, \@maxl, 'TOTAL', $nsent, $ntok, $nfus, $nword);
    return ($nsent, $ntok, $nfus, $nword, \@table, \@maxl);
}



#------------------------------------------------------------------------------
# Adds a table row and updates maximum lengths of cells.
#------------------------------------------------------------------------------
sub add_table_row
{
    my $table = shift; # array reference
    my $maxl = shift; # array reference
    my @tablerow = @_;
    for(my $i = 0; $i <= $#tablerow; $i++)
    {
        $maxl->[$i] = max($maxl->[$i], length($tablerow[$i]));
    }
    push(@{$table}, \@tablerow);
}



#------------------------------------------------------------------------------
# Returns maximum of two numbers.
#------------------------------------------------------------------------------
sub max
{
    my $x = shift;
    my $y = shift;
    return $y > $x ? $y : $x;
}



#------------------------------------------------------------------------------
# Compares the new release with the previous one in terms of treebank sizes.
# Significant changes should be reported. Especially if a treebank shrank,
# it may be a sign of an error. The function prints report to STDOUT along the
# way but it also returns a preformatted changelog that can be used in the
# release announcement.
#------------------------------------------------------------------------------
sub compare_with_previous_release
{
    my $oldpath = shift;
    my $newstats = shift;
    my $folder_codes_names = shift;
    my $languages_from_yaml = shift;
    print("Collecting statistics of $oldpath...\n");
    my $oldstats = collect_statistics_about_ud_release($oldpath);
    my @oldtreebanks = sort(keys(%{$oldstats}));
    my @newtreebanks = sort(keys(%{$newstats}));
    foreach my $t (@oldtreebanks)
    {
        if($oldstats->{$t}{ntok}  != $newstats->{$t}{ntok}  ||
           $oldstats->{$t}{nword} != $newstats->{$t}{nword} ||
           $oldstats->{$t}{nfus}  != $newstats->{$t}{nfus}  ||
           $oldstats->{$t}{nsent} != $newstats->{$t}{nsent})
        {
            my $pad = ' ' x (length($t)-5);
            my $diff = $newstats->{$t}{nword}-$oldstats->{$t}{nword};
            my $sign = $diff > 0 ? '+' : $diff < 0 ? '–' : '';
            my $pct = $diff ? sprintf(" ==> %s%d%%", $sign, abs($diff)/$oldstats->{$t}{nword}*100+0.5) : '';
            print("$l\tt=$oldstats->{$t}{ntok}\tw=$oldstats->{$t}{nword}\tf=$oldstats->{$t}{nfus}\ts=$oldstats->{$t}{nsent}\n");
            print(" NOW:$pad\tt=$newstats->{$t}{ntok}\tw=$newstats->{$t}{nword}\tf=$newstats->{$t}{nfus}\ts=$newstats->{$t}{nsent}\t$pct\n");
        }
    }
    print("\n");
    # Get the list of languages that are new in this release.
    my %oldlanguages;
    my %newlanguages;
    foreach my $t (@oldtreebanks)
    {
        if(exists($folder_codes_names->{$t}))
        {
            my $language = $folder_codes_names->{$t}{lname};
            if(!exists($oldlanguages{$language}))
            {
                $oldlanguages{$language} = $folder_codes_names->{$t};
            }
        }
        else
        {
            my $record = get_folder_codes_and_names($t, $languages_from_yaml);
            if(defined($record))
            {
                my $language = $record->{lname};
                if(!exists($oldlanguages{$language}))
                {
                    $oldlanguages{$language} = $record;
                }
            }
        }
    }
    foreach my $t (@newtreebanks)
    {
        my $language = $folder_codes_names->{$t}{lname};
        if(!exists($oldlanguages{$language}) && !exists($newlanguages{$language}))
        {
            $newlanguages{$language} = $folder_codes_names->{$t};
        }
    }
    # Treebanks can appear, disappear and reappear. Get the list of all treebanks
    # that are part either of this or of the previous release.
    my %oldnewtreebanks;
    foreach my $t (@oldtreebanks, @newtreebanks)
    {
        $oldnewtreebanks{$t}++;
    }
    my @oldnewtreebanks = sort(keys(%oldnewtreebanks));
    # Find treebanks whose size has changed by more than 10%.
    my @changedsize;
    my $codemaxl = 0;
    my $namemaxl = 0;
    my $oldmaxl = 0;
    my $newmaxl = 0;
    foreach my $t (@oldnewtreebanks)
    {
        my $oldsize = exists($oldstats->{$t}) ? $oldstats->{$t}{nword} : 0;
        my $newsize = exists($newstats->{$t}) ? $newstats->{$t}{nword} : 0;
        if($newsize > $oldsize * 1.1 || $newsize < $oldsize * 0.9)
        {
            # For retired or renamed old treebanks we may not have the hname yet.
            my $hname;
            if(exists($folder_codes_names->{$t}))
            {
                $hname = $folder_codes_names->{$t}{hname};
            }
            else
            {
                my $record = get_folder_codes_and_names($t, $languages_from_yaml);
                if(defined($record))
                {
                    # We could add the record about the old treebank to the database.
                    # But it could be dangerous because elsewhere we assume that the
                    # database contains exactly those treebanks that are going to be
                    # released now.
                    #$folder_codes_names{$t} = $record;
                    $hname = $record->{hname};
                }
                else
                {
                    $hname = 'UNKNOWN';
                }
            }
            my %record =
            (
                'code' => $t,
                'name' => $hname,
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
    return ($changelog, \%newlanguages);
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
    my $n_sentences = shift;
    my $n_tokens = shift;
    my $n_words = shift;
    my @release_list   = ('1.0',   '1.1',    '1.2',    '1.3',    '1.4',   '2.0',   '2.1',     '2.2',    '2.3',   '2.4',   '2.5',      '2.6',     '2.7',        '2.8',        '2.9',       '2.10',      '2.11',        '2.12',       '2.13',       '2.14',      '2.15',         '2.16',          '2.17',         '2.18',          '2.19');
    my @nth_vocabulary = ('first', 'second', 'third',  'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth', 'tenth', 'eleventh', 'twelfth', 'thirteenth', 'fourteenth', 'fifteenth', 'sixteenth', 'seventeenth', 'eighteenth', 'nineteenth', 'twentieth', 'twenty-first', 'twenty-second', 'twenty-third', 'twenty-fourth', 'twenty-fifth');
    my $nth;
    for(my $i = 0; $i<=$#release_list; $i++)
    {
        if($release_list[$i] eq $release)
        {
            $nth = $nth_vocabulary[$i];
            last;
        }
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
We are very happy to announce the $nth release of annotated treebanks in Universal Dependencies, v$release, available at https://universaldependencies.org/.

Universal Dependencies is a project that seeks to develop cross-linguistically consistent treebank annotation for many languages with the goal of facilitating multilingual parser development, cross-lingual learning, and parsing research from a language typology perspective (de Marneffe et al., 2021; Nivre et al., 2020). The annotation scheme is based on (universal) Stanford dependencies (de Marneffe et al., 2006, 2008, 2014), Google universal part-of-speech tags (Petrov et al., 2012), and the Interset interlingua for morphosyntactic tagsets (Zeman, 2008). The general philosophy is to provide a universal inventory of categories and guidelines to facilitate consistent annotation of similar constructions across languages, while allowing language-specific extensions when necessary.

The $n_treebanks treebanks in v$release are annotated according to version $guidelines_version of the UD guidelines and represent the following $n_languages languages: $languages. The $n_languages languages belong to $n_families families: $families. Depending on the language, the treebanks range in size from $min_size to $max_size. We expect the next release to be available in $next_release_available_in.

$changelog
In total, the new release contains $n_sentences sentences, $n_tokens surface tokens and $n_words syntactic words.

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
