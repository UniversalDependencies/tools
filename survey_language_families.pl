#!/usr/bin/env perl
# Reads all UD treebanks in the UD folder, counts regular nodes (i.e. syntactic
# words/tokens) in all of them. Skips treebanks that do not contain the under-
# lying texts. Prints the counts grouped by language family.
# Copyright © 2023 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
use udlib;

sub usage
{
    print STDERR ("Usage: $0 --udpath /data/udreleases/2.12 --langyaml /data/ud/docs-automation/codes_and_flags.yaml\n");
}

#my $udpath = 'C:/Users/Dan/Documents/Lingvistika/Projekty/universal-dependencies';
my $udpath = '/net/data/universal-dependencies-2.12';
my $langyamlpath = '/net/work/people/zeman/unidep/docs-automation/codes_and_flags.yaml';
GetOptions
(
    'udpath=s' => \$udpath,
    'langyaml=s' => \$langyamlpath
);

my $languages = udlib::get_language_hash($langyamlpath);
my @folders = udlib::list_ud_folders($udpath);
my %family_words;
my %iegenus_words;
my $nwords = 0;
foreach my $folder (@folders)
{
    my ($language, $treebank) = udlib::decompose_repo_name($folder);
    if(!exists($languages->{$language}))
    {
        print STDERR ("Skipping $folder because language $language is unknown.\n");
        next;
    }
    my $metadata = udlib::read_readme($folder, $udpath);
    if($metadata->{'Includes text'} !~ m/^y/i)
    {
        print STDERR ("Skipping $folder because it lacks underlying text.\n");
        next;
    }
    print STDERR ("Reading $folder...\n");
    my $ltcode = udlib::get_ltcode_from_repo_name($folder, $languages);
    my $stats = udlib::collect_statistics_about_ud_treebank("$udpath/$folder", $ltcode);
    my $family = $languages->{$language}{family};
    $family =~ s/, (.*)//;
    my $genus = $1;
    $family = 'Indo-European' if($family eq 'IE');
    $family_words{$family} += $stats->{nword};
    if($family eq 'Indo-European')
    {
        $iegenus_words{$genus} += $stats->{nword};
    }
    $nwords += $stats->{nword};
}
# Print the statistics.
my @families = sort {$family_words{$b} <=> $family_words{$a}} (keys(%family_words));
foreach my $family (@families)
{
    printf("%s\t%d\t%d %%\n", $family, $family_words{$family}, $family_words{$family}/$nwords*100+0.5);
}
my @genuses = sort {$iegenus_words{$b} <=> $iegenus_words{$a}} (keys(%iegenus_words));
foreach my $genus (@genuses)
{
    printf("%s\t%d\t%d %%\n", $genus, $iegenus_words{$genus}, $iegenus_words{$genus}/$family_words{'Indo-European'}*100+0.5);
}
