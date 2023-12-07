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
use Carp;

if(scalar(@ARGV) != 2)
{
    confess("Usage: $0 src.conllu tgt.conllu > tgt-resegmented.conllu");
}
my $srcpath = $ARGV[0];
my $tgtpath = $ARGV[1];
open(SRC, $srcpath) or confess("Cannot read $srcpath: $!");
open(TGT, $tgtpath) or confess("Cannot read $tgtpath: $!");
my $sli = 0; # src line number
my $tli = 0; # tgt line number
my $srcline = get_next_token_line(*SRC, \$sli); # the next source token
confess("Source token expected but not found at line $sli") if(!defined($srcline));
my @comments;
my @tokens;
my $last_sentid;
my %used_sentids;
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
            confess("Source form '$sform' at line $sli does not match target form '$tform' at line $tli");
        }
        push(@tokens, $tgtline);
        # Check whether the source sentence ends here. Read the next source token.
        $srcline = get_next_token_line(*SRC, \$sli);
        # Undefined $srcline means end of src sentence.
        if(!defined($srcline))
        {
            # The token ids may need renumbering.
            ###!!! We currently do not assume there is any syntactic annotation, so we do not care about HEAD and DEPS.
            my $id = 1;
            my $text = '';
            my $mwtto = 0;
            foreach my $token (@tokens)
            {
                $token =~ s/\r?\n$//;
                my @f = split(/\t/, $token);
                if($f[0] =~ m/^(\d+)-(\d+)$/)
                {
                    my $diff = $2-$1;
                    $mwtto = $id+$diff;
                    $f[0] = $id.'-'.$mwtto;
                    $text .= $f[1];
                    unless($f[9] ne '_' && grep {m/^SpaceAfter=No$/} (split(/\|/, $f[9])))
                    {
                        $text .= ' ';
                    }
                }
                elsif($f[0] =~ m/^(\d+)$/)
                {
                    $f[0] = $id;
                    unless($id <= $mwtto)
                    {
                        $text .= $f[1];
                        unless($f[9] ne '_' && grep {m/^SpaceAfter=No$/} (split(/\|/, $f[9])))
                        {
                            $text .= ' ';
                        }
                    }
                    $id++;
                }
                $token = join("\t", @f)."\n";
            }
            $text =~ s/\s+$//;
            # Make sure that the comments contain just one sent_id and text, and that they are correct.
            my $sentid_found = 0;
            my $text_found = 0;
            for(my $i = 0; $i <= $#comments; $i++)
            {
                if($comments[$i] =~ m/^\#\s*sent_id\s*=\s*(\S+)/)
                {
                    $last_sentid = $1;
                    if($sentid_found)
                    {
                        splice(@comments, $i--, 1);
                    }
                    else
                    {
                        $sentid_found = 1;
                        if(exists($used_sentids{$last_sentid}))
                        {
                            die("Unexpected duplicite sentence id '$last_sentid' in $tgtpath");
                        }
                        else
                        {
                            $used_sentids{$last_sentid}++;
                        }
                    }
                }
                elsif($comments[$i] =~ m/^\#\s*text\s*=/)
                {
                    if($text_found)
                    {
                        splice(@comments, $i--, 1);
                    }
                    else
                    {
                        $comments[$i] = "\# text = $text\n";
                        $text_found = 1;
                    }
                }
            }
            if(!$sentid_found)
            {
                my $sentid = $last_sentid;
                # The $last_sentid may not have been used if it was in a merged sentence with another id.
                # If it has been used, add a letter to distinguish it.
                my $code = 65; # 'A'
                while(exists($used_sentids{$sentid}))
                {
                    $code++;
                    $sentid = $last_sentid.chr($code);
                }
                $used_sentids{$sentid}++;
                push(@comments, "\# sent_id = $sentid\n");
            }
            if(!$text_found)
            {
                push(@comments, "\# text = $text\n");
            }
            # Print the sentence accummulated so far.
            print(join('', @comments));
            print(join('', @tokens));
            print("\n");
            # Reset the variables to collect the next sentence.
            @comments = ();
            @tokens = ();
            # Get the real next token. This time it should not be undefined
            # unless we are at the end of both files.
            $srcline = get_next_token_line(*SRC, \$sli);
        }
    }
}
# If there is more data in source, the source sentence may not end  when the
# target ends, meaning that the final part of the target will not be printed.
if(scalar(@comments) > 0 || scalar(@tokens) > 0)
{
    print STDERR (join('', @comments));
    print STDERR (join('', @tokens));
    confess("Some target lines did not make it to the output (tgt line $tli, src line $sli); perhaps the target input ended prematurely");
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
    # If we are here, we are at the end of the file. This can happen because
    # after we return an end of sentence, we are immediatelly called again for
    # the first token of the next sentence. After the last sentence of the
    # file, we obviously have nothing more to offer.
    return undef;
}
