#!/usr/bin/env perl
# Generates a treebank-description page for UD documentation.
# Copyright © 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
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

my $folder = shift(@ARGV);
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

EOF
;
print(udlib::generate_markdown_treebank_overview($folder));
