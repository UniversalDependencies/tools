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

# Path to the local copy of the UD repository (e.g., UD_Czech).
my $folder = $ARGV[0];
if(!defined($folder))
{
    die("Usage: $0 path-to-ud-folder");
}
my $record = get_ud_files_and_codes($folder);
my $n = 0;
my $ntrain = 0;
my $ndev = 0;
my $ntest = 0;
my %lemmas;
my $n_words_with_features = 0;
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
            my $feat = $f[5];
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
            $lemmas{$lemma}++;
            $n_words_with_features++ if($feat ne '_');
        }
    }
    close(FILE);
}
# Compute partial scores.
my %score;
#------------------------------------------------------------------------------
# Size. Project size to the interval <0; 1>.
$n = 1000000 if($n > 1000000);
$n = 1 if($n <= 0);
my $lognn = log(($n/1000)**2); $lognn = 0 if($lognn < 0);
$score{size} = $lognn / log(1000000);
#------------------------------------------------------------------------------
# Split. This is also very much related to size, but per individual parts.
$score{split} = 0.01;
$score{split} += 0.33 if($ntrain > 10000);
$score{split} += 0.33 if($ndev >= 10000);
$score{split} += 0.33 if($ntest >= 10000);
#------------------------------------------------------------------------------
# Lemmas. If the most frequent lemma is '_', we infer that the corpus does not annotate lemmas.
my @lemmas = sort {$lemmas{$b} <=> $lemmas{$a}} (keys(%lemmas));
$score{lemmas} = (scalar(@lemmas) < 1 || $lemmas[0] eq '_') ? 0.01 : 1;
#------------------------------------------------------------------------------
# Features. There is no universal rule how many features must be in every language.
# It is only sure that every language can have some features. It may be misleading
# to say that a treebank has features if at least one feature has been observed:
# Some treebanks have just NumType=Card with every NUM but nothing else (and this
# is just a consequence of how Interset works). Therefore we will distinguish several
# very coarse-grained degrees.
$score{features} = $n_words_with_features==0 ? 0.01 : $n_words_with_features<$n/3 ? 0.3 : $n_words_with_features<$n/2 ? 0.5 : 1;
#------------------------------------------------------------------------------
# Evaluate availability.
###!!! We should read the information from the README file and verify in the data that '_' is not the most frequent word form!
###!!! However, currently it is hardcoded here, based on language-treebank code.
my $availability = 1;
if($record->{ltcode} =~ m/^(ja_ktc|en_esl|ko_sejong|ar_nyuad)$/)
{
    # These treebanks are not available for free.
    $availability = 0.01;
}
elsif($record->{ltcode} eq 'fr_ftb')
{
    # This treebank is available for free but the user must obtain it separately.
    $availability = 0.1;
}
#------------------------------------------------------------------------------
# Score of empty treebanks should be zero regardless of the other features.
my $score = 0;
if($n > 1)
{
    my %weights =
    (
        'size'     => 7,
        'split'    => 1,
        'lemmas'   => 3,
        'features' => 3
    );
    my @dimensions = keys(%weights);
    my $wsum = 0;
    foreach my $d (@dimensions)
    {
        $wsum += $weights{$d};
    }
    foreach my $d (@dimensions)
    {
        my $nweight = $weights{$d} / $wsum;
        $score += $nweight * $score{$d};
    }
    # The availability dimension is a show stopper. Instead of weighted combination, we multiply the score by it.
    $score *= $availability;
}
my $stars = sprintf("%d", $score*10+0.5)/2;
print("$folder\t$score\t$stars\n");



#==============================================================================
# The following functions are available in tools/udlib.pm. However, udlib uses
# JSON::Parse, which is not installed on quest, so we cannot use it here.
#==============================================================================



#------------------------------------------------------------------------------
# Scans a UD folder for CoNLL-U files. Uses the file names to guess the
# language code.
#------------------------------------------------------------------------------
sub get_ud_files_and_codes
{
    my $udfolder = shift; # e.g. "UD_Czech"; not the full path
    my $path = shift; # path to the superordinate folder; default: the current folder
    $path = '.' if(!defined($path));
    my $name;
    my $langname;
    my $tbkext;
    if($udfolder =~ m/^UD_(([^-]+)(?:-(.+))?)$/)
    {
        $name = $1;
        $langname = $2;
        $tbkext = $3;
        $langname =~ s/_/ /g;
    }
    else
    {
        print STDERR ("WARNING: Unexpected folder name '$udfolder'\n");
    }
    # Look for training, development or test data.
    my $section = 'any'; # training|development|test|any
    my %section_re =
    (
        # Training data in UD_Czech are split to four files.
        'training'    => 'train(-[clmv])?',
        'development' => 'dev',
        'test'        => 'test',
        'any'         => '(train(-[clmv])?|dev|test)'
    );
    opendir(DIR, "$path/$udfolder") or die("Cannot read the contents of '$path/$udfolder': $!");
    my @files = sort(grep {-f "$path/$udfolder/$_" && m/.+-ud-$section_re{$section}\.conllu$/} (readdir(DIR)));
    closedir(DIR);
    my $n = scalar(@files);
    my $code;
    my $lcode;
    my $tcode;
    if($n==0)
    {
    }
    else
    {
        if($n>1 && $section ne 'any')
        {
            print STDERR ("WARNING: Folder '$path/$udfolder' contains multiple ($n) files that look like $section data.\n");
        }
        $files[0] =~ m/^(.+)-ud-$section_re{$section}\.conllu$/;
        $lcode = $code = $1;
        if($code =~ m/^([^_]+)_(.+)$/)
        {
            $lcode = $1;
            $tcode = $2;
        }
    }
    my %record =
    (
        'folder' => $udfolder,
        'name'   => $name,
        'lname'  => $langname,
        'tname'  => $tbkext,
        'code'   => $code,
        'ltcode' => $code, # for compatibility with some tools, this code is provided both as 'code' and as 'ltcode'
        'lcode'  => $lcode,
        'tcode'  => $tcode,
        'files'  => \@files,
        $section => $files[0]
    );
    #print STDERR ("$udfolder\tlname $langname\ttname $tbkext\tcode $code\tlcode $lcode\ttcode $tcode\t$section $files[0]\n");
    return \%record;
}
