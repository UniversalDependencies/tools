#!/usr/bin/perl
# Reads CoNLL(-U) data from STDIN, collects all features (FEAT column, delimited by vertical bars) and prints them sorted to STDOUT.
# Copyright © 2013-2015 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;

# Read options.
$konfig{detailed} = 0; # default: generate stats.xml; detailed statistics are for Github documentation
GetOptions
(
    'detailed' => \$konfig{detailed}
);
# Argument "2009" toggles the CoNLL 2009 data format.
my $format = shift;
my $i_feat_column = $format eq '2009' ? 6 : 5;

my $ntok = 0;
my $nfus = 0;
my $nword = 0;
my $nsent = 0;
my @sentence;
while(<>)
{
    # Skip comment lines (new in CoNLL-U).
    next if(m/^\#/);
    # Empty lines separate sentences. There must be an empty line after every sentence including the last one.
    if(m/^\s*$/)
    {
        if(@sentence)
        {
            process_sentence(@sentence);
        }
        $nsent++;
        splice(@sentence);
    }
    # Lines with fused tokens do not contain features but we want to count the fusions.
    elsif(m/^(\d+)-(\d+)\t(\S+)/)
    {
        my $i0 = $1;
        my $i1 = $2;
        my $fusion = $3;
        my $size = $i1-$i0+1;
        $ntok -= $size-1;
        $nfus++;
        # Remember the occurrence of the fusion.
        $fusions{$fusion}++ unless($fusion eq '_');
    }
    else
    {
        $ntok++;
        $nword++;
        # Get rid of the line break.
        s/\r?\n$//;
        # Split line into columns.
        my @columns = split(/\s+/, $_);
        push(@sentence, \@columns);
    }
}
prune_examples(\%fusions);
@fusions = sort {$fusions{$b} <=> $fusions{$a}} (keys(%fusions));
prune_examples(\%words);
@words = sort {$words{$b} <=> $words{$a}} (keys(%words));
prune_examples(\%lemmas);
@lemmas = sort {$lemmas{$b} <=> $lemmas{$a}} (keys(%lemmas));
# Sort the features alphabetically before printing them.
@tagset = sort(keys(%tagset));
@featureset = sort {lc($a) cmp lc($b)} (keys(%featureset));
@deprelset = sort(keys(%deprelset));
# Examples may contain uppercase letters only if all-lowercase version does not exist.
my @ltagset = map {$_.'-lemma'} (@tagset);
foreach my $key (keys(%examples))
{
    my @examples = keys(%{$examples{$key}});
    foreach my $example (@examples)
    {
        if(lc($example) ne $example && exists($examples{$key}{lc($example)}))
        {
            $examples{$key}{lc($example)} += $examples{$key}{$example};
            delete($examples{$key}{$example});
        }
    }
}
foreach my $tag (@tagset)
{
    my @lemmas = keys(%{$tlw{$tag}});
    foreach my $lemma (@lemmas)
    {
        prune_examples($tlw{$tag}{$lemma});
    }
}
if($konfig{detailed})
{
    detailed_statistics();
}
else
{
    # Print the list of universal tags as an XML structure that can be used in the treebank description XML file.
    print("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    print("<treebank>\n");
    print <<EOF
  <!-- tokens means "surface tokens", e.g. Spanish "vámonos" counts as one token
       words means "syntactic words", e.g. Spanish "vámonos" is split to two words, "vamos" and "nos"
       fused is the number of tokens that are split to two or more syntactic words
       The words and fused elements can be omitted if no token is split to smaller syntactic words. -->
EOF
    ;
    print("  <size>\n");
    print("    <total><sentences>$nsent</sentences><tokens>$ntok</tokens><words>$nword</words><fused>$nfus</fused></total>\n");
    ###!!! We do not know what part of the data is for training, development or testing. We would have to change the calling syntax.
    #print("    <train></train>\n");
    #print("    <dev></dev>\n");
    #print("    <test></test>\n");
    print("  </size>\n");
    print('  <lemmas unique="', scalar(@lemmas), '" />');
    splice(@lemmas, 15);
    print("<!-- ", join(', ', @lemmas), " -->\n");
    print('  <forms unique="', scalar(@words), '" />');
    splice(@words, 15);
    print("<!-- ", join(', ', @words), " -->\n");
    print('  <fusions unique="', scalar(@fusions), '" />');
    splice(@fusions, 15);
    print("<!-- ", join(', ', @fusions), " -->\n");
    print("  <!-- Statistics of universal POS tags. The comments with the most frequent lemmas are optional (but easy to obtain). -->\n");
    print("  <tags unique=\"".scalar(@tagset)."\">\n");
    foreach my $tag (@tagset)
    {
        my @examples = sort
        {
            my $result = $examples{$tag}{$b} <=> $examples{$tag}{$a};
            unless($result)
            {
                $result = $a cmp $b;
            }
            $result
        }
        (keys(%{$examples{$tag}}));
        splice(@examples, 10);
        print('    <tag name="'.$tag.'">'.$tagset{$tag}.'</tag><!-- ', join(', ', @examples), " -->\n");
    }
    print("  </tags>\n");
    # Print the list of features as an XML structure that can be used in the treebank description XML file.
    print("  <!-- Statistics of features and values. The comments with the most frequent word forms are optional (but easy to obtain). -->\n");
    print("  <feats unique=\"".scalar(@featureset)."\">\n");
    foreach my $feature (@featureset)
    {
        my @examples = sort
        {
            my $result = $examples{$feature}{$b} <=> $examples{$feature}{$a};
            unless($result)
            {
                $result = $a cmp $b;
            }
            $result
        }
        (keys(%{$examples{$feature}}));
        splice(@examples, 10);
        my $upostags = join(',', sort(keys(%{$upos{$feature}})));
        my ($name, $value) = split(/=/, $feature);
        print('    <feat name="'.$name.'" value="'.$value.'" upos="'.$upostags.'">'.$featureset{$feature}.'</feat><!-- ', join(', ', @examples), " -->\n");
    }
    print("  </feats>\n");
    # Print the list of dependency relations as an XML structure that can be used in the treebank description XML file.
    print("  <!-- Statistics of universal dependency relations. -->\n");
    print("  <deps unique=\"".scalar(@deprelset)."\">\n");
    foreach my $deprel (@deprelset)
    {
        print('    <dep name="'.$deprel.'">'.$deprelset{$deprel}."</dep>\n");
    }
    print("  </deps>\n");
    print("</treebank>\n");
}



#------------------------------------------------------------------------------
# Collects statistics from one sentence after the sentence has been read
# completely. We need to read the sentence first so we can save the entire
# sentence as an example of a word's usage.
#------------------------------------------------------------------------------
sub process_sentence
{
    my @sentence = @_;
    my $sentence = join(' ', map {$_->[1]} (@sentence));
    my $slength = length($sentence);
    foreach my $columns (@sentence)
    {
        my $word = $columns->[1];
        my $lemma = $columns->[2];
        my $tag = $columns->[3];
        my $features = $columns->[$i_feat_column];
        my $head = $columns->[6];
        my $deprel = $columns->[7];
        # Remember the occurrence of the word form (syntactic word).
        $words{$word}++ unless($word eq '_');
        # Remember the occurrence of the lemma.
        $lemmas{$lemma}++ unless($lemma eq '_');
        # Remember the occurrence of the universal POS tag.
        $tagset{$tag}++;
        $tlw{$tag}{$lemma}{$word}++;
        # We can also print example forms and lemmas that had the tag.
        $examples{$tag}{$word}++;
        $examples{$tag.'-lemma'}{$lemma}++;
        # How many times is a particular form or lemma classified as a particular part of speech?
        $wordtag{$word}{$tag}++;
        $lemmatag{$lemma}{$tag}++;
        if(!exists($exentwt{$word}{$tag}) || length($exentwt{$word}{$tag}) > 80 && $slength < length($exentwt{$word}{$tag}))
        {
            $exentwt{$word}{$tag} = join(' ', map {($_->[1] eq $word && $_->[3] eq $tag) ? "<b>$_->[1]</b>" : $_->[1]} (@sentence));
        }
        $exentlt{$lemma}{$tag} = $sentence unless(exists($exentlt{$lemma}{$tag}));
        # Remember the occurrence of each feature-value pair.
        my $tagfeatures = "$tag\t$features";
        $tfset{$tag}{$features}++;
        $tfsetjoint{$tagfeatures}++;
        $examples{$tagfeatures}{$word}++;
        # Skip if there are no features.
        unless($features eq '_')
        {
            my @features = split(/\|/, $features);
            foreach my $fv (@features)
            {
                $featureset{$fv}++;
                # We can also list tags with which the feature occurred.
                $upos{$fv}{$tag}++;
                $tfv{$tag}{$fv}++;
                # We can also print example words that had the feature.
                $examples{$feature}{$word}++;
                # Aggregate feature names over all values.
                my ($f, $v) = split(/=/, $fv);
                $tf{$tag}{$f}++;
            }
        }
        # Remember the occurrence of each dependency relation.
        $deprelset{$deprel}++;
        $tagdeprel{$tag}{$deprel}++;
        my $parent_tag = ($head==0) ? 'ROOT' : $sentence[$head-1][3];
        $parenttag{$tag}{$parent_tag}++;
    }
}



#------------------------------------------------------------------------------
# Takes the reference to a hash of examples. Prunes the hash so that if a
# lowercased example exists, its capitalized counterpart will be deleted.
#------------------------------------------------------------------------------
sub prune_examples
{
    my $examplehash = shift;
    my @examples = keys(%{$examplehash});
    foreach my $example (@examples)
    {
        if(lc($example) ne $example && exists($examplehash->{lc($example)}))
        {
            $examplehash->{lc($example)} += $examplehash->{$example};
            delete($examplehash->{$example});
        }
    }
}



#------------------------------------------------------------------------------
# Extended statistics could be used to substitute documentation if it does not
# exist. This could be said about NOUN in the language, based on the current
# data:
#
# - how many nouns are there (types, tokens). What is the rank of this part of
#   speech? What percentage of all tokens (or types) is nouns?
# - N most frequent lemmas that are tagged NOUN
# -- if the treebank does not have lemmas, N most frequent words
# - N most frequent ambiguities, i.e. words that are sometimes tagged NOUN and
#   sometimes something else. Same for lemmas if they exist.
# - Morphological richness of nouns, form-lemma ratio. How different is it from
#   the other parts of speech and from the average? What is the highest number
#   of forms per one lemma? And what is the number of different feature-value
#   combinations observed with nouns?
# - What features may be non-empty with nouns. How often is each feature non-
#   empty with nouns? Are there features that are always filled with nouns?
# - For every feature, what are the values of the feature used with nouns? How
#   frequent are the values? Show example words.
# - Try to find example lemmas that appear with all values of a feature (or as
#   many values as possible). Show the paradigm. If there are no lemmas, try to
#   substitute them with automatically estimated stems.
# -- Specifically for nouns: If there is the feature of gender / animacy, can
#    we do this for each gender separately?
# - What are the most frequent dependency relations of a noun to its parent?
#   What is the typical part of speech of the parent?
#   Is the parent usually to the left or to the right? Close or distant? Most
#   frequent examples?
# - What is the average number of children of a noun? What are their prevailing
#   relations and parts of speech? Most frequent examples?
#------------------------------------------------------------------------------
sub detailed_statistics
{
    # We have to see all tags before we can compute percentage of each tag.
    my %ntypes; # hash{$tag}
    my %nlemmas; # hash{$tag}
    my $ntokens_total = 0;
    my $ntypes_total = 0;
    my $nlemmas_total = 0;
    foreach my $tag (@tagset)
    {
        $ntokens_total += $tagset{$tag};
        $ntypes{$tag} = scalar(keys(%{$examples{$tag}}));
        $ntypes_total += $ntypes{$tag};
        $nlemmas{$tag} = scalar(keys(%{$examples{$tag.'-lemma'}}));
        $nlemmas_total += $nlemmas{$tag};
    }
    my $flratio = $ntypes_total/$nlemmas_total;
    # Rank tags by number of lemmas, types and tokens.
    my %rtokens;
    my @tags = sort {$tagset{$b} <=> $tagset{$a}} (@tagset);
    for(my $i = 0; $i <= $#tags; $i++)
    {
        $rtokens{$tags[$i]} = $i + 1;
    }
    my %rtypes;
    @tags = sort {$ntypes{$b} <=> $ntypes{$a}} (@tagset);
    for(my $i = 0; $i <= $#tags; $i++)
    {
        $rtypes{$tags[$i]} = $i + 1;
    }
    my %rlemmas;
    @tags = sort {$nlemmas{$b} <=> $nlemmas{$a}} (@tagset);
    for(my $i = 0; $i <= $#tags; $i++)
    {
        $rlemmas{$tags[$i]} = $i + 1;
    }
    my $ntags = scalar(@tagset);
    my $limit = 10;
    foreach my $tag (@tagset)
    {
        print("--------------------------------------------------------------------------------\n");
        my $ntokens = $tagset{$tag};
        my $ptokens = sprintf("%d", ($ntokens/$ntokens_total)*100+0.5);
        my $ptypes = sprintf("%d", ($ntypes{$tag}/$ntypes_total)*100+0.5);
        my $plemmas = sprintf("%d", ($nlemmas{$tag}/$nlemmas_total)*100+0.5);
        print("There are $nlemmas{$tag} $tag lemmas ($plemmas\%), $ntypes{$tag} $tag types ($ptypes\%) and $ntokens $tag tokens ($ptokens\%).\n");
        print("Out of $ntags observed tags, the rank of $tag is: $rlemmas{$tag} in number of lemmas, $rtypes{$tag} in number of types and $rtokens{$tag} in number of tokens.\n");
        my @examples = sort
        {
            my $result = $examples{$tag.'-lemma'}{$b} <=> $examples{$tag.'-lemma'}{$a};
            unless($result)
            {
                $result = $a cmp $b;
            }
            $result
        }
        (keys(%{$examples{$tag.'-lemma'}}));
        splice(@examples, $limit);
        print("The $limit most frequent $tag lemmas: ", join(', ', @examples), "\n");
        @examples = sort
        {
            my $result = $examples{$tag}{$b} <=> $examples{$tag}{$a};
            unless($result)
            {
                $result = $a cmp $b;
            }
            $result
        }
        (keys(%{$examples{$tag}}));
        splice(@examples, $limit);
        print("The $limit most frequent $tag types:  ", join(', ', @examples), "\n");
        # Examples of ambiguous lemmas that can be this part of speech or at least one other part of speech.
        @examples = sort
        {
            my $result = $examples{$tag.'-lemma'}{$b} <=> $examples{$tag.'-lemma'}{$a};
            unless($result)
            {
                $result = $a cmp $b;
            }
            $result
        }
        (grep {scalar(keys(%{$lemmatag{$_}})) > 1} (keys(%{$examples{$tag.'-lemma'}})));
        splice(@examples, $limit);
        @examples = map {my $l = $_; my @t = map {"$_ $lemmatag{$l}{$_}"} (sort {$lemmatag{$l}{$b} <=> $lemmatag{$l}{$a}} (keys(%{$lemmatag{$l}}))); $l.' ('.join(', ', @t).')'} (@examples);
        print("The $limit most frequent ambiguous lemmas: ", join(', ', @examples), "\n");
        # Examples of ambiguous types that can be this part of speech or at least one other part of speech.
        @examples = sort
        {
            my $result = $examples{$tag}{$b} <=> $examples{$tag}{$a};
            unless($result)
            {
                $result = $a cmp $b;
            }
            $result
        }
        (grep {scalar(keys(%{$wordtag{$_}})) > 1} (keys(%{$examples{$tag}})));
        splice(@examples, $limit);
        my @examples1 = map {my $w = $_; my @t = map {"$_ $wordtag{$w}{$_}"} (sort {$wordtag{$w}{$b} <=> $wordtag{$w}{$a}} (keys(%{$wordtag{$w}}))); $w.' ('.join(', ', @t).')'} (@examples);
        print("The $limit most frequent ambiguous types:  ", join(', ', @examples1), "\n");
        print("\n");
        foreach my $example (@examples)
        {
            print("* $example\n");
            my @ambtags = sort {$wordtag{$example}{$b} <=> $wordtag{$example}{$a}} (keys(%{$wordtag{$example}}));
            foreach my $ambtag (@ambtags)
            {
                print("  * $example $ambtag $wordtag{$example}{$ambtag}: $exentwt{$example}{$ambtag}\n");
            }
        }
        print("\n");
        # Morphological richness.
        printf("The form / lemma ratio of $tag is %f (the average of all parts of speech is %f).\n", $ntypes{$tag}/$nlemmas{$tag}, $flratio);
        my @mrich_lemmas = sort {my $v = scalar(keys(%{$tlw{$tag}{$b}})) <=> scalar(keys(%{$tlw{$tag}{$a}})); $v = $a cmp $b unless($v); $v} (keys(%{$tlw{$tag}}));
        for(my $i = 0; $i < 3; $i++)
        {
            my @richest_paradigm = sort(keys(%{$tlw{$tag}{$mrich_lemmas[$i]}}));
            my $richness = scalar(@richest_paradigm);
            my $rank = ($i+1).($i==0 ? 'st' : $i==1 ? 'nd' : $i==2 ? 'rd' : 'th');
            print("The $rank highest number of forms ($richness) was observed with lemma “$mrich_lemmas[$i]”: ", join(', ', @richest_paradigm), "\n");
        }
        my @features = sort(keys(%{$tf{$tag}}));
        my $nfeatures = scalar(@features);
        my @featurepairs = sort(keys(%{$tfv{$tag}}));
        my $nfeaturepairs = scalar(@featurepairs);
        my @featuresets = sort {$tfset{$tag}{$b} <=> $tfset{$tag}{$a}} (keys(%{$tfset{$tag}}));
        my $nfeaturesets = scalar(@featuresets);
        my @features_with_counts = map {my $p = sprintf("%d", ($tf{$tag}{$_}/$tagset{$tag})*100+0.5); "$_ ($tf{$tag}{$_}; $p\% tokens)"} (@features);
        @examples = sort
        {
            my $result = $examples{$tag."\t".$featuresets[0]}{$b} <=> $examples{$tag."\t".$featuresets[0]}{$a};
            unless($result)
            {
                $result = $a cmp $b;
            }
            $result
        }
        (keys(%{$examples{$tag."\t".$featuresets[0]}}));
        splice(@examples, $limit);
        print("$tag occurs with $nfeatures features: ", join(', ', @features_with_counts), "\n");
        print("$tag occurs with $nfeaturepairs feature-value pairs: ", join(', ', @featurepairs), "\n");
        print("$tag occurs with $nfeaturesets feature combinations. The most frequent feature combination is $featuresets[0] ($tfset{$tag}{$featuresets[0]} tokens, examples: ".join(', ', @examples).").\n");
        print("\n");
        # Dependency relations.
        my @deprels = sort {$tagdeprel{$tag}{$b} <=> $tagdeprel{$tag}{$a}} (keys(%{$tagdeprel{$tag}}));
        my $ndeprels = scalar(@deprels);
        my $deprels_with_counts = join(', ', map {my $p = sprintf("%d", ($tagdeprel{$tag}{$_}/$tagset{$tag})*100+0.5); "$_ ($tagdeprel{$tag}{$_}; $p\% tokens)"} (@deprels));
        print("$tag nodes are attached to their parents using $ndeprels different relations: $deprels_with_counts\n");
        my @parenttags = sort {$parenttag{$tag}{$b} <=> $parenttag{$tag}{$a}} (keys(%{$parenttag{$tag}}));
        my $nparenttags = scalar(@parenttags);
        my $parenttags_with_counts = join(', ', map {my $p = sprintf("%d", ($parenttag{$tag}{$_}/$tagset{$tag})*100+0.5); "$_ ($parenttag{$tag}{$_}; $p\% tokens)"} (@parenttags));
        print("Parents of $tag nodes belong to $nparenttags different parts of speech: $parenttags_with_counts\n");
        print("\n");
    }
}
