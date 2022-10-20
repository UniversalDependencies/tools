#!/usr/bin/env perl
# Scans all treebanks of one language for occurrences of a particular morphological
# feature and summarizes the values that are used. The output may be used to identify
# harmonization needs.
# Copyright © 2022 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
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
    print STDERR ("Usage: $0 --udpath <path-to-ud> --lang <lcode> --feat <feature>\n");
    print STDERR ("       <path-to-ud> is the path to the folder where all UD treebanks reside; default: current folder\n");
    print STDERR ("       <lcode> is an ISO 639 code, either two-letter (639-1), or three-letter (639-3), as used in the UD infrastructure\n");
    print STDERR ("       <feature> is the UD feature name to investigate\n");
}

my $udpath = '.';
my $lcode;
my $feature;
GetOptions
(
    'udpath=s'   => \$udpath,
    'language=s' => \$lcode, # it's fine to use just 'lang'
    'feature=s'  => \$feature # it's fine to use just 'feat'
);
if(!defined($lcode))
{
    usage();
    die("Missing language code");
}
if(!defined($feature))
{
    usage();
    die("Missing feature name");
}

# Find treebanks of the given language.
my $languages = udlib::get_language_hash("$udpath/docs-automation/codes_and_flags.yaml");
my @matching_languages = grep {$languages->{$_}{lcode} eq $lcode || $languages->{$_}{iso3} eq $lcode} (keys(%{$languages}));
if(scalar(@matching_languages) == 0)
{
    die("Unknown language code '$lcode'");
}
my $lname = $matching_languages[0];
$lname =~ s/ /_/g;
my @folders = sort {lc($a) cmp lc($b)} (grep {m/^UD_$lname-/} (udlib::list_ud_folders($udpath)));
if(scalar(@folders) == 0)
{
    die("No treebanks of language '$lname' found");
}
# Scan the treebanks for the values of all features.
my %hash;
foreach my $folder (@folders)
{
    print STDERR ("Scanning '$folder'...\n");
    ###!!! Note that the following function decomposes multivalues, e.g., PronType=Int,Rel will be counted as PronType=Int + PronType=Rel.
    ###!!! For the purposes of this script we may actually prefer to see that a multivalue was used.
    udlib::collect_features_from_ud_folder("$udpath/$folder", \%hash, $folder);
}
if(!exists($hash{$feature}))
{
    print("The feature '$feature' does not occur in any treebank of language '$lcode'.\n");
}
else
{
    my @values = sort(keys(%{$hash{$feature}}));
    my @table;
    $table[0] = ['', @values];
    foreach my $folder (@folders)
    {
        push(@table, [$folder, map {$hash{$feature}{$_}{$folder}} (@values)]);
    }
    push(@table, ['TOTAL', map {$hash{$feature}{$_}{TOTAL}} (@values)]);
    print_table(scalar(@table), scalar(@values)+1, @table);
}



#------------------------------------------------------------------------------
# Prints a table of M rows and N columns. Pads columns with spaces.
#------------------------------------------------------------------------------
sub print_table
{
    my $m = shift;
    my $n = shift;
    my @table = @_;
    # Find the maximum length of a value in each column.
    my @lengths;
    for(my $j = 0; $j < $n; $j++)
    {
        for(my $i = 0; $i < $m; $i++)
        {
            my $l = length($table[$i][$j]);
            if($l > $lengths[$j])
            {
                $lengths[$j] = $l;
            }
        }
    }
    # Now print it.
    for(my $i = 0; $i < $m; $i++)
    {
        for(my $j = 0; $j < $n; $j++)
        {
            print(' ') if($j>0);
            my $l = length($table[$i][$j]);
            my $pad = ' ' x ($lengths[$j]-$l);
            my $string = $table[$i][$j] =~ m/^[-+0-9\.,]+$/ ? $pad.$table[$i][$j] : $table[$i][$j].$pad;
            print($string);
        }
        print("\n");
    }
}
