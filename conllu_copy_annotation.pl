#!/usr/bin/env perl
# Assuming that two CoNLL-U files cover the same text with same tokenization
# and sentence segmentation, this script makes sure that the TARGET file has
# also the same annotation (in selected columns) as the SOURCE file.
# Everything else in the target file is left intact. Possible use case: We
# ran a tagger / lemmatizer / parser on the file but we only want to take one
# type of annotation from the predicted output, and we also do not want the
# additional comment lines the tool may have generated.
# Copyright © 2024 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Carp;
use Getopt::Long;

sub usage
{
    print STDERR ("Usage: $0 --columns=lemma,upos,xpos,feats src.conllu tgt.conllu > tgt-merged.conllu\n");
    print STDERR ("       By default all columns that can be copied will be copied.\n");
}

my $columns = 'lemma,upos,xpos,feats';
GetOptions
(
    'columns=s' => \$columns
);
my @columns = split(',', lc($columns));
# Initialize the hash with columns that can be copied, so we can verify the command-line options.
my %copy =
(
    'lemma' => 1,
    'upos'  => 1,
    'xpos'  => 1,
    'feats' => 1
);
foreach my $column (@columns)
{
    if(!exists($copy{$column}))
    {
        confess("Cannot copy column '$column'");
    }
    $copy{$column}++;
}
# Columns that have only the initial 1 were in fact not selected and should now get 0.
foreach my $column (keys(%copy))
{
    $copy{$column}--;
}

# We assume that the source of the new annotation is the output of UDPipe or
# another tool, while the target file is the original with other annotation.
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
while(my $tgtline = <TGT>)
{
    $tli++;
    # For a token/word/node line, first make sure that is has the same id and form in src and tgt.
    if($tgtline =~ m/^\d/)
    {
        my @tf = split(/\t/, $tgtline);
        # We have already read the matching source token line.
        my @sf = split(/\t/, $srcline);
        if($sf[0] ne $tf[0])
        {
            confess("Source id '$sf[0]' at line $sli does not match target id '$tf[0]' at line $tli");
        }
        if($sf[1] ne $tf[1])
        {
            confess("Source form '$sf[1]' at line $sli does not match target form '$tf[1]' at line $tli");
        }
        # Now that we have matching src and tgt lines, copy the annotation that has to be copied from src to tgt.
        $tf[2] = $sf[2] if($copy{lemma});
        $tf[3] = $sf[3] if($copy{upos});
        $tf[4] = $sf[4] if($copy{xpos});
        $tf[5] = $sf[5] if($copy{feats});
        # Print the modified target line.
        $tgtline = join("\t", @tf);
        print($tgtline);
        # Read the next source token.
        $srcline = get_next_token_line(*SRC, \$sli);
    }
    # Print other tgt lines (comments and empty lines) immediately after reading them.
    # Source comments are ignored.
    else
    {
        print($tgtline);
    }
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
        #if($line =~ m/^\s*$/)
        #{
        #    return undef;
        #}
        # Skip sentence-level comments.
        # Return the next line of a regular node, multi-word token interval or empty node.
        if($line =~ m/^\d/)
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
