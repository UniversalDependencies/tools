#!/usr/bin/env perl
# Converts Unicode to the NFC normalized form (i.e., canonical decomposition followed by canonical composition).
# Can be applied to any UTF-8 encoded text file, including CoNLL-U.
# Usage: perl normalize_unicode.pl < input.txt > normalized_output.txt
# Copyright © 2019 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Unicode::Normalize;

while(<>)
{
    print(NFC($_));
}
