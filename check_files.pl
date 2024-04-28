#!/usr/bin/env perl
# Checks files to be distributed as Universal Dependencies.
# Copyright © 2015, 2016, 2017, 2018, 2022, 2023 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

sub usage
{
    print STDERR ("Usage: tools/check_files.pl UD_Ancient_Greek-PROIEL\n");
    print STDERR ("       Will just check files and metadata of one treebank, report errors and exit.\n");
}

# We need to tell Perl where to find my udlib module (same folder as this script).
# While we are at it, we will also remember the path to the superordinate folder,
# which should be the UD root (all UD treebanks should be its subfolders).
BEGIN
{
    use Cwd;
    my $path = $0;
    $path =~ s:\\:/:g;
    my $currentpath = getcwd();
    $libpath = $currentpath;
    if($path =~ m:/:)
    {
        $path =~ s:/[^/]*$:/:;
        chdir($path);
        $libpath = getcwd();
    }
    chdir('..');
    $udpath = getcwd();
    chdir($currentpath);
    #print STDERR ("libpath=$libpath\n");
}
use lib $libpath;
use udlib;

# We expect one argument and interpret it as the name of the treebank whose
# files and metadata should be checked. We should check the arguments after
# options have been read.
if(scalar(@ARGV) != 1)
{
    usage();
    die;
}

# We need a mapping from the English names of the languages (as they appear in folder names) to their ISO codes and families.
my $languages_from_yaml = udlib::get_language_hash();

my $folder = $ARGV[0];
$folder =~ s:/$::;
my $n_errors = 0;
my @errors;
# The name of the folder: 'UD_' + language name + optional treebank identifier.
# Example: UD_Ancient_Greek-PROIEL
my ($language, $treebank) = udlib::decompose_repo_name($folder);
if(defined($language))
{
    if(exists($languages_from_yaml->{$language}))
    {
        my $langcode = $languages_from_yaml->{$language}{lcode};
        my $key = udlib::get_ltcode_from_repo_name($folder, $languages_from_yaml);
        # Check that the expected files are present and that there are no extra files.
        udlib::check_files($udpath, $folder, $key, \@errors, \$n_errors);
        # Check that all required metadata items are present in the README file.
        my $metadata = udlib::read_readme($folder, $udpath);
        if(!defined($metadata))
        {
            push(@errors, "[L0 Repo files] $folder: cannot read the README file: $!\n");
            $n_errors++;
        }
        udlib::check_metadata($udpath, $folder, $metadata, \@errors, \$n_errors);
        # Check that the language-specific documentation has at least the index (summary) page.
        udlib::check_documentation($udpath, $folder, $langcode, \@errors, \$n_errors);
    }
    else
    {
        push(@errors, "[L0 Repo files] $folder: Unknown language '$language'.\n");
        $n_errors++;
    }
}
else
{
    push(@errors, "[L0 Repo files] $folder: Cannot parse folder name '$folder'.\n");
    $n_errors++;
}
if($n_errors>0)
{
    print(join('', @errors));
    print("*** FAILED ***\n");
}
else
{
    # Output similar to the validator.
    print("*** PASSED ***\n");
}
# Exit 0 is considered success by the operating system.
exit($n_errors);
