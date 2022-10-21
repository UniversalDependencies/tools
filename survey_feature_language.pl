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
    print STDERR ("       <lcode> is an ISO 639 code, either two-letter (639-1), or three-letter (639-3), as used in the UD infrastructure; or multiple codes, comma-separated\n");
    print STDERR ("       alternatively, languages can be specified as --family Slavic\n");
    print STDERR ("       <feature> is the UD feature name to investigate\n");
}

my $udpath = '.';
my $lcodes;
my $family;
my $feature;
GetOptions
(
    'udpath=s'    => \$udpath,
    'languages=s' => \$lcodes, # it's fine to use just 'lang'
    'family=s'    => \$family, # instead or in addition to languages, regex for family and/or genus
    'feature=s'   => \$feature # it's fine to use just 'feat'
);
if(!defined($lcodes) && !defined($family))
{
    usage();
    die("Missing language code");
}
if(!defined($feature))
{
    usage();
    die("Missing feature name");
}

# Find treebanks of the given languages.
my @lcodes = split(/,/, $lcodes);
my $languages = udlib::get_language_hash("$udpath/docs-automation/codes_and_flags.yaml");
my @matching_languages;
foreach my $lname (keys(%{$languages}))
{
    if(scalar(grep {$_ eq $languages->{$lname}{lcode} || $_ eq $languages->{$lname}{iso3}} (@lcodes)) ||
       defined($family) && $languages->{$lname}{family} =~ m/$family/)
    {
        my $lname_with_underscores = $lname;
        $lname_with_underscores =~ s/ /_/g;
        push(@matching_languages, $lname_with_underscores);
    }
}
if(scalar(@matching_languages) == 0)
{
    die("No language matching '$lcodes'");
}
my $lname_regex = join('|', @matching_languages);
my @folders = sort {lc($a) cmp lc($b)} (grep {m/^UD_($lname_regex)-/} (udlib::list_ud_folders($udpath)));
if(scalar(@folders) == 0)
{
    die("No treebanks matching language(s) '$lname' found");
}
# Scan the treebanks for the values of all features.
my %hash;
foreach my $folder (@folders)
{
    print STDERR ("Scanning '$folder'...\n");
    ###!!! Note that the following function decomposes multivalues, e.g., PronType=Int,Rel will be counted as PronType=Int + PronType=Rel.
    ###!!! For the purposes of this script we may actually prefer to see that a multivalue was used.
    #udlib::collect_features_from_ud_folder("$udpath/$folder", \%hash, $folder, 1);
    collect_features_from_ud_folder_by_upos("$udpath/$folder", \%hash, $folder, 1);
}
if(!exists($hash{ANYPOS}{$feature}))
{
    print("The feature '$feature' does not occur in any treebank of language '$lcode'.\n");
}
else
{
    my @values = sort(keys(%{$hash{ANYPOS}{$feature}}));
    my @table;
    $table[0] = ['', @values];
    foreach my $folder (@folders)
    {
        push(@table, [$folder, map {$hash{ANYPOS}{$feature}{$_}{$folder}} (@values)]);
    }
    push(@table, ['TOTAL', map {$hash{ANYPOS}{$feature}{$_}{TOTAL}} (@values)]);
    print_table(scalar(@table), scalar(@values)+1, @table);
    # Print a separate table for each UPOS with which the feature occurs.
    foreach my $upos (sort(keys(%{$hash{BYUPOS}{$feature}})))
    {
        my @values = ('EMPTY', sort(keys(%{$hash{BYUPOS}{$feature}{$upos}})));
        my @table;
        $table[0] = [$upos, @values];
        foreach my $folder(@folders)
        {
            # Compute how many times the value of this feature was empty.
            my $n_nonempty = 0;
            foreach my $value (@values)
            {
                unless($value eq 'EMPTY')
                {
                    $n_nonempty += $hash{BYUPOS}{$feature}{$upos}{$value}{$folder};
                }
            }
            $hash{BYUPOS}{$feature}{$upos}{EMPTY}{$folder} = $hash{UPOS}{$upos}{$folder}-$n_nonempty;
            $hash{BYUPOS}{$feature}{$upos}{EMPTY}{TOTAL} += $hash{UPOS}{$upos}{$folder}-$n_nonempty;
            push(@table, [$folder, map {$hash{BYUPOS}{$feature}{$upos}{$_}{$folder}} (@values)]);
        }
        push(@table, ['TOTAL', map {$hash{BYUPOS}{$feature}{$upos}{$_}{TOTAL}} (@values)]);
        print("\n");
        print_table(scalar(@table), scalar(@values)+1, @table);
    }
}



#------------------------------------------------------------------------------
# Reads a CoNLL-U file and collects statistics about features, organized by
# UPOS categories with which they occur. Note that there is a similarly named
# function in udlib.pm but it does not split the statistics by UPOS. Eventually
# we may want to make this version available in udlib and make the system of
# scanning languages, treebanks and files more general.
#------------------------------------------------------------------------------
sub collect_features_from_conllu_file_by_upos
{
    my $file = shift; # relative or full path
    my $hash = shift; # ref to hash where the statistics are collected
    my $key = shift; # identification of the current dataset in the hash (e.g. language code)
    my $multivalues = shift; # if true, multivalues (e.g. PronType=Int,Rel) will not be split
    open(FILE, $file) or die("Cannot read $file: $!");
    while(<FILE>)
    {
        if(m/^\d+\t/)
        {
            chomp();
            my @fields = split(/\t/, $_);
            my $upos = $fields[3];
            $hash->{UPOS}{$upos}{$key}++;
            my $features = $fields[5];
            unless($features eq '_')
            {
                my @features = split(/\|/, $features);
                foreach my $feature (@features)
                {
                    my ($f, $vv) = split(/=/, $feature);
                    # There may be several values delimited by commas.
                    my @values;
                    if($multivalues)
                    {
                        $values[0] = $vv;
                    }
                    else
                    {
                        @values = split(/,/, $vv);
                    }
                    foreach my $v (@values)
                    {
                        $hash->{ANYPOS}{$f}{$v}{$key}++;
                        $hash->{ANYPOS}{$f}{$v}{TOTAL}++;
                        $hash->{BYUPOS}{$f}{$upos}{$v}{$key}++;
                        $hash->{BYUPOS}{$f}{$upos}{$v}{TOTAL}++;
                    }
                }
            }
        }
    }
    return $hash;
}



#------------------------------------------------------------------------------
# Reads all CoNLL-U files in a folder and collects statistics about features.
#------------------------------------------------------------------------------
sub collect_features_from_ud_folder_by_upos
{
    my $udfolder = shift; # relative or full path
    my $hash = shift; # ref to hash where the statistics are collected
    my $key = shift; # identification of the current dataset in the hash (e.g. language code)
    my $multivalues = shift; # if true, multivalues (e.g. PronType=Int,Rel) will not be split
    opendir(DIR, $udfolder) or die("Cannot read the contents of '$udfolder': $!");
    my @files = sort(grep {-f "$udfolder/$_" && m/.+\.conllu$/} (readdir(DIR)));
    closedir(DIR);
    foreach my $file (@files)
    {
        collect_features_from_conllu_file_by_upos("$udfolder/$file", $hash, $key, $multivalues);
    }
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
