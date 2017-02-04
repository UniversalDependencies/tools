#!/usr/bin/env perl
# Extracts raw text from CoNLL-U file. Uses newdoc and newpar tags when available.
# Copyright © 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;

# Language code 'zh' or 'ja' will trigger Chinese-like text formatting.
my $language = 'en';
GetOptions
(
    'language=s' => \$language
);
my $chinese = $language =~ m/^(zh|ja)(_|$)/;

my @sentence = ();
my $text = '';
my $newpar = 0;
my $newdoc = 0;
my $buffer = '';
my $start = 1;
while(<>)
{
    push(@sentence, $_);
    if(m/^\#\s*text\s*=\s*(.+)/)
    {
        $text = $1;
    }
    elsif(m/^\#\s*newpar(\s|$)/)
    {
        $newpar = 1;
    }
    elsif(m/^\#\s*newdoc(\s|$)/)
    {
        $newdoc = 1;
    }
    elsif(m/^\s*$/)
    {
        # Empty line between documents and paragraphs.
        if(!$start && ($newdoc || $newpar))
        {
            if($buffer ne '')
            {
                print("$buffer\n");
                $buffer = '';
            }
            print("\n");
        }
        # Add space between sentences.
        if($buffer ne '' && !$chinese)
        {
            $buffer .= ' ';
        }
        $buffer .= $text;
        # Line breaks at word boundaries after at most 80 characters.
        if($chinese)
        {
            $buffer = print_chinese_lines_from_buffer($buffer, 80);
        }
        else
        {
            $buffer = print_lines_from_buffer($buffer, 80);
        }
        # Start is only true until we write the first sentence of the input stream.
        $start = 0;
        $newdoc = 0;
        $newpar = 0;
        $text = '';
    }
}
# There may be unflushed buffer contents after the last sentence, less than 80 characters
# (otherwise we would have already dealt with it), so just flush it.
if($buffer ne '')
{
    print("$buffer\n");
}



#------------------------------------------------------------------------------
# Prints as many complete lines of text as there are in the buffer. Returns the
# remaining contents of the buffer.
#------------------------------------------------------------------------------
sub print_lines_from_buffer
{
    my $buffer = shift;
    # Maximum number of characters allowed on one line, not counting the line
    # break character(s), which also replace any number of trailing spaces.
    # Exception: If there is a word longer than the limit, it will be printed
    # on one line.
    # Note that this algorithm is not suitable for Chinese and Japanese.
    my $limit = shift;
    if(length($buffer) >= $limit)
    {
        my @cbuffer = split(//, $buffer);
        # There may be more than one new line waiting in the buffer.
        while(scalar(@cbuffer) >= $limit)
        {
            ###!!! We could make it simpler if we ignored multi-space sequences
            ###!!! between words. It sounds OK to ignore them because at the
            ###!!! line break we do not respect original spacing anyway.
            my $i;
            my $ilastspace;
            for($i = 0; $i<=$#cbuffer; $i++)
            {
                if($i>$limit && defined($ilastspace))
                {
                    last;
                }
                if($cbuffer[$i] =~ m/\s/)
                {
                    $ilastspace = $i;
                }
            }
            if(defined($ilastspace) && $ilastspace>0)
            {
                my @out = @cbuffer[0..($ilastspace-1)];
                splice(@cbuffer, 0, $ilastspace+1);
                print(join('', @out), "\n");
            }
            else
            {
                print(join('', @cbuffer), "\n");
                splice(@cbuffer);
            }
        }
        $buffer = join('', @cbuffer);
    }
    return $buffer;
}



#------------------------------------------------------------------------------
# Prints as many complete lines of text as there are in the buffer. Returns the
# remaining contents of the buffer. Assumes that there are no spaces between
# words and lines can be broken between any two characters, as is the custom in
# Chinese and Japanese.
#------------------------------------------------------------------------------
sub print_chinese_lines_from_buffer
{
    my $buffer = shift;
    # Maximum number of characters allowed on one line, not counting the line
    # break character(s).
    my $limit = shift;
    # We cannot simply print the first $limit characters from the buffer,
    # followed by a line break. There could be embedded Latin words or
    # numbers and we do not want to insert a line break in the middle of
    # a foreign word.
    my @cbuffer = split(//, $buffer);
    while(scalar(@cbuffer) >= $limit)
    {
        my $nprint = 0;
        for(my $i = 0; $i <= $#cbuffer; $i++)
        {
            if($i > $limit && $nprint > 0)
            {
                last;
            }
            unless($i < $#cbuffer && $cbuffer[$i] =~ m/[\p{Latin}0-9]/ && $cbuffer[$i+1] =~ m/[\p{Latin}0-9]/)
            {
                $nprint = $i+1;
            }
        }
        my @out = @cbuffer[0..($nprint-1)];
        splice(@cbuffer, 0, $nprint);
        print(join('', @out), "\n");
    }
    $buffer = join('', @cbuffer);
    return $buffer;
}
