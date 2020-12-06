#!/usr/bin/env perl
# Scans all UD treebanks for morphological features and values.
# Copyright © 2016-2018, 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
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
    $libpath = $currentpath;
    $path =~ s:\\:/:g;
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
    print STDERR ("Usage: perl survey_features.pl --datapath /net/projects/ud --tbklist udsubset.txt --countby treebank|language > features.md\n");
    print STDERR ("       perl survey_features.pl --datapath /net/projects/ud --tbklist udsubset.txt --countby treebank|language --oformat json > features.json\n");
    print STDERR ("       --datapath ... path to the folder where all UD_* treebank repositories reside\n");
    print STDERR ("       --tbklist .... file with list of UD_* folders to consider (e.g. treebanks we are about to release)\n");
    print STDERR ("                      if tbklist is not present, all treebanks in datapath will be scanned\n");
    print STDERR ("       --countby .... count occurrences separately for each treebank or for each language?\n");
    print STDERR ("       --oformat .... md or json; in JSON, the output will be organized for each UPOS tag separately\n");
    print STDERR ("       --help ....... print usage and exit\n");
    print STDERR ("The overview will be printed to STDOUT in MarkDown format.\n");
}

my $datapath = '.';
my $tbklist;
my $countby = 'treebank'; # or language
my $oformat = 'markdown'; # or json
my $help = 0;
GetOptions
(
    'datapath=s' => \$datapath, # UD_* folders will be sought in this folder
    'tbklist=s'  => \$tbklist,  # path to file with treebank list; if defined, only treebanks on the list will be surveyed
    'countby=s'  => \$countby,  # count items by treebank or by language?
    'oformat=s'  => \$oformat,  # format output as MarkDown or JSON?
    'help'       => \$help
);
if($help)
{
    usage();
    exit 0;
}
if($countby =~ m/^t/i)
{
    $countby = 'treebank';
}
else
{
    $countby = 'language';
}
if($oformat =~ m/^m/i)
{
    $oformat = 'markdown';
}
else
{
    $oformat = 'json';
}
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
my %hash; # $hash{$feature}{$value}{$treebank/$language} = $count
my %poshash; # $poshash{$treebank/$language}{$upos}{$feature}{$value} = $count
my %hittreebanks;
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
            if($countby eq 'treebank' && $treebank ne '')
            {
                $key .= '_'.lc($treebank);
            }
            my $nhits = 0;
            # Look for the other files in the repository.
            opendir(DIR, "$datapath/$folder") or die("Cannot read the contents of the folder '$datapath/$folder': $!");
            my @files = readdir(DIR);
            closedir(DIR);
            my @conllufiles = grep {-f "$datapath/$folder/$_" && m/\.conllu$/} (@files);
            foreach my $file (@conllufiles)
            {
                $nhits += read_conllu_file("$datapath/$folder/$file", \%hash, \%poshash, $key);
            }
            # Remember treebanks where we found something.
            if($nhits>0)
            {
                $hittreebanks{$key}++;
            }
        }
    }
}
if($oformat eq 'markdown')
{
    print_markdown(\%hash);
}
else
{
    print_json(\%poshash);
}



#------------------------------------------------------------------------------
# Reads one CoNLL-U file and notes all features in the global hash. Returns the
# number of feature-value pair occurrences observed in this file.
#------------------------------------------------------------------------------
sub read_conllu_file
{
    my $path = shift;
    my $hash = shift;
    my $poshash = shift;
    my $key = shift;
    my $nhits = 0;
    open(FILE, $path) or die("Cannot read '$path': $!");
    while(<FILE>)
    {
        if(m/^\d+\t/)
        {
            chomp();
            my @fields = split(/\t/, $_);
            my $upos = $fields[3];
            my $features = $fields[5];
            unless($features eq '_')
            {
                my @features = split(/\|/, $features);
                foreach my $feature (@features)
                {
                    my ($f, $vv) = split(/=/, $feature);
                    # There may be several values delimited by commas.
                    my @values = split(/,/, $vv);
                    foreach my $v (@values)
                    {
                        $hash->{$f}{$v}{$key}++;
                        $poshash->{$key}{$upos}{$f}{$v}++;
                        $nhits++;
                    }
                }
            }
        }
    }
    close(FILE);
    return $nhits;
}



#------------------------------------------------------------------------------
# Prints an overview of features and their values as a MarkDown page.
#------------------------------------------------------------------------------
sub print_markdown
{
    my $hash = shift;
    my @features = sort(keys(%{$hash}));
    print <<EOF
---
layout: base
title:  'Features and Values'
udver: '2'
---

This is an automatically generated list of features and values (both universal and language-specific) that occur in the UD data.
EOF
    ;
    foreach my $f (@features)
    {
        my %ffolders;
        my @values = sort(keys(%{$hash->{$f}}));
        print("\#\# $f\n\n");
        print("[$f]()\n\n");
        foreach my $v (@values)
        {
            my @folders = sort(keys(%{$hash->{$f}{$v}}));
            foreach my $folder (@folders)
            {
                print("* $f=$v\t$folder\t$hash->{$f}{$v}{$folder}\n");
                $ffolders{$folder}++;
            }
        }
        print("\n");
    }
}



#------------------------------------------------------------------------------
# Prints the per-language statistics of upos-feature-value in JSON.
#------------------------------------------------------------------------------
sub print_json
{
    my $poshash = shift;
    print("{\n");
    my @languages = sort(keys(%{$poshash}));
    my @ljsons = ();
    foreach my $language (@languages)
    {
        my $ljson = '  "'.escape_json_string($language).'": {'."\n";
        my @upos = sort(keys(%{$poshash->{$language}}));
        my @ujsons = ();
        foreach my $upos (@upos)
        {
            my $ujson = '    "'.escape_json_string($upos).'": {'."\n";
            my @features = sort(keys(%{$poshash->{$language}{$upos}}));
            my @fjsons = ();
            foreach my $feature (@features)
            {
                my $fjson = '      "'.escape_json_string($feature).'": {';
                my @values = sort(keys(%{$poshash->{$language}{$upos}{$feature}}));
                my @vjsons = ();
                foreach my $value (@values)
                {
                    my $vjson = '"'.escape_json_string($value).'": ';
                    $vjson .= sprintf("%d", $poshash->{$language}{$upos}{$feature}{$value});
                    push(@vjsons, $vjson);
                }
                $fjson .= join(', ', @vjsons);
                $fjson .= '}';
                push(@fjsons, $fjson);
            }
            $ujson .= join(",\n", @fjsons)."\n";
            $ujson .= '    }';
            push(@ujsons, $ujson);
        }
        $ljson .= join(",\n", @ujsons)."\n";
        $ljson .= '  }';
        push(@ljsons, $ljson);
    }
    print(join(",\n", @ljsons)."\n");
    print("}\n");
}



#------------------------------------------------------------------------------
# Takes a string and escapes characters that would prevent it from being used
# in JSON. (For control characters, it throws a fatal exception instead of
# escaping them because they should not occur in anything we export in this
# block.)
#------------------------------------------------------------------------------
sub escape_json_string
{
    my $string = shift;
    # https://www.ietf.org/rfc/rfc4627.txt
    # The only characters that must be escaped in JSON are the following:
    # \ " and control codes (anything less than U+0020)
    # Escapes can be written as \uXXXX where XXXX is UTF-16 code.
    # There are a few shortcuts, too: \\ \"
    $string =~ s/\\/\\\\/g; # escape \
    $string =~ s/"/\\"/g; # escape " # "
    if($string =~ m/[\x{00}-\x{1F}]/)
    {
        log_fatal("The string must not contain control characters.");
    }
    return $string;
}
