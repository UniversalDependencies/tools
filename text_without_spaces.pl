#!/usr/bin/env perl
# Outputs raw text without spaces. Used to verify that one file is a tokenization of another.
# Copyright © 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;

my $input = 'plaintext'; # conllutext | conlluform(s)
GetOptions
(
    'input=s' => \$input
);
if($input =~ m/^conllu?form/i)
{
    process_conllu_forms();
}
elsif($input =~ m/^conllu?text/i)
{
    process_conllu_sentence_text();
}
else
{
    process_plain_text();
}



#------------------------------------------------------------------------------
# Takes new text, removes spaces and adds the result to the buffer. If the
# buffer exceeds a pre-set size, prints the prefix of the buffer and shifts the
# rest. Returns the new buffer.
#------------------------------------------------------------------------------
sub buffer
{
    my $buffer = shift;
    my $newtext = shift;
    # Remove spaces.
    $newtext =~ s/\s//g;
    $buffer .= $newtext;
    # Print lines until the buffer fits in the pre-set size.
    while(length($buffer)>80)
    {
        my $line = substr($buffer, 0, 80);
        $buffer = substr($buffer, 80);
        print("$line\n");
    }
    # We must not forget to flush the rest of the buffer at the end!
    return $buffer;
}



#------------------------------------------------------------------------------
# Processes plain text input.
#------------------------------------------------------------------------------
sub process_plain_text
{
    my $buffer;
    while(<>)
    {
        $buffer = buffer($buffer, $_);
    }
    print("$buffer\n");
}



#------------------------------------------------------------------------------
# Processes text attributes from a CoNLL-U file.
#------------------------------------------------------------------------------
sub process_conllu_sentence_text
{
    my $buffer;
    while(<>)
    {
        if(m/^\#\s*text\s*=\s*(.+)$/)
        {
            $buffer = buffer($buffer, $1);
        }
    }
    print("$buffer\n");
}



#------------------------------------------------------------------------------
# Processes token forms from a CoNLL-U file.
#------------------------------------------------------------------------------
sub process_conllu_forms
{
    my $buffer;
    my $mwtlast;
    while(<>)
    {
        if(m/^\d+-(\d+)\t(.+?)\t/)
        {
            $mwtlast = $1;
            $buffer = buffer($buffer, $2);
        }
        elsif(m/^(\d+)\t(.+?)\t/ && !(defined($mwtlast) && $1<=$mwtlast))
        {
            $mwtlast = undef;
            $buffer = buffer($buffer, $2);
        }
        elsif(m/^\D/)
        {
            $mwtlast = undef;
        }
    }
    print("$buffer\n");
}
