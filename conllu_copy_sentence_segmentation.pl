#!/usr/bin/env perl
# Assuming that two CoNLL-U files cover the same text with same tokenization
# and word segmentation, this script makes sure that the TARGET file has also
# the same sentence segmentation as the SOURCE file. Everything else in the
# target file is left as intact as possible.
# Copyright © 2018, 2022 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

# Usage: Project sentence segmentation predicted by UDPipe to a file where
# we have other annotations that we do not want to lose (note: we can first
# project tokenization using the script conllu_copy_tokenization.pl):
# conllu_copy_sentence_segmentation.pl udpipe-output.conllu tgtfile.conllu

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

if(scalar(@ARGV) != 2)
{
    die("Usage: $0 src.conllu tgt.conllu > tgt-resegmented.conllu");
}
my $srcpath = $ARGV[0];
my $tgtpath = $ARGV[1];
open(SRC, $srcpath) or die("Cannot read $srcpath: $!");
open(TGT, $tgtpath) or die("Cannot read $tgtpath: $!");
my $sli = 0; # src line number
my $tli = 0; # tgt line number
my $srcline = get_next_token_line(*SRC, \$sli); # the next source token
die("Source token expected but not found at line $sli") if(!defined($srcline));
my @comments;
my @tokens;
while(my $tgtline = <TGT>)
{
    $tli++;
    # Collect tgt comments. They will be printed when the next src sentence starts.
    if($tgtline =~ m/^\#/)
    {
        push(@comments, $tgtline);
    }
    # For a token/word line, collect it and check that src has the same token/word.
    elsif($tgtline =~ m/^\d/)
    {
        my @tf = split(/\t/, $tgtline);
        my $tform = $tf[1];
        # We have already read the matching source token line.
        my @sf = split(/\t/, $srcline);
        my $sform = $sf[1];
        if($sform ne $tform)
        {
            die("Source form '$sform' at line $sli does not match target form '$tform' at line $tli");
        }
        push(@tokens, $tgtline);
        # Check whether the source sentence ends here. Read the next source token.
        $srcline = get_next_token_line(*SRC, \$sli);
        # Undefined $srcline means end of src sentence.
        if(!defined($srcline))
        {
            # Print the sentence accummulated so far.
            print(join('', @comments));
            print(join('', @tokens));
            print("\n");
            # Reset the variables to collect the next sentence.
            @comments = ();
            @tokens = ();
            # Get the real next token. This time it should not be undefined.
            $srcline = get_next_token_line(*SRC, \$sli);
            die("Source token expected but not found at line $sli") if(!defined($srcline));
        }
    }
}
# If there is more data in source, the source sentence may not end  when the
# target ends, meaning that the final part of the target will not be printed.
if(scalar(@comments) > 0 || scalar(@tokens) > 0)
{
    print STDERR (join('', @comments));
    print STDERR (join('', @tokens));
    die("Some target lines did not make it to the output (tgt line $tli, src line $sli); perhaps the target input ended prematurely");
}
close(SRC);
close(TGT);



#------------------------------------------------------------------------------
# Reads next token from a CoNLL-U file. Adds it to a buffer. Returns the number
# of non-whitespace characters read. (Returns 0 if there are no more tokens in
# the file. The same would happen if there were an empty string instead of the
# word form, i.e., not even the underscore character, but such file would not
# be valid CoNLL-U.)
#
# This function is currently used to read the source tokens but not the target
# tokens, those are read directly in the main loop.
#------------------------------------------------------------------------------
sub get_next_token_line
{
    my $fh = shift; # the handle of the open file
    my $li = shift; # reference to the current line number
    # Read the next token or sentence break.
    while(my $line = <$fh>)
    {
        ${$li}++;
        # Return undef if sentence ends.
        if($line =~ m/^\s*$/)
        {
            return undef;
        }
        # Skip sentence-level comments.
        # Return the next line of a regular node, multi-word token interval or empty node.
        elsif($line =~ m/^\d/)
        {
            return $line;
        }
    }
    die("File ended without terminating the last sentence (src line $sli, tgt line $tli)");
}
