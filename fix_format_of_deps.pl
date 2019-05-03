#!/usr/bin/env perl
# Fixes errors in enhanced graphs in Bulgarian.
# Copyright © 2019 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

while(<>)
{
    my $line = $_;
    if($line =~ m/^\d+(\.\d+)?\t/)
    {
        my @f = split(/\t/, $line);
        my $deps = $f[8];
        unless($deps eq '_')
        {
            my @deps = map {m/^(\d+):(.+)$/; [$1, $2]} (split(/\|/, $deps));
            # If parent is 0, relation must be 'root'.
            @deps = map {my $h = $_->[0]; my $d = $_->[1]; $d = 'root' if($h==0); [$h, $d]} (@deps);
            # Relations must be sorted by parent id, then by relation type.
            @deps = sort {my $r = $a->[0] <=> $b->[0]; unless($r) {$r = $a->[1] cmp $b->[1];} $r} (@deps);
            my $new_deps = join('|', map {"$_->[0]:$_->[1]"} (@deps));
            if($new_deps ne $deps)
            {
                $f[8] = $new_deps;
                $line = join("\t", @f);
            }
        }
    }
    print($line);
}
