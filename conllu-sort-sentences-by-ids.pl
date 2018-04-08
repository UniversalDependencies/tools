#!/usr/bin/env perl
# Re-orders sentences in a CoNLL-U file by their ids. Reads the entire file
# into memory, hence it may choke on large files.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

while(<>)
{
    push(@sentence, $_);
    if(m/^\#\s*sent_id\s*=\s*(\S+)\s*$/)
    {
        $current_sent_id = $1;
    }
    if(m/^\s*$/)
    {
        if(exists($hash{$current_sent_id}))
        {
            die("Duplicate sentence id '$current_sent_id'");
        }
        $hash{$current_sent_id} = join('', @sentence);
        splice(@sentence);
        $current_sent_id = '';
    }
}
###!!! I am creating this script because of a treebank that uses numeric ids,
###!!! so I give higher priority to numeric sorting. However, this should be
###!!! configurable as for other treebanks lexicographic sorting may be
###!!! preferable.
my @ids = sort
{
    my $result = $a <=> $b;
    unless($result)
    {
        $result = $a cmp $b;
    }
    $result
}
(keys(%hash));
foreach my $id (@ids)
{
    print($hash{$id});
}
