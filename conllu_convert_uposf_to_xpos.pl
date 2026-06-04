#!/usr/bin/env perl
# Reads CoNLL-U from STDIN, computes XPOS in a given tagset from UPOS+FEATS
# (overwrites preexisting XPOS if any), writes the result to STDOUT.
# Copyright © 2026 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
use Lingua::Interset::Converter;

sub usage
{
    print STDERR ("Usage: conllu_convert_uposf_to_xpos.pl -t target_tagset < input.conllu > output.conllu\n");
}

# Get options.
my $tagset = 'cs::pdtc';
my $help = 0;
GetOptions('to=s' => \$tagset, 'help' => \$help);
if($help)
{
    usage();
    exit(0);
}

my $c = new Lingua::Interset::Converter ('from' => 'mul::uposf', 'to' => $tagset);

# Read the CoNLL-U file from STDIN or from files given as arguments.
while(<>)
{
    # Skip comment lines before sentences.
    # Skip empty lines after sentences.
    # Skip initial lines of multi-word tokens.
    if(m/^[0-9]+\t/)
    {
        chomp;
        my @f = split(/\t/, $_);
        my $uposf = "$f[3]\t$f[5]";
        my $xpos = $c->convert($uposf);
        $xpos =~ s/^\s+//;
        $xpos =~ s/\s+$//;
        $xpos =~ s/\s+/ /g;
        $xpos = '_' if($xpos =~ m/^\s*$/);
        $f[4] = $xpos;
        $_ = join("\t", @f)."\n";
    }
    # Write the modified line to the standard output.
    print();
}
