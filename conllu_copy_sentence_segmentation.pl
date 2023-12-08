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
use Getopt::Long;

sub usage
{
    print STDERR ("Usage: $0 src.conllu tgt.conllu > tgt-resegmented.conllu\n");
    print STDERR ("Options:\n");
    print STDERR ("    --par2sentids ... target sentence ids are paragraph ids + -s1, -s2 etc.\n");
}

# We assume that the source of the segmentation is the output of UDPipe or
# another segmenter, while the target file is the original with other annotation.
# The paragraph or sentence ids in the original (target) file may bear important
# information, while UDPipe outputs just numeric sentence ids. Therefore the
# sentence boundaries will be taken from the source file but sentence ids will
# be based on those in the target file. There are three options:
# 1. Take the actual paragraph id from the target file, append -s1, -s2 etc.
#    The target file must have # newpar before the first sentence and every
#    # newpar must have an id.
# 2. Take the most recent sentence id from the target file. If it has not yet
#    been used in the output, use it. Otherwise append B, C, D, etc.
# 3. Use the source sentence ids, ignore target paragraph and sentence ids.
# At present, option 3 is not supported and the following parameter switches
# between options 1 and 2.
my $use_target_paragraph_ids = 0;
GetOptions
(
    'par2sentids' => \$use_target_paragraph_ids
);
if(scalar(@ARGV) != 2)
{
    my $n = scalar(@ARGV);
    usage();
    confess("Expected 2 arguments, found $n");
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
my $last_parid;
my $isent_in_par = 0;
my $last_sentid;
my %used_sentids;
while(my $tgtline = <TGT>)
{
    $tli++;
    # Collect tgt comments. They will be printed when the next src sentence starts.
    if($tgtline =~ m/^\#/)
    {
        push(@comments, $tgtline);
        if($tgtline =~ m/^\#\s*newpar\s*(?:id\s*=\s*(\S+))?/)
        {
            $last_parid = $1;
            if($use_target_paragraph_ids && !defined($last_parid))
            {
                confess("Paragraph without id in $tgtpath (tgt line $tli, src line $sli)");
            }
            $isent_in_par = 0;
        }
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
            # Decide what will be the sentence id of the new sentence.
            my @sentids = get_sentids_from_comments(@comments);
            my $sentid = $use_target_paragraph_ids ? generate_sentid_from_parid($last_parid, \$isent_in_par, \%used_sentids) : generate_unused_sentid($last_sentid, \@sentids, \%used_sentids);
            if(scalar(@sentids) > 0)
            {
                $last_sentid = $sentids[-1];
            }
            @comments = update_sentid_in_comments($sentid, @comments);
            $used_sentids{$sentid}++;
            @comments = update_text_in_comments($text, @comments);
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



#------------------------------------------------------------------------------
# Scans a set of comments for sentence ids. Returns their list.
#------------------------------------------------------------------------------
sub get_sentids_from_comments
{
    my $comments = @_;
    my @sentids = ();
    foreach my $comment (@comments)
    {
        if($comment =~ m/^\#\s*sent_id\s*=\s*(\S+)/)
        {
            push(@sentids, $1);
        }
    }
    return @sentids;
}



#------------------------------------------------------------------------------
# Generates an unused sentence id based on the last paragraph id observed in
# the target file.
#------------------------------------------------------------------------------
sub generate_sentid_from_parid
{
    my $last_parid = shift;
    my $isent_in_par = shift; # scalar reference
    my $used_sentids = shift; # hash reference
    if(!$last_parid)
    {
        confess("Unknown target paragraph id (tgt line $tli, src line $sli)");
    }
    # Add 's' + a new sentence number to the paragraph id.
    my $sentid;
    my $isent = ${$isent_in_par};
    do
    {
        $isent++;
        $sentid = "$last_parid-s$isent";
    }
    while(exists($used_sentids->{$sentid}));
    ${$isent_in_par} = $isent;
    return $sentid;
}



#------------------------------------------------------------------------------
# Generates an unused sentence id based on the last sentence id observed in the
# target file.
#------------------------------------------------------------------------------
sub generate_unused_sentid
{
    my $last_sentid = shift;
    my $sentids = shift; # array reference: sentids found in comments
    my $used_sentids = shift; # hash reference
    # First try the sentids from the current set of comments.
    my $sentid;
    foreach $sentid (@{$sentids})
    {
        if(!exists($used_sentids->{$sentid}))
        {
            return $sentid;
        }
        # Update local $last_sentid.
        # We would use the $last_sentid provided by the caller only if the current set of comments did not contain any new sentids.
        $last_sentid = $sentid;
    }
    # Either there are no new sentids or they were already used.
    # Let's try a modification.
    $sentid = $last_sentid;
    # The $last_sentid may not have been used if it was in a merged sentence with another id.
    # If it has been used, add a letter to distinguish it.
    my $code = 65; # 'A'
    while(exists($used_sentids->{$sentid}))
    {
        $code++;
        if($code > 90) # 'Z'
        {
            ###!!! We could do something more sophisticated, e.g., double letters ('AA').
            ###!!! But we do not want to use non-letter characters such as '['. # ]
            print STDERR ("Current sentid(s): ", join(', ', @{$sentids}), "\n");
            confess("Unable to find a unique sentence id (tgt line $tli, src line $sli, last id '$last_sentid')");
        }
        $sentid = $last_sentid.chr($code);
    }
    return $sentid;
}



#------------------------------------------------------------------------------
# Takes a set of comments and modifies it. If there are sentids, the first one
# will be replaced with the new sentid and all others will be removed. If there
# are none, the new sentid will be added to the end.
#------------------------------------------------------------------------------
sub update_sentid_in_comments
{
    my $sentid = shift;
    my @comments = @_;
    my $sentid_found = 0;
    for(my $i = 0; $i <= $#comments; $i++)
    {
        if($comments[$i] =~ m/^\#\s*sent_id\s*=\s*(\S+)/)
        {
            if($sentid_found)
            {
                splice(@comments, $i--, 1);
            }
            else
            {
                $comments[$i] = "\# sent_id = $sentid\n";
                $sentid_found = 1;
            }
        }
    }
    if(!$sentid_found)
    {
        push(@comments, "\# sent_id = $sentid\n");
    }
    return @comments;
}



#------------------------------------------------------------------------------
# Takes a set of comments and modifies it. If there are texts, the first one
# will be replaced with the new text and all others will be removed. If there
# are none, the new text will be added to the end.
#------------------------------------------------------------------------------
sub update_text_in_comments
{
    my $text = shift;
    my @comments = @_;
    my $text_found = 0;
    for(my $i = 0; $i <= $#comments; $i++)
    {
        if($comments[$i] =~ m/^\#\s*text\s*=/)
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
    if(!$text_found)
    {
        push(@comments, "\# text = $text\n");
    }
    return @comments;
}
