#!/usr/bin/env perl
# Scans all UD treebanks for prevailing script used in the text.
# Copyright © 2026 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Unicode::UCD 'charscript', 'prop_value_aliases';
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
    print STDERR ("Usage: perl survey_scripts.pl --datapath /net/projects/ud --tbklist udsubset.txt --countby language|treebank > scripts.md\n");
    print STDERR ("       perl survey_scripts.pl --datapath /net/projects/ud --tbklist udsubset.txt --countby language|treebank --oformat json > scripts.json\n");
    print STDERR ("       --datapath ... path to the folder where all UD_* treebank repositories reside\n");
    print STDERR ("       --tbklist .... file with list of UD_* folders to consider (e.g. treebanks we are about to release)\n");
    print STDERR ("                      if tbklist is not present, all treebanks in datapath will be scanned\n");
    print STDERR ("       --countby .... count occurrences separately for each language (default) or for each treebank?\n");
    print STDERR ("       --oformat .... markdown (default) or json\n");
    print STDERR ("       --help ....... print usage and exit\n");
    print STDERR ("The overview will be printed to STDOUT.\n");
}

my $datapath = '.';
my $tbklist;
my $countby = 'language'; # or treebank
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
# Look for scripts in the data.
my %hash; # $hash{$script}{$treebank/$language} = $count
my %expected_scripts; # indexed by $treebank/$language
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
            if($countby eq 'treebank' && $treebank ne '')
            {
                $key = $langcode.'_'.lc($treebank);
            }
            else
            {
                # In the MarkDown output, we want full language names rather than just codes.
                $key = $language;
                $key =~ s/_/ /g;
            }
            # Remember expected script(s) for each key.
            $expected_scripts{$key} = $languages_from_yaml->{$langnames{$langcode}}{scripts};
            foreach my $es (@{$expected_scripts{$key}})
            {
                # Jpan denotes a mixture of Hani, Hira and Kana, but every character
                # belongs to only one of them.
                if($es eq 'Jpan')
                {
                    push(@{$expected_scripts{$key}}, 'Hani', 'Hira', 'Kana');
                    last;
                }
            }
            # Look for CoNLL-U files in the repository.
            opendir(DIR, "$datapath/$folder") or die("Cannot read the contents of the folder '$datapath/$folder': $!");
            my @files = readdir(DIR);
            closedir(DIR);
            my @conllufiles = grep {-f "$datapath/$folder/$_" && m/\.conllu$/} (@files);
            foreach my $file (@conllufiles)
            {
                read_conllu_file("$datapath/$folder/$file", \%hash, $key);
            }
        }
    }
}
if($oformat eq 'markdown')
{
    print_markdown(\%hash, \%expected_scripts);
}
else
{
    print_json(\%hash);
}



#------------------------------------------------------------------------------
# Reads one CoNLL-U file and notes all features in the global hash. Returns the
# number of feature-value pair occurrences observed in this file.
#------------------------------------------------------------------------------
sub read_conllu_file
{
    my $path = shift;
    my $hash = shift; # $hash->{$script}{$treebank/$language} = $count
    my $key = shift;
    my $nhits = 0;
    open(FILE, $path) or die("Cannot read '$path': $!");
    while(<FILE>)
    {
        # We can look at the sentence-level text attribute or at the FORM
        # column. The former is easier. In FORM, we would have to decide
        # whether we want to include nodes that are not surface tokens.
        if(m/\#\s*text\s*=(.*)/)
        {
            my $text = $1;
            # Keep only letters. Throw away digits, punctuation, spaces etc.
            $text =~ s/\P{L}//g;
            my @characters = split(//, $text);
            foreach my $c (@characters)
            {
                my $script = charscript(ord($c));
                $hash->{$script}{$key}++;
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
    my $expected_scripts = shift;
    # The hash is organized first by scripts, then by languages/treebanks.
    # If we want to present it from the opposite side, we must reorganize it.
    my %bydataset;
    foreach my $script (keys(%{$hash}))
    {
        foreach my $dataset (keys(%{$hash->{$script}}))
        {
            $bydataset{$dataset}{$script} = $hash->{$script}{$dataset};
        }
    }
    my @datasets = sort(keys(%bydataset));
    print <<EOF
---
layout: base
title:  'Scripts'
udver: '2'
---

# Scripts in the Data

This is an automatically generated list of scripts that occur in the UD data.
Only letters were surveyed. Other characters (digits, punctuation, spaces) were
ignored. The scripts are identified by their
[ISO 15924 codes](https://en.wikipedia.org/wiki/ISO_15924).

EOF
    ;
    foreach my $d (@datasets)
    {
        print("\#\# $d\n\n");
        my @scripts = sort {$bydataset{$d}{$b} <=> $bydataset{$d}{$a}} (keys(%{$bydataset{$d}}));
        # Check that the most frequent script is expected in this language.
        if(scalar(@scripts) > 0)
        {
            my $mainscript_iso = script_to_iso($scripts[0]);
            if(!grep {$_ eq $mainscript_iso} (@{$expected_scripts->{$d}}))
            {
                print("<span style=\"color:red\">Expected scripts: <tt>", join(', ', @{$expected_scripts->{$d}}), "</tt></span>\n\n");
            }
        }
        foreach my $s (@scripts)
        {
            my $siso = script_to_iso($s);
            print("* \`$siso\` ($bydataset{$d}{$s})\n");
        }
        print("\n");
    }
}
sub script_to_iso
{
    my $s = shift;
    my @aliases = grep {length($_) == 4} (prop_value_aliases('Script', $s));
    return scalar(@aliases) > 0 ? $aliases[0] : $s;
}



#------------------------------------------------------------------------------
# Prints the per-language statistics of upos-feature-value in JSON.
#------------------------------------------------------------------------------
sub print_json
{
    my $hash = shift;
    # The hash is organized first by scripts, then by languages/treebanks.
    # If we want to present it from the opposite side, we must reorganize it.
    my %bydataset;
    foreach my $script (keys(%{$hash}))
    {
        foreach my $dataset (keys(%{$hash->{$script}}))
        {
            $bydataset{$dataset}{$script} = $hash->{$script}{$dataset};
        }
    }
    print("{\n");
    my @datasets = sort(keys(%bydataset));
    my @djsons = ();
    foreach my $d (@datasets)
    {
        my $djson = '  "'.escape_json_string($d).'": {'."\n";
        my @scripts = sort {$bydataset{$d}{$b} <=> $bydataset{$d}{$a}} (keys(%{$bydataset{$d}}));
        my @sjsons = ();
        foreach my $script (@scripts)
        {
            my $sjson = '    "'.escape_json_string($script).'": '."\n";
            $sjson .= sprintf("%d", $bydataset{$d}{$script});
            push(@sjsons, $sjson);
        }
        $djson .= join(",\n", @sjsons)."\n";
        $djson .= '  }';
        push(@djsons, $djson);
    }
    print(join(",\n", @djsons)."\n");
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
