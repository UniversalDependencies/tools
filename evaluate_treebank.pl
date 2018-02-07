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
use udlib;

# Path to the local copy of the UD repository (e.g., UD_Czech).
my $folder = $ARGV[0];
if(!defined($folder))
{
    die("Usage: $0 path-to-ud-folder");
}
my $record = udlib::get_ud_files_and_codes($folder);
my $n = 0;
foreach my $file (@{$record->{files}})
{
    open(FILE, "$folder/$file") or die("Cannot read $folder/$file: $!");
    while(<FILE>)
    {
        if(m/^\d+\t/)
        {
            $n++;
        }
    }
    close(FILE);
}
# Project size to the interval <0; 1>.
$n = 1000000 if($n > 1000000);
$n = 1 if($n <= 0);
my $lognn = log(($n/1000)**2); $lognn = 0 if($lognn < 0);
my $size = $lognn / log(1000000);
#my $size = log($n*$n)/log(1000000000000);
my $stars = sprintf("%d", $size*10+0.5)/2;
print("words = $n; size = $size (i.e. $stars stars)\n");
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
my $score = $availability * $size;
$stars = sprintf("%d", $score*10+0.5)/2;
print("availability = $availability\n");
print("score = $score (i.e. $stars stars)\n");
