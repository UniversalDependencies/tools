#!/usr/bin/env perl
# Calls conllu-stats.pl for all sets of treebanks that need comparison.
# Copyright © 2017, 2021 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
# Make sure that the tools folder is searched for Perl modules. Then use udlib from there.
# Without it, we could not run this script from other folders.
BEGIN
{
    our $toolsdir = $0;
    unless($toolsdir =~ s:[/\\][^/\\]*$::)
    {
        $toolsdir = '.';
    }
}
use lib "$toolsdir";
use udlib;

sub usage
{
    print STDERR ("Usage: perl generate_comparison_of_treebanks.pl [UD_XXX, UD_YYY, ...]\n");
    print STDERR ("       Generates a MarkDown page with comparison of treebanks in each language where there are multiple treebanks.\n");
    print STDERR ("       Saves the page in docs/treebanks/$LCODE-comparison.md.\n");
    print STDERR ("       If no UD folders are provided as arguments, scans all UD_* subfolders of the current folder.\n");
}

my $languages = udlib::get_language_hash();
my @folders;
if(scalar(@ARGV) > 0)
{
    @folders = sort(@ARGV);
}
else
{
    @folders = udlib::list_ud_folders(); # the list comes sorted
}
my $current_language;
my @current_group;
foreach my $folder (@folders)
{
    # Skip empty folders.
    my $tbkrecord = udlib::get_ud_files_and_codes($folder);
    next if(scalar(@{$tbkrecord->{files}})==0);
    my $language = $folder;
    $language =~ s/^UD_//;
    $language =~ s/-.*//;
    $language =~ s/_/ /g;
    if(defined($current_language) && $language eq $current_language)
    {
        push(@current_group, $folder);
    }
    else
    {
        if(scalar(@current_group)>1)
        {
            if(!exists($languages->{$current_language}))
            {
                print STDERR ("WARNING: Unknown language $current_language\n");
            }
            my $folders = join(' ', @current_group);
            my $command = "perl tools/conllu-stats.pl --oformat hubcompare $folders > docs/treebanks/$languages->{$current_language}{lcode}-comparison.md";
            print("$command\n");
            system($command);
        }
        $current_language = $language;
        @current_group = ($folder);
    }
}
if(scalar(@current_group)>1)
{
    if(!exists($languages->{$current_language}))
    {
        print STDERR ("WARNING: Unknown language $current_language\n");
    }
    my $folders = join(' ', @current_group);
    my $command = "perl tools/conllu-stats.pl --oformat hubcompare $folders > docs/treebanks/$languages->{$current_language}{lcode}-comparison.md";
    print("$command\n");
    system($command);
}
