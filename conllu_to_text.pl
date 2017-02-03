#!/usr/bin/env perl
# Extracts raw text from CoNLL-U file. Uses newdoc and newpar tags when available.
# Copyright © 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

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
        ###!!! We must not do this in languages like Chinese and Japanese!
        if($buffer ne '')
        {
            $buffer .= ' ';
        }
        $buffer .= $text;
        # Line breaks at word boundaries after at most 80 characters.
        # Only if there is a word longer than 80 characters, it will make a long line.
        ###!!! In Chinese and Japanese, we must break between characters! (But probably not between a normal character and punctuation.)
        if(length($buffer)>=80)
        {
            my @cbuffer = split(//, $buffer);
            while(scalar(@cbuffer)>=80)
            {
                my $i;
                my $ilastspace;
                for($i = 0; $i<=$#cbuffer; $i++)
                {
                    if($i>80 && defined($ilastspace))
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
                }
            }
            $buffer = join('', @cbuffer);
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
