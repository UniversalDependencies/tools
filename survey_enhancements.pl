#!/usr/bin/env perl
# Scans all UD treebanks for enhancement types in enhanced UD graphs.
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
# We need to tell Perl where to find my UD and graph modules.
BEGIN
{
    use Cwd;
    my $path = $0;
    my $currentpath = getcwd();
    $currentpath =~ s/\r?\n$//;
    $libpath = $currentpath;
    if($path =~ m:/:)
    {
        $path =~ s:/[^/]*$:/:;
        chdir($path);
        $libpath = getcwd();
        chdir($currentpath);
    }
    $libpath =~ s/\r?\n$//;
    #print STDERR ("libpath=$libpath\n");
}
use lib $libpath;
use udlib;

sub usage
{
    print STDERR ("Usage: perl survey_enhancements.pl --datapath /net/projects/ud --tbklist udsubset.txt\n");
    print STDERR ("       --datapath ... path to the folder where all UD_* treebank repositories reside\n");
    print STDERR ("       --tbklist .... file with list of UD_* folders to consider (e.g. treebanks we are about to release)\n");
    print STDERR ("                      if tbklist is not present, all treebanks in datapath will be scanned\n");
}

my $datapath = '.';
my $tbklist;
GetOptions
(
    'datapath=s' => \$datapath, # UD_* folders will be sought in this folder
    'tbklist=s'  => \$tbklist   # path to file with treebank list; if defined, only treebanks on the list will be surveyed
);
my %treebanks;
if(defined($tbklist))
{
    open(TBKLIST, $tbklist) or die("Cannot read treebank list from '$tbklist': $!");
    while(<TBKLIST>)
    {
        s/^\s+//;
        s/\s+$//;
        my @treebanks = split(/\s+/, $_);
        foreach my $t (@treebanks)
        {
            $t =~ s:/$::;
            $treebanks{$t}++;
        }
    }
    close(TBKLIST);
}

opendir(DIR, $datapath) or die("Cannot read the contents of '$datapath': $!");
my @folders = sort(grep {-d "$datapath/$_" && m/^UD_[A-Z]/} (readdir(DIR)));
closedir(DIR);
my $n = scalar(@folders);
print STDERR ("Found $n UD folders in '$datapath'.\n");
if(defined($tbklist))
{
    my $n = scalar(keys(%treebanks));
    print STDERR ("We will only scan those listed in $tbklist (the list contains $n treebanks but we have not checked yet which of them exist in the folder).\n");
}
else
{
    print STDERR ("Warning: We will scan them all, whether their data is valid or not!\n");
}
if($datapath eq '.')
{
    print STDERR ("Use the --datapath option to scan a different folder with UD treebanks.\n");
}
sleep(5);
# We need a mapping from the English names of the languages (as they appear in folder names) to their ISO codes.
# There is now also the new list of languages in YAML in docs-automation; this one has also language families.
my $languages_from_yaml = udlib::get_language_hash("$libpath/../docs-automation/codes_and_flags.yaml");
my %langnames;
my %langcodes;
foreach my $language (keys(%{$languages_from_yaml}))
{
    # We need a mapping from language names in folder names (contain underscores instead of spaces) to language codes.
    # Language names in the YAML file may contain spaces (not underscores).
    my $usname = $language;
    $usname =~ s/ /_/g;
    $langcodes{$usname} = $languages_from_yaml->{$language}{lcode};
    $langnames{$languages_from_yaml->{$language}{lcode}} = $language;
}
# Look for features in the data.
my %hash;
my %hitlanguages;
foreach my $folder (@folders)
{
    # If we received the list of treebanks to be released, skip all other treebanks.
    if(defined($tbklist) && !exists($treebanks{$folder}))
    {
        next;
    }
    # The name of the folder: 'UD_' + language name + optional treebank identifier.
    # Example: UD_Ancient_Greek-PROIEL
    my $language = '';
    my $treebank = '';
    my $langcode;
    my $key;
    if($folder =~ m/^UD_([A-Za-z_]+)(?:-([A-Za-z]+))?$/)
    {
        print STDERR ("$folder\n");
        $language = $1;
        $treebank = $2 if(defined($2));
        if(exists($langcodes{$language}))
        {
            $langcode = $langcodes{$language};
            $key = $langcode;
            $key .= '_'.lc($treebank) if($treebank ne '');
            my $nhits = 0;
            chdir("$datapath/$folder") or die("Cannot enter folder '$datapath/$folder': $!");
            # Collect enhanced graph properties from all CoNLL-U files in the folder using a dedicated script.
            my $command = "cat *.conllu | $libpath/enhanced_graph_properties.pl";
            open(PROPERTIES, "$command |") or die("Cannot run and read output of '$command': $!");
            while(<PROPERTIES>)
            {
                s/\r?\n$//;
                # We are looking for the following six lines:
                # * Gapping:             0
                # * Coord shared parent: 1145
                # * Coord shared depend: 407
                # * Controlled subject:  698
                # * Relative clause:     0
                # * Deprel with case:    55
                if(m/^\*\s*(.+):\s*(\d+)$/)
                {
                    my $property = $1;
                    my $count = $2;
                    $hash{$folder}{$property} = $count;
                    if($property ne 'Edge basic only' && $count>0)
                    {
                        $hash{$folder}{hit}++;
                        $hitlanguages{$langcode}++;
                    }
                }
            }
            close(PROPERTIES);
        }
    }
}
my $n_languages_something = scalar(keys(%hitlanguages));
my $n_treebanks_something = 0;
my $n_treebanks_everything = 0;
my @treebanks = sort(keys(%hash));
my $maxlength;
foreach my $treebank (@treebanks)
{
    my $l = length($treebank);
    if(!defined($maxlength) || $l > $maxlength)
    {
        $maxlength = $l;
    }
}
foreach my $treebank (@treebanks)
{
    if($hash{$treebank}{hit})
    {
        $n_treebanks_something++;
        my $g = $hash{$treebank}{'Gapping'};
        my $p = $hash{$treebank}{'Coord shared parent'};
        my $s = $hash{$treebank}{'Coord shared depend'};
        my $x = $hash{$treebank}{'Controlled subject'};
        my $r = $hash{$treebank}{'Relative clause'};
        my $c = $hash{$treebank}{'Deprel with case'};
        my $all = '';
        if($g>0 && $p>0 && $s>0 && $x>0 && $r>0 && $c>0)
        {
            $all = '*';
            $n_treebanks_everything++;
        }
        print(pad($treebank.$all, $maxlength+1), "\t");
        print(pad("EB=$hash{$treebank}{'Edge basic only'}", 10), "\t");
        print(pad("EBE=$hash{$treebank}{'Edge basic & enhanced'}", 11), "\t");
        print(pad("EBe=$hash{$treebank}{'Edge enhanced type'}", 11), "\t");
        print(pad("EBi=$hash{$treebank}{'Edge incompatible type'}", 11), "\t");
        print(pad("EE=$hash{$treebank}{'Edge enhanced only'}", 10), "\t");
        print(pad("G=$g", 7), "\t");
        print(pad("P=$p", 7), "\t");
        print(pad("S=$s", 7), "\t");
        print(pad("X=$x", 7), "\t");
        print(pad("R=$r", 7), "\t");
        print("C=$c\n");
    }
}
print("\n");
print("Total $n_treebanks_everything treebanks have all types of enhancements.\n");
print("Total $n_treebanks_something treebanks have at least one type of enhancement.\n");
print("Total $n_languages_something languages have at least one type of enhancement in at least one treebank.\n");



#------------------------------------------------------------------------------
# Adds spaces before or after a string to achieve a specified length.
#------------------------------------------------------------------------------
sub pad
{
    my $string = shift;
    my $target = shift; # target length
    my $before = shift;
    my $l = length($string);
    if($target > $l)
    {
        my $spaces = ' ' x ($target-$l);
        if($before)
        {
            $string = $spaces.$string;
        }
        else
        {
            $string = $string.$spaces;
        }
    }
    return $string;
}
