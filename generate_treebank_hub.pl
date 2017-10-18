#!/usr/bin/env perl
# Generates a treebank-description page for UD documentation.
# Copyright © 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use udlib;

my $folder = 'UD_Czech';
my $treebank_name = $folder;
$treebank_name =~ s/[-_]/ /g;
my $language_name = $folder;
$language_name =~ s/^UD_//;
$language_name =~ s/-.*//;
$language_name =~ s/_/ /g;
my $metadata = udlib::read_readme($folder);

print <<EOF
---
layout: base
title:  '$folder'
permalink: cs/overview/cs_pdt-hub.html
udver: '2'
---

<!-- This page is automatically generated from the README file and from the data files in the latest release.
     Please do not edit this page directly. -->

\# $treebank_name

EOF
;
print("<em>TODO: Provide backward link to the [$language_name](cs-hub.html) language hub page, once we have agreed on a common naming scheme.</em>\n\n");
print("This treebank has been part of Universal Dependencies since the $metadata->{'Data available since'} release.\n\n");
print("The following people have contributed to making this treebank part of UD: ", join(', ', map {my $x = $_; if($x =~ m/^(.+),\s*(.+)$/) {$x = "$2 $1"} $x} (split(/\s*;\s*/, $metadata->{Contributors}))), ".\n\n");
print("Repository: [$folder](https://github.com/UniversalDependencies/$folder)\n\n");
print("License: $metadata->{License}");
print(". The underlying text is not included; the user must obtain it separately and then merge with the UD annotation using a script distributed with UD") if($metadata->{'Includes text'} eq 'no');
print("\n\n");
print("Genre: ", join(', ', split(/\s+/, $metadata->{Genre})), "\n\n");

my $scrambled_email = $metadata->{Contact};
$scrambled_email =~ s/\@/&nbsp;(æt)&nbsp;/g;
$scrambled_email =~ s/\./&nbsp;•&nbsp;/g;
print("Questions, comments?\n");
print("General annotation questions (either $language_name-specific or cross-linguistic) can be raised in the [main UD issue tracker](https://github.com/UniversalDependencies/docs/issues).\n");
print("You can report bugs in this treebank in the [treebank-specific issue tracker on Github](https://github.com/UniversalDependencies/$folder/issues).\n");
print("If you want to collaborate, please contact [$scrambled_email].\n");
if($metadata->{Contributing} eq 'here')
{
    print("Development of the treebank happens directly in the UD repository, so you may submit bug fixes as pull requests against the dev branch.\n");
}
elsif($metadata->{Contributing} eq 'elsewhere')
{
    print("Development of the treebank happens outside the UD repository.\n");
    print("If there are bugs, either the original data source or the conversion procedure must be fixed.\n");
    print("Do not submit pull requests against the UD repository.\n");
}
elsif($metadata->{Contributing} eq 'to be adopted')
{
    print("The UD version of this treebank currently does not have a maintainer.\n");
    print("If you know the language and want to help, please consider adopting the treebank.\n");
}
print("\n");

print("| Annotation | Source |\n");
print("|------------|--------|\n");
foreach my $annotation (qw(Lemmas UPOS XPOS Features Relations))
{
    print("| $annotation | ");
    if($metadata->{$annotation} eq 'manual native')
    {
        print("annotated manually");
        unless($annotation eq 'XPOS')
        {
            print(", natively in UD style");
        }
        print(" |\n");
    }
    elsif($metadata->{$annotation} eq 'converted from manual')
    {
        print("annotated manually in non-UD style, automatically converted to UD |\n");
    }
    elsif($metadata->{$annotation} eq 'automatic')
    {
        print("assigned by a program, not checked manually |\n");
    }
    elsif($metadata->{$annotation} eq 'not available')
    {
        print("not available |\n");
    }
    else
    {
        print("(undocumented) |\n");
    }
}
print("\n");

print("$metadata->{description}\n\n");

print("\#\# Facts about the Data\n\n");
# We should integrate this script with the stats-collecting script better... or keep the two outputs separate.
# For now, let's just call the other script.
system("perl tools/conllu-stats.pl --oformat hubcompare $folder");
