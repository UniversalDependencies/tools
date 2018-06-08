#!/usr/bin/perl
# Reads CoNLL-U data from STDIN, checks whether every sentence has a sent_id comment/attribute and whether it is unique.
# Note that all CoNLL-U files from one repository (treebank) (i.e. train, dev and test) have to be supplied so that treebank-wide uniqueness is checked:
# cat *.conllu | check_sentence_ids.pl
# Copyright © 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;

sub usage
{
    print STDERR ("cat *.conllu | perl check_sentence_ids.pl\n");
}

use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my %hash;
my $current_id = '';
my $lineno = 0;
my $in_sentence = 0;
my $first_sentence_line = 0;
while(<>)
{
    $lineno++;
    s/\r?\n$//;
    if($in_sentence == 0)
    {
        if(m/^$/)
        {
            print STDERR ("Unwarranted empty line at line no. $lineno.\n");
        }
        else
        {
            $in_sentence = 1;
            $first_sentence_line = $lineno ;
        }
    }
    if($in_sentence == 1 and m/^$/)
    {
        if($current_id eq '')
        {
            print STDERR ("Missing sent_id at sentence beginning at line no. $first_sentence_line.\n");
        }
        $in_sentence = 0;
        $current_id = '';
        $first_sentence_line = -1;
    }
    if(m/^\#\s*sent_id\s*=\s*(.+)/)
    {
        if(not($current_id eq ''))
        {
            print STDERR ("Multiple 'sent_id' values at sentence beginning at line no. $first_sentence_line.\n");
        }
        $current_id = $1;
        if(exists($hash{$current_id}))
        {
            print STDERR ("Duplicate sent_id '$current_id' at line no. $lineno (first occurrence at line no. $hash{$current_id}).\n");
        }
        else
        {
            $hash{$current_id} = $lineno;
        }
    }
}
