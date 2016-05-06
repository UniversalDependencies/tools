#!/usr/bin/env perl
# Reads CoNLL-X from STDIN, converts CPOS+POS+FEAT to the universal POS and features, writes the result to STDOUT.
# The output contains the universal POS tag in the CPOS column and the universal features in the FEAT column.
# The POS column is copied over from the input.
# Copyright © 2015 Dan Zeman <zeman@ufal.mff.cuni.cz>
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
    print STDERR ("Usage: conll_convert_tags_to_uposf.pl -f source_tagset < input.conll > output.conll\n");
}

# Get options.
GetOptions('from=s' => \$tagset1);
if($tagset1 eq '')
{
    usage();
    die();
}

my $c = new Lingua::Interset::Converter ('from' => $tagset1, 'to' => 'mul::uposf');

# Read the CoNLL-X file from STDIN or from files given as arguments.
while(<>)
{
    # Skip comment lines before sentences.
    # Skip empty lines after sentences.
    # Skip initial lines of multi-word tokens.
    unless(m/^#/ || m/^\s*$/ || m/^\d+-\d/)
    {
        chomp();
        my @f = split(/\t/, $_);
        my $tag = "$f[3]\t$f[4]\t$f[5]";
        my $utag = $c->convert($tag);
        my ($upos, $ufeat) = split(/\t/, $utag);
        $f[3] = $upos;
        $f[5] = $ufeat;
        $_ = join("\t", @f)."\n";
    }
    # Write the modified line to the standard output.
    print();
}
