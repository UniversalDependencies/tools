#!/usr/bin/env perl
# Evaluates quality of a UD treebank. Should help to determine if there are
# multiple treebanks in one language, which is the best one to use.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
use File::Which; # find executable files in $PATH
use udlib;

my $verbose = 0;
my $forcemaster = 0;
GetOptions
(
    'verbose'      => \$verbose,
    'forcemaster!' => \$forcemaster
);

# Path to the local copy of the UD repository (e.g., UD_Czech).
my $folder = $ARGV[0];
if(!defined($folder))
{
    die("Usage: $0 path-to-ud-folder");
}
$folder =~ s:/$::;
$folder =~ s:^\./::;
if($folder =~ m:/:)
{
    print STDERR ("WARNING: argument '$folder' contains a slash, indicating that the treebank is not a direct subfolder of the current folder. Some tests will probably not work as expected!\n");
}
if($verbose)
{
    print STDERR ("Running the following version of tools/evaluate_treebank.pl:\n");
    system("cd tools ; (git log evaluate_treebank.pl | head -3 1>&2) ; cd ..");
}
# The ranking that we apply to the list of treebanks of a given language (on UD title page)
# should be based on the most recent official release, i.e., on the master branch.
if($forcemaster)
{
    ###!!! At present we ignore the fact that multiple CGI processes may attempt to
    ###!!! fiddle with the repository at the same time! When that happens, the output
    ###!!! will be wrong!
    system("cd $folder ; (git checkout master 1>&2) ; cd ..");
}
if($verbose)
{
    print STDERR ("Evaluating the following revision of $folder:\n");
    system("cd $folder ; (git log | head -3 1>&2) ; cd ..");
}
my $record = udlib::get_ud_files_and_codes($folder);
my $metadata = udlib::read_readme($folder);
my $n = 0;
my $ntrain = 0;
my $ndev = 0;
my $ntest = 0;
my %forms;
my %lemmas;
my %tags;
my $n_words_with_features = 0;
my %udeprels;
foreach my $file (@{$record->{files}})
{
    open(FILE, "$folder/$file") or die("Cannot read $folder/$file: $!");
    while(<FILE>)
    {
        if(m/^\d+\t/)
        {
            s/\r?\n$//;
            my @f = split(/\t/, $_);
            my $form = $f[1];
            my $lemma = $f[2];
            my $upos = $f[3];
            my $feat = $f[5];
            my $udeprel = $f[7];
            $udeprel =~ s/:.*$//;
            $n++;
            if($file =~ m/ud-train/)
            {
                $ntrain++;
            }
            elsif($file =~ m/ud-dev/)
            {
                $ndev++;
            }
            elsif($file =~ m/ud-test/)
            {
                $ntest++;
            }
            $forms{$form}++;
            $lemmas{$lemma}++;
            $tags{$upos}++;
            $n_words_with_features++ if($feat ne '_');
            $udeprels{$udeprel}++;
        }
    }
    close(FILE);
}
# Compute partial scores.
my %score;
#------------------------------------------------------------------------------
# Size. Project size to the interval <0; 1>.
# Do not modify the real number of words, $n. It will be needed in other metrics, too.
my $ntrunc = $n;
$ntrunc = 1000000 if($ntrunc > 1000000);
$ntrunc = 1 if($ntrunc <= 0);
my $lognn = log(($ntrunc/1000)**2); $lognn = 0 if($lognn < 0);
$score{size} = $lognn / log(1000000);
if($verbose)
{
    print STDERR ("Size: counted $ntrunc of $n words (nodes).\n");
    print STDERR ("Size: min(0, log((N/1000)**2)) = $lognn.\n");
    printf STDERR ("Size: maximum value %f is for 1000000 words or more.\n", log(1000000));
}
#------------------------------------------------------------------------------
# Split. This is also very much related to size, but per individual parts.
$score{split} = 0.01;
$score{split} += 0.33 if($ntrain > 10000);
$score{split} += 0.33 if($ndev >= 10000);
$score{split} += 0.33 if($ntest >= 10000);
if($verbose)
{
    if($ntrain > 10000)
    {
        print STDERR ("Split: Found more than 10000 training words.\n");
    }
    else
    {
        print STDERR ("Split: Did not find more than 10000 training words.\n");
    }
    if($ndev >= 10000)
    {
        print STDERR ("Split: Found at least 10000 development words.\n");
    }
    else
    {
        print STDERR ("Split: Did not find at least 10000 development words.\n");
    }
    if($ntest >= 10000)
    {
        print STDERR ("Split: Found at least 10000 test words.\n");
    }
    else
    {
        print STDERR ("Split: Did not find at least 10000 test words.\n");
    }
}
#------------------------------------------------------------------------------
# Lemmas. If the most frequent lemma is '_', we infer that the corpus does not annotate lemmas.
my @lemmas = sort {$lemmas{$b} <=> $lemmas{$a}} (keys(%lemmas));
my $lsource = $metadata->{Lemmas} eq 'manual native' ? 1 : $metadata->{Lemmas} eq 'converted with corrections' ? 0.9 : $metadata->{Lemmas} eq 'converted from manual' ? 0.8 : $metadata->{Lemmas} eq 'automatic with corrections' ? 0.5 : 0.4;
$score{lemmas} = (scalar(@lemmas) < 1 || $lemmas[0] eq '_') ? 0.01 : $lsource;
if($verbose)
{
    if(scalar(@lemmas)<1)
    {
        print STDERR ("Lemmas: No lemmas found.\n");
    }
    elsif($lemmas[0] eq '_')
    {
        print STDERR ("Lemmas: '_' is the most frequent lemma.\n");
    }
    else
    {
        print STDERR ("Lemmas: source of annotation (from README) factor is $lsource.\n");
    }
}
#------------------------------------------------------------------------------
# Tags. How many of the 17 universal POS tags have been seen at least once?
# Some languages may not have use for some tags, and some tags may be very rare.
# But for comparison within one language this is useful. If a tag exists in the
# language but the corpus does not contain it, maybe it cannot distinguish it.
my $tsource = $metadata->{UPOS} eq 'manual native' ? 1 : $metadata->{UPOS} eq 'converted with corrections' ? 0.9 : $metadata->{UPOS} eq 'converted from manual' ? 0.8 : 0.1;
my $maxtags = 17;
$score{tags} = (scalar(keys(%tags)) / $maxtags) * $tsource;
$score{tags} = 0.01 if($score{tags}<0.01);
if($verbose)
{
    printf STDERR ("Universal POS tags: %d out of $maxtags found in the corpus.\n", scalar(keys(%tags)));
    print STDERR ("Universal POS tags: source of annotation (from README) factor is $tsource.\n");
}
#------------------------------------------------------------------------------
# Features. There is no universal rule how many features must be in every language.
# It is only sure that every language can have some features. It may be misleading
# to say that a treebank has features if at least one feature has been observed:
# Some treebanks have just NumType=Card with every NUM but nothing else (and this
# is just a consequence of how Interset works). Therefore we will distinguish several
# very coarse-grained degrees.
my $fsource = $metadata->{Features} eq 'manual native' ? 1 : $metadata->{Features} eq 'converted with corrections' ? 0.9 : $metadata->{Features} eq 'converted from manual' ? 0.8 : $metadata->{Features} eq 'automatic with corrections' ? 0.5 : 0.4;
$score{features} = $n_words_with_features==0 ? 0.01 : $n_words_with_features<$n/3 ? 0.3*$fsource : $n_words_with_features<$n/2 ? 0.5*$fsource : 1*$fsource;
if($verbose)
{
    print STDERR ("Features: $n_words_with_features out of $n total words have one or more features.\n");
    print STDERR ("Features: source of annotation (from README) factor is $fsource.\n");
}
#------------------------------------------------------------------------------
# Dependency relations. How many of the 37 universal relation types have been
# seen at least once? Some languages may not have use for some relations, and
# some relations may be very rare. But for comparison within one language this
# is useful. If a relation exists in the language but the corpus does not
# contain it, maybe it cannot distinguish it.
my $rsource = $metadata->{Relations} eq 'manual native' ? 1 : $metadata->{Relations} eq 'converted with corrections' ? 0.9 : $metadata->{Relations} eq 'converted from manual' ? 0.8 : 0.1;
my $maxudeprels = 37;
$score{udeprels} = (scalar(keys(%udeprels)) / $maxudeprels) * $rsource;
$score{udeprels} = 0.01 if($score{udeprels}<0.01);
if($verbose)
{
    printf STDERR ("Universal relations: %d out of $maxudeprels found in the corpus.\n", scalar(keys(%udeprels)));
    print STDERR ("Universal relations: source of annotation (from README) factor is $rsource.\n");
}
#------------------------------------------------------------------------------
# Udapi MarkBugs (does the content follow the guidelines?)
# Measured only if the corpus is not empty and if udapy is found at the expected place.
if($n > 0)
{
    $score{udapi} = 1;
    my $command = get_udapi_command($folder);
    if(defined($command))
    {
        my $output = `$command`;
        my $nbugs = 0;
        my $maxwordsperbug = 10; # if there are more bugs than every n-th word, we will count maximum error rate
        if($output =~ m/(\d+)/)
        {
            $nbugs = $1;
            # Evaluate the proportion of bugs to the size of the treebank
            # (with a ceiling defined by $maxwordsperbug; anything above is considered "absolutely bad").
            my $nbugs1 = $nbugs>$n/$maxwordsperbug ? $n/$maxwordsperbug : $nbugs;
            $score{udapi} = 1-$nbugs1/($n/$maxwordsperbug);
            $score{udapi} = 0.01 if($score{udapi}<0.01);
        }
        if($verbose)
        {
            print STDERR ("Udapi: found $nbugs bugs.\n");
            print STDERR ("Udapi: worst expected case (threshold) is one bug per $maxwordsperbug words. There are $n words.\n");
        }
    }
    elsif($verbose)
    {
        print STDERR ("WARNING: Udapi not found. The content-based tests were not performed.\n");
        print STDERR ("         In order to get a full evaluation, you need to:\n");
        print STDERR ("         1. Put this script in the current folder:\n");
        print STDERR ("            https://github.com/UniversalDependencies/docs-automation/blob/master/valdan/udapi-markbugs.sh\n");
        print STDERR ("         2. Install Python version of Udapi.\n");
        print STDERR ("         3. Copy udapi-python and pythonlib to the current folder, as indicated in udapi-markbugs.sh.\n");
    }
}
else
{
    $score{udapi} = 0;
}
#------------------------------------------------------------------------------
# Genres. Idea: an attempt at a balance of many genres provides for a more
# versatile dataset. Of course this is just an approximation. We cannot verify
# how well the authors described the genres in their corpus and how much they
# managed to make it balanced. We look only for the listed, "officially known"
# genres. (Sometimes there are typos in the READMEs and besides "news", people
# also use "new" or "newswire"; this is undesirable.)
my @official_genres = ('academic', 'bible', 'blog', 'email', 'fiction', 'grammar-examples', 'learner-essays', 'legal', 'medical', 'news', 'nonfiction', 'poetry', 'reviews', 'social', 'spoken', 'web', 'wiki');
my @genres = grep {my $g = $_; scalar(grep {$_ eq $g} (@official_genres));} (split(/\s+/, $metadata->{Genre}));
my $ngenres = scalar(@genres);
$ngenres = 1 if($ngenres<1);
$score{genres} = $ngenres / scalar(@official_genres);
if($verbose)
{
    printf STDERR ("Genres: found %d out of %d known.\n", $ngenres, scalar(@official_genres));
}
#------------------------------------------------------------------------------
# Evaluate availability. If the most frequent form is '_', we infer that the
# corpus does not contain the underlying text (which is done for copyright reasons;
# the user must obtain the underlying text elsewhere and merge it with UD annotation).
my @forms = sort {$forms{$b} <=> $forms{$a}} (keys(%forms));
# At the same time, such corpora should be also labeled in the README metadata
# item "Includes text".
my $availability = $metadata->{'Includes text'} !~ m/^yes$/i || scalar(@forms) < 1 || $forms[0] eq '_' ? 0.1 : 1;
if($verbose)
{
    if($metadata->{'Includes text'} !~ m/^yes$/i)
    {
        print STDERR ("Availability: README does not say Includes text: yes\n");
    }
    if(scalar(@forms) < 1)
    {
        print STDERR ("Availability: No words found.\n");
    }
    elsif($forms[0] eq '_')
    {
        print STDERR ("Availability: '_' is the most frequent form.\n");
    }
}
#------------------------------------------------------------------------------
# Evaluate validity. Formally invalid data should get a score close to zero.
my $folder_success = 1;
foreach my $file (@{$record->{files}})
{
    my $command = get_validator_command($folder, $file, $record->{lcode});
    if(defined($command))
    {
        system("echo $command");
        my $result = saferun("$command 2>&1");
        $folder_success = $folder_success && $result;
    }
    elsif($verbose)
    {
        print STDERR ("WARNING: Validator not found. We will assume that all files are valid.\n");
        last;
    }
}
my $validity = $folder_success ? 1 : 0.01;
if($verbose)
{
    print STDERR ("Validity: $validity\n");
}
#------------------------------------------------------------------------------
# Score of empty treebanks should be zero regardless of the other features.
my $score = 0;
if($n > 1)
{
    my %weights =
    (
        'size'     => 10,
        'split'    => 2,
        'lemmas'   => 3,
        'tags'     => 3,
        'features' => 3,
        'udeprels' => 3,
        'udapi'    => 12,
        'genres'   => 3
    );
    my @dimensions = sort(keys(%weights));
    my $wsum = 0;
    foreach my $d (@dimensions)
    {
        $wsum += $weights{$d};
    }
    foreach my $d (@dimensions)
    {
        my $nweight = $weights{$d} / $wsum;
        $score += $nweight * $score{$d};
        if($verbose)
        {
            my $wscore = $nweight * $score{$d};
            print STDERR ("(weight=$nweight) * (score{$d}=$score{$d}) = $wscore\n");
        }
    }
    # The availability and validity dimensions are show stoppers. Instead of weighted combination, we multiply the score by them.
    if($verbose)
    {
        print STDERR ("(TOTAL score=$score) * (availability=$availability) * (validity=$validity) = ");
    }
    $score *= $availability * $validity;
    if($verbose)
    {
        print STDERR ("$score\n");
    }
}
my $stars = sprintf("%d", $score*10+0.5)/2;
if($verbose)
{
    print STDERR ("STARS = $stars\n");
}
print("$folder\t$score\t$stars\n");
# When we are done we must switch the repository back from master to the dev branch.
# (Provided we actually switched it to master. And ignoring the possibility that there is a third branch or that it already was in master when we came.)
if($forcemaster)
{
    ###!!! At present we ignore the fact that multiple CGI processes may attempt to
    ###!!! fiddle with the repository at the same time! When that happens, the output
    ###!!! will be wrong!
    system("cd $folder ; (git checkout dev 1>&2) ; cd ..");
}



#------------------------------------------------------------------------------
# Figures out whether the UD validator is available and how to invoke it.
#------------------------------------------------------------------------------
sub get_validator_command
{
    my $folder = shift;
    my $file = shift;
    my $lcode = shift;
    my $command;
    # If evaluation runs under a CGI script on quest, validation must be called through an envelope script.
    if(-x './validate.sh')
    {
        $command = "./validate.sh --lang $lcode --max-err=10 $folder/$file";
    }
    elsif(which('validate.py'))
    {
        $command = "validate.py --lang $lcode --max-err=10 $folder/$file";
    }
    return $command;
}



#------------------------------------------------------------------------------
# Figures out whether Udapi is available and how to invoke it.
#------------------------------------------------------------------------------
sub get_udapi_command
{
    my $folder = shift;
    my $command;
    # If evaluation runs under a CGI script on quest, Udapi must be called through an envelope script.
    if(-x './udapi-markbugs.sh')
    {
        $command = "(cat $folder/*.conllu | ./udapi-markbugs.sh 2>&1) | grep TOTAL";
    }
    elsif(which('udapy'))
    {
        $command = "(cat $folder/*.conllu | udapy ud.MarkBugs 2>&1) | grep TOTAL";
    }
    return $command;
}



#------------------------------------------------------------------------------
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# This function comes from Dan's library dzsys. I do not want to depend on that
# library here, so I am copying the function. I have also modified it so that
# it does not throw exceptions.
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# Calls an external program. Uses system(). In addition, echoes the command
# line to the standard error output, and returns true/false according to
# whether the call was successful and the external program returned 0 (success)
# or non-zero (error).
#
# Typically called as follows:
#     saferun($command) or die;
#------------------------------------------------------------------------------
sub saferun
{
    my $command = join(' ', @_);
    #my $ted = cas::ted()->{datumcas};
    #print STDERR ("[$ted] Executing: $command\n");
    system($command);
    # The external program does not exist, is not executable or the execution failed for other reasons.
    if($?==-1)
    {
        print STDERR ("ERROR: Failed to execute: $command\n  $!\n");
        return;
    }
    # We were able to start the external program but its execution failed.
    elsif($? & 127)
    {
        printf STDERR ("ERROR: Execution of: $command\n  died with signal %d, %s coredump\n",
            ($? & 127), ($? & 128) ? 'with' : 'without');
        return;
    }
    # The external program ended "successfully" (this still does not guarantee
    # that the external program returned zero!)
    else
    {
        my $exitcode = $? >> 8;
        print STDERR ("Exit code: $exitcode\n") if($exitcode);
        # Return false if the program returned a non-zero value.
        # It is up to the caller how they will handle the return value.
        # (The easiest is to always write:
        # saferun($command) or die;
        # )
        return ! $exitcode;
    }
}
