#!/usr/bin/perl
# Reads CoNLL(-U) data from STDIN, collects all features (FEAT column, delimited by vertical bars) and prints them sorted to STDOUT.
# Copyright © 2013-2016 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;

sub usage
{
    print STDERR ("cat *.conllu | perl conllu-stats.pl > stats.xml\n");
    print STDERR ("... generates the basic statistics that accompany each treebank.\n");
    print STDERR ("perl conllu-stats.pl --detailed --data .. --docs ../docs --lang pt\n");
    print STDERR ("... adds detailed statistics of each tag, feature and relation to the documentation source pages.\n");
    print STDERR ("    data = parent folder of the data repositories, e.g. of UD_English\n");
    print STDERR ("    The script will analyze all treebanks of the given language.\n");
}

use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;

# Read options.
$konfig{detailed} = 0; # default: generate stats.xml; detailed statistics are for Github documentation
$konfig{datapath} = '.'; # if detailed: parent folder of the data repositories (of UD_$language).
$konfig{docspath} = '../docs'; # if detailed: where is the docs repository? We will modify the page sources there.
$konfig{langcode} = ''; # if detailed; used to identify docs that shall be modified, and also in links inside
GetOptions
(
    'detailed'   => \$konfig{detailed},
    'data=s'     => \$konfig{datapath},
    'docs=s'     => \$konfig{docspath},
    'language=s' => \$konfig{langcode},
    'help'       => \$konfig{help}
);
exit(usage()) if($konfig{help});
if($konfig{detailed} && $konfig{langcode} eq '')
{
    usage();
    die("Missing language code for detailed analysis");
}
# Argument "2009" toggles the CoNLL 2009 data format.
my $format = shift;
my $i_feat_column = $format eq '2009' ? 6 : 5;
my %universal_features =
(
    'PronType' => ['Prs', 'Rcp', 'Art', 'Int', 'Rel', 'Dem', 'Tot', 'Neg', 'Ind'],
    'NumType'  => ['Card', 'Ord', 'Mult', 'Frac', 'Sets', 'Dist', 'Range', 'Gen'],
    'Poss'     => ['Yes'],
    'Reflex'   => ['Yes'],
    'Gender'   => ['Masc', 'Fem', 'Neut', 'Com'],
    'Animacy'  => ['Anim', 'Nhum', 'Inan'],
    'Number'   => ['Sing', 'Coll', 'Dual', 'Plur', 'Ptan'],
    'Case'     => ['Nom', 'Acc', 'Abs', 'Erg', 'Dat', 'Gen', 'Voc', 'Loc', 'Ins', 'Par', 'Dis', 'Ess', 'Tra', 'Com', 'Abe', 'Ine', 'Ill', 'Ela', 'Add', 'Ade', 'All', 'Abl', 'Sup', 'Sub', 'Del', 'Lat', 'Tem', 'Ter', 'Cau', 'Ben'],
    'Definite' => ['Ind', 'Def', 'Red', 'Com'],
    'Degree'   => ['Pos', 'Cmp', 'Sup', 'Abs'],
    'VerbForm' => ['Fin', 'Inf', 'Sup', 'Part', 'Trans', 'Ger'],
    'Mood'     => ['Ind', 'Imp', 'Cnd', 'Pot', 'Sub', 'Jus', 'Qot', 'Opt', 'Des', 'Nec'],
    'Tense'    => ['Pres', 'Fut', 'Past', 'Imp', 'Nar', 'Pqp'],
    'Aspect'   => ['Imp', 'Perf', 'Pro', 'Prog'],
    'Voice'    => ['Act', 'Pass', 'Rcp', 'Cau'],
    'Person'   => ['1', '2', '3'],
    'Negative' => ['Pos', 'Neg']
);
my %languages =
(
    'am'  => {'name' => 'Amharic',    'i' => 0, 'c' => ','},
    'grc' => {'name' => 'Ancient Greek', 'i' => 1, 'c' => ','},
    'ar'  => {'name' => 'Arabic',     'i' => 0, 'c' => '،'},
    'eu'  => {'name' => 'Basque',     'i' => 1, 'c' => ','},
    'bg'  => {'name' => 'Bulgarian',  'i' => 1, 'c' => ','},
    'ca'  => {'name' => 'Catalan',    'i' => 1, 'c' => ','},
    'hr'  => {'name' => 'Croatian',   'i' => 1, 'c' => ','},
    'cs'  => {'name' => 'Czech',      'i' => 1, 'c' => ','},
    'da'  => {'name' => 'Danish',     'i' => 1, 'c' => ','},
    'nl'  => {'name' => 'Dutch',      'i' => 1, 'c' => ','},
    'en'  => {'name' => 'English',    'i' => 1, 'c' => ','},
    'et'  => {'name' => 'Estonian',   'i' => 1, 'c' => ','},
    'fi'  => {'name' => 'Finnish',    'i' => 1, 'c' => ','},
    'fr'  => {'name' => 'French',     'i' => 1, 'c' => ','},
    'de'  => {'name' => 'German',     'i' => 1, 'c' => ','},
    'got' => {'name' => 'Gothic',     'i' => 1, 'c' => ','},
    'el'  => {'name' => 'Greek',      'i' => 1, 'c' => ','},
    'he'  => {'name' => 'Hebrew',     'i' => 0, 'c' => ','},
    'hi'  => {'name' => 'Hindi',      'i' => 0, 'c' => ','},
    'hu'  => {'name' => 'Hungarian',  'i' => 1, 'c' => ','},
    'id'  => {'name' => 'Indonesian', 'i' => 1, 'c' => ','},
    'ga'  => {'name' => 'Irish',      'i' => 1, 'c' => ','},
    'it'  => {'name' => 'Italian',    'i' => 1, 'c' => ','},
    'ja'  => {'name' => 'Japanese',   'i' => 0, 'c' => ','},
    'kk'  => {'name' => 'Kazakh',     'i' => 1, 'c' => ','},
    'ko'  => {'name' => 'Korean',     'i' => 0, 'c' => ','},
    'la'  => {'name' => 'Latin',      'i' => 1, 'c' => ','},
    'no'  => {'name' => 'Norwegian',  'i' => 1, 'c' => ','},
    'cu'  => {'name' => 'Old Church Slavonic', 'i' => 1, 'c' => ','},
    'fa'  => {'name' => 'Persian',    'i' => 0, 'c' => '،'},
    'pl'  => {'name' => 'Polish',     'i' => 1, 'c' => ','},
    'pt'  => {'name' => 'Portuguese', 'i' => 1, 'c' => ','},
    'ro'  => {'name' => 'Romanian',   'i' => 1, 'c' => ','},
    'ru'  => {'name' => 'Russian',    'i' => 1, 'c' => ','},
    'sk'  => {'name' => 'Slovak',     'i' => 1, 'c' => ','},
    'sl'  => {'name' => 'Slovenian',  'i' => 1, 'c' => ','},
    'es'  => {'name' => 'Spanish',    'i' => 1, 'c' => ','},
    'sv'  => {'name' => 'Swedish',    'i' => 1, 'c' => ','},
    'ta'  => {'name' => 'Tamil',      'i' => 0, 'c' => ','},
    'tr'  => {'name' => 'Turkish',    'i' => 1, 'c' => ','},
    'uk'  => {'name' => 'Ukrainian',  'i' => 1, 'c' => ','},
);
if(!exists($languages{$konfig{langcode}}))
{
    die("Unknown language code '$konfig{langcode}'");
}
if($konfig{detailed})
{
    my $language = $languages{$konfig{langcode}}{name};
    $language =~ s/ /_/g;
    @treebanks = glob("$konfig{datapath}/UD_$language*");
    print STDERR ("Treebanks to analyze: ", join(', ', @treebanks), "\n");
    $mode = '>';
    foreach my $treebank (@treebanks)
    {
        local $treebank_id = $treebank;
        $treebank_id =~ s-^.*/--;
        @ARGV = glob("$treebank/*.conllu");
        if(scalar(@ARGV)==0)
        {
            print STDERR ("WARNING: No CoNLL-U files found in $treebank.\n");
            next;
        }
        print STDERR ("Files to read: ", join(', ', @ARGV), "\n");
        my $target_path = "$konfig{docspath}/_includes/stats/$konfig{langcode}";
        if(!-d $target_path)
        {
            mkdir($target_path) or die("Cannot create folder $target_path: $!");
        }
        process_treebank();
        $mode = '>>';
    }
}
else
{
    # Take either STDIN or the CoNLL-U files specified on the command line.
    process_treebank();
}



#------------------------------------------------------------------------------
# Reads the standard input (simple stats) or all CoNLL-U files in one treebank
# (detailed stats) and analyzes them.
#------------------------------------------------------------------------------
sub process_treebank
{
    local $ntok = 0;
    local $nfus = 0;
    local $nword = 0;
    local $nsent = 0;
    local @sentence;
    # Counters visible to the summarizing functions.
    local %words;
    local %lemmas;
    local %tagset;
    local %tlw;
    local %examples;
    local %wordtag;
    local %lemmatag;
    local %exentwt;
    local %exentlt;
    local %tfset;
    local %tfsetjoint;
    local %fvset;
    local %upos;
    local %tfv;
    local %featureset;
    local %tf;
    local %ft;
    local %fw;
    local %fl;
    local %paradigm;
    local %fv;
    local %deprelset;
    local %ltrdeprel;
    local %deprellen;
    local %tagdeprel;
    local %parenttag;
    local %depreltags;
    local %exentdtt;
    local %exconlludtt;
    local %exentlt;
    local %maxtagdegree;
    local %nchildren;
    local %tagdegree;
    local %childtag;
    local %childtagdeprel;
    local %agreement;
    local %disagreement;
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
    local @fusions = sort {$fusions{$b} <=> $fusions{$a}} (keys(%fusions));
    prune_examples(\%words);
    local @words = sort {$words{$b} <=> $words{$a}} (keys(%words));
    prune_examples(\%lemmas);
    local @lemmas = sort {$lemmas{$b} <=> $lemmas{$a}} (keys(%lemmas));
    # Sort the features alphabetically before printing them.
    local @tagset = sort(keys(%tagset));
    local @featureset = sort {lc($a) cmp lc($b)} (keys(%featureset));
    local @fvset = sort {lc($a) cmp lc($b)} (keys(%fvset));
    local @deprelset = sort(keys(%deprelset));
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
        detailed_statistics_tags();
        detailed_statistics_features();
        detailed_statistics_relations();
    }
    else # stats.xml
    {
        simple_xml_statistics();
    }
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
    # Add to every node the links to its children.
    foreach my $node (@sentence)
    {
        my $id = $node->[0];
        my $head = $node->[6];
        if($head > 0)
        {
            # The eleventh column [10] is unused and we will use it for the child links.
            push(@{$sentence[$head-1][10]}, $id);
        }
    }
    foreach my $node (@sentence)
    {
        my $id = $node->[0];
        my $word = $node->[1];
        my $lemma = $node->[2];
        my $tag = $node->[3];
        my $features = $node->[$i_feat_column];
        my $head = $node->[6];
        my $deprel = $node->[7];
        my @children = @{$node->[10]};
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
        my %features_found_here;
        unless($features eq '_')
        {
            my @features = split(/\|/, $features);
            foreach my $fv (@features)
            {
                $fvset{$fv}++;
                # We can also list tags with which the feature occurred.
                $upos{$fv}{$tag}++;
                $tfv{$tag}{$fv}++;
                # We can also print example words that had the feature.
                $examples{$fv}{$word}++;
                $examples{"$tag\t$fv"}{$word}++;
                # Aggregate feature names over all values.
                my ($f, $v) = split(/=/, $fv);
                $featureset{$f}++;
                $tf{$tag}{$f}++;
                $ft{$f}{$tag}++;
                $fw{$f}{$word}++;
                $fl{$f}{$lemma}++;
                my @other_features = grep {!m/$f/} (@features);
                my $other_features = scalar(@other_features) > 0 ? join('|', @other_features) : '_';
                $paradigm{$tag}{$f}{$lemma}{$v}{$other_features}{$word}++;
                $fv{$f}{$v}++;
                $features_found_here{$f}++;
            }
        }
        # Remember examples of empty values of features.
        foreach my $f (keys(%universal_features))
        {
            if(!exists($features_found_here{$f}))
            {
                $examples{"$tag\t$f=EMPTY"}{$word}++;
            }
        }
        # Remember the occurrence of each dependency relation.
        $deprelset{$deprel}++;
        $ltrdeprel{$deprel}++ if($head < $id);
        $deprellen{$deprel} += abs($id - $head);
        $tagdeprel{$tag}{$deprel}++;
        my $parent_tag = ($head==0) ? 'ROOT' : $sentence[$head-1][3];
        $parenttag{$tag}{$parent_tag}++;
        $depreltags{$deprel}{"$parent_tag-$tag"}++;
        if(!exists($exentdtt{$deprel}{$parent_tag}{$tag}) || length($exentdtt{$deprel}{$parent_tag}{$tag}) > 80 && $slength < length($exentdtt{$deprel}{$parent_tag}{$tag}))
        {
            $exentdtt{$deprel}{$parent_tag}{$tag} = join(' ', map {($_->[0] == $id || $_->[0] == $head) ? "<b>$_->[1]</b>" : $_->[1]} (@sentence));
            my $visualstyle = "# visual-style $id\tbgColor:blue\n";
            $visualstyle .= "# visual-style $id\tfgColor:white\n";
            $visualstyle .= "# visual-style $head\tbgColor:blue\n";
            $visualstyle .= "# visual-style $head\tfgColor:white\n";
            $visualstyle .= "# visual-style $head $id $deprel\tcolor:blue\n";
            $exconlludtt{$deprel}{$parent_tag}{$tag} = $visualstyle.join("\n", map {my @f = @{$_}; join("\t", (@f[0..9]))} (@sentence))."\n\n";
        }
        $exentlt{$lemma}{$tag} = $sentence unless(exists($exentlt{$lemma}{$tag}));
        # Children from the perspective of their parent.
        my $nchildren = scalar(@children);
        $maxtagdegree{$tag} = $nchildren if(!defined($maxtagdegree{$tag}) || $nchildren > $maxtagdegree{$tag});
        $nchildren{$tag} += $nchildren;
        $nchildren = 3 if($nchildren > 3);
        $tagdegree{$tag}{$nchildren}++;
        foreach my $child (@children)
        {
            my $cnode = $sentence[$child-1];
            my $ctag = $cnode->[3];
            my $cdeprel = $cnode->[7];
            $childtag{$tag}{$ctag}++;
            $childtagdeprel{$tag}{$cdeprel}++;
        }
        # Feature agreement between parent and child.
        unless($head==0)
        {
            my $relation = "$parent_tag --[$deprel]--> $tag";
            my $parent_features = $sentence[$head-1][5];
            my @pfvs = $parent_features eq '_' ? () : split(/\|/, $parent_features);
            my @cfvs = $features        eq '_' ? () : split(/\|/, $features);
            my %pf;
            foreach my $pfv (@pfvs)
            {
                my ($f, $v) = split(/=/, $pfv);
                $pf{$f} = $v;
            }
            my %cf;
            foreach my $cfv (@cfvs)
            {
                my ($f, $v) = split(/=/, $cfv);
                $cf{$f} = $v;
                # Does the parent have the same value of the feature?
                if($pf{$f} eq $v)
                {
                    $agreement{$f}{$relation}++;
                }
                else
                {
                    $disagreement{$f}{$relation}++;
                }
            }
            foreach my $f (keys(%pf))
            {
                if(!exists($cf{$f}))
                {
                    $disagreement{$f}{$relation}++;
                }
            }
        }
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
# exist. This function generates statistics of all part-of-speech tags and
# saves them in the docs repository.
#------------------------------------------------------------------------------
sub detailed_statistics_tags
{
    local $docspath = $konfig{docspath};
    local $langcode = $konfig{langcode};
    # We have to see all tags before we can compute percentage of each tag.
    local %ntypes; # hash{$tag}
    local %nlemmas; # hash{$tag}
    local $ntokens_total = 0;
    local $ntypes_total = 0;
    local $nlemmas_total = 0;
    foreach my $tag (@tagset)
    {
        $ntokens_total += $tagset{$tag};
        $ntypes{$tag} = scalar(keys(%{$examples{$tag}}));
        $ntypes_total += $ntypes{$tag};
        $nlemmas{$tag} = scalar(keys(%{$examples{$tag.'-lemma'}}));
        $nlemmas_total += $nlemmas{$tag};
    }
    local $flratio = $ntypes_total/$nlemmas_total;
    # Rank tags by number of lemmas, types and tokens.
    local %rtokens;
    local @tags = sort {$tagset{$b} <=> $tagset{$a}} (@tagset);
    for(my $i = 0; $i <= $#tags; $i++)
    {
        $rtokens{$tags[$i]} = $i + 1;
    }
    local %rtypes;
    @tags = sort {$ntypes{$b} <=> $ntypes{$a}} (@tagset);
    for(my $i = 0; $i <= $#tags; $i++)
    {
        $rtypes{$tags[$i]} = $i + 1;
    }
    local %rlemmas;
    @tags = sort {$nlemmas{$b} <=> $nlemmas{$a}} (@tagset);
    for(my $i = 0; $i <= $#tags; $i++)
    {
        $rlemmas{$tags[$i]} = $i + 1;
    }
    local $ntags = scalar(@tagset);
    local $limit = 10;
    foreach my $tag (@tagset)
    {
        my $path = "$docspath/_includes/stats/$langcode/pos";
        mkdir($path) unless(-d $path);
        my $file = "$path/$tag.md";
        $file =~ s/AUX\.md/AUX_.md/;
        my $page = get_detailed_statistics_tag($tag);
        print STDERR ("Writing $file\n");
        open(PAGE, "$mode$file") or die("Cannot write $file: $!");
        print PAGE ($page);
        close(PAGE);
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
sub get_detailed_statistics_tag
{
    my $tag = shift;
    my $page;
    $page .= "\n\n--------------------------------------------------------------------------------\n\n";
    $page .= "## Treebank Statistics ($treebank_id)\n\n";
    my $ntokens = $tagset{$tag};
    my $ptokens = percent($ntokens, $ntokens_total);
    my $ptypes = percent($ntypes{$tag}, $ntypes_total);
    my $plemmas = percent($nlemmas{$tag}, $nlemmas_total);
    $page .= "There are $nlemmas{$tag} `$tag` lemmas ($plemmas), $ntypes{$tag} `$tag` types ($ptypes) and $ntokens `$tag` tokens ($ptokens).\n";
    $page .= "Out of $ntags observed tags, the rank of `$tag` is: $rlemmas{$tag} in number of lemmas, $rtypes{$tag} in number of types and $rtokens{$tag} in number of tokens.\n\n";
    my $examples = prepare_examples($examples{$tag.'-lemma'}, $limit);
    $page .= "The $limit most frequent `$tag` lemmas: ".fex($examples)."\n\n";
    $examples = prepare_examples($examples{$tag}, $limit);
    $page .= "The $limit most frequent `$tag` types:  ".fex($examples)."\n\n";
    # Examples of ambiguous lemmas that can be this part of speech or at least one other part of speech.
    my @examples = grep {scalar(keys(%{$lemmatag{$_}})) > 1} (keys(%{$examples{$tag.'-lemma'}}));
    @examples = sort_and_truncate_examples($examples{$tag.'-lemma'}, \@examples, $limit);
    @examples = map {my $l = $_; my @t = map {"[$_]() $lemmatag{$l}{$_}"} (sort {$lemmatag{$l}{$b} <=> $lemmatag{$l}{$a}} (keys(%{$lemmatag{$l}}))); fex($l).' ('.join(', ', @t).')'} (@examples);
    $page .= "The $limit most frequent ambiguous lemmas: ".join(', ', @examples)."\n\n";
    # Examples of ambiguous types that can be this part of speech or at least one other part of speech.
    @examples = grep {scalar(keys(%{$wordtag{$_}})) > 1} (keys(%{$examples{$tag}}));
    @examples = sort_and_truncate_examples($examples{$tag}, \@examples, $limit);
    my @examples1 = map {my $w = $_; my @t = map {"[$_]() $wordtag{$w}{$_}"} (sort {$wordtag{$w}{$b} <=> $wordtag{$w}{$a}} (keys(%{$wordtag{$w}}))); fex($w).' ('.join(', ', @t).')'} (@examples);
    $page .= "The $limit most frequent ambiguous types:  ".join(', ', @examples1)."\n\n\n";
    foreach my $example (@examples)
    {
        $page .= '* '.fex($example)."\n";
        my @ambtags = sort {$wordtag{$example}{$b} <=> $wordtag{$example}{$a}} (keys(%{$wordtag{$example}}));
        foreach my $ambtag (@ambtags)
        {
            $page .= "  * [$ambtag]() $wordtag{$example}{$ambtag}: ".fex($exentwt{$example}{$ambtag})."\n";
        }
    }
    $page .= "\n";
    # Morphological richness.
    $page .= "## Morphology\n\n";
    $page .= sprintf("The form / lemma ratio of `$tag` is %f (the average of all parts of speech is %f).\n\n", $ntypes{$tag}/$nlemmas{$tag}, $flratio);
    my @mrich_lemmas = sort {my $v = scalar(keys(%{$tlw{$tag}{$b}})) <=> scalar(keys(%{$tlw{$tag}{$a}})); $v = $a cmp $b unless($v); $v} (keys(%{$tlw{$tag}}));
    for(my $i = 0; $i < 3; $i++)
    {
        last unless(defined($mrich_lemmas[$i]));
        my @richest_paradigm = sort(keys(%{$tlw{$tag}{$mrich_lemmas[$i]}}));
        my $richness = scalar(@richest_paradigm);
        my $rank = ($i+1).($i==0 ? 'st' : $i==1 ? 'nd' : $i==2 ? 'rd' : 'th');
        $page .= "The $rank highest number of forms ($richness) was observed with the lemma “$mrich_lemmas[$i]”: ".fex(join(', ', @richest_paradigm)).".\n\n";
    }
    if(scalar(keys(%{$tf{$tag}})) > 0)
    {
        my ($list, $n) = list_keys_with_counts($tf{$tag}, $tagset{$tag}, "$langcode-feat/");
        $page .= "`$tag` occurs with $n features: $list\n\n";
        my @featurepairs = map {"`$_`"} (sort(keys(%{$tfv{$tag}})));
        my $nfeaturepairs = scalar(@featurepairs);
        $page .= "`$tag` occurs with $nfeaturepairs feature-value pairs: ".join(', ', @featurepairs)."\n\n";
        my @featuresets = sort {$tfset{$tag}{$b} <=> $tfset{$tag}{$a}} (keys(%{$tfset{$tag}}));
        my $nfeaturesets = scalar(@featuresets);
        $examples = prepare_examples($examples{$tag."\t".$featuresets[0]}, $limit);
        # The vertical bar separates table columns in Markdown. We must escape it if we are generating content for Github pages.
        # Update: The vertical bar is not treated as a special character if it is inside `code text`.
        my $escaped_featureset = $featuresets[0];
        #$escaped_featureset =~ s/\|/\\\|/g;
        $page .= "`$tag` occurs with $nfeaturesets feature combinations.\n";
        $page .= "The most frequent feature combination is `$escaped_featureset` ($tfset{$tag}{$featuresets[0]} tokens).\n";
        $page .= "Examples: ".fex($examples)."\n\n";
    }
    else
    {
        $page .= "`$tag` does not occur with any features.\n\n";
    }
    $page .= "\n";
    # Dependency relations.
    $page .= "## Relations\n\n";
    my ($list, $n) = list_keys_with_counts($tagdeprel{$tag}, $tagset{$tag}, "$langcode-dep/");
    $page .= "`$tag` nodes are attached to their parents using $n different relations: $list\n\n";
    ($list, $n) = list_keys_with_counts($parenttag{$tag}, $tagset{$tag}, '');
    $page .= "Parents of `$tag` nodes belong to $n different parts of speech: $list\n\n";
    my $n0c = $tagdegree{$tag}{0} // 0;
    my $p0c = percent($n0c, $tagset{$tag});
    $page .= "$n0c ($p0c) `$tag` nodes are leaves.\n\n";
    if($maxtagdegree{$tag} > 0)
    {
        my $n1c = $tagdegree{$tag}{1} // 0;
        my $p1c = percent($n1c, $tagset{$tag});
        $page .= "$n1c ($p1c) `$tag` nodes have one child.\n\n";
        if($maxtagdegree{$tag} > 1)
        {
            my $n2c = $tagdegree{$tag}{2} // 0;
            my $p2c = percent($n2c, $tagset{$tag});
            $page .= "$n2c ($p2c) `$tag` nodes have two children.\n\n";
            if($maxtagdegree{$tag} > 2)
            {
                my $n3c = $tagdegree{$tag}{3} // 0;
                my $p3c = percent($n3c, $tagset{$tag});
                $page .= "$n3c ($p3c) `$tag` nodes have three or more children.\n\n";
            }
        }
    }
    $page .= "The highest child degree of a `$tag` node is $maxtagdegree{$tag}.\n\n";
    if($maxtagdegree{$tag} > 0)
    {
        ($list, $n) = list_keys_with_counts($childtagdeprel{$tag}, $nchildren{$tag}, "$langcode-dep/");
        $page .= "Children of `$tag` nodes are attached using $n different relations: $list\n\n";
        ($list, $n) = list_keys_with_counts($childtag{$tag}, $nchildren{$tag}, '');
        $page .= "Children of `$tag` nodes belong to $n different parts of speech: $list\n\n";
    }
    return $page;
}



#------------------------------------------------------------------------------
# Generates statistics of all features and saves them in the docs repository.
#------------------------------------------------------------------------------
sub detailed_statistics_features
{
    local $docspath = $konfig{docspath};
    local $langcode = $konfig{langcode};
    local $limit = 10;
    # Identify layered features.
    local %layers;
    local %base_features;
    foreach my $feature (@featureset)
    {
        my ($base, $layer);
        if($feature =~ m/^(\w+)\[(.+)\]$/)
        {
            $base = $1;
            $layer = $2;
        }
        else
        {
            $base = $feature;
            $layer = 'DEFAULT';
        }
        $layers{$base}{$layer} = $feature;
        $base_features{$feature} = $base;
    }
    foreach my $feature (@featureset)
    {
        my $path = "$docspath/_includes/stats/$langcode/feat";
        mkdir($path) unless(-d $path);
        my $file = "$path/$feature.md";
        # Layered features do not have the brackets in their file names.
        $file =~ s/\[(.+)\]/-$1/;
        my $page = get_detailed_statistics_feature($feature);
        print STDERR ("Writing $file\n");
        open(PAGE, "$mode$file") or die("Cannot write $file: $!");
        print PAGE ($page);
        close(PAGE);
    }
}



#------------------------------------------------------------------------------
# Detailed statistics about a feature:
#
# - Is this a language-specific feature?
# - If the feature is universal, are there additional language-specific values
#   used with this feature?
# - How many tokens and types have a non-empty value of this feature? How many
#   different lemmas and parts of speech occur at least once with this feature?
# - For every part of speech with which the feature occurs separate section:
# -- How many tokens in this class occur with the feature?
# -- Is there a specific value of another feature, that is always the same when
#    the current feature is non-empty? (Motivation for this question: some
#    features will be only used with personal pronouns. The other feature will
#    be PronType and the fixed value will be Prs.)
# -- What values of the feature are used and how frequent are they?
# -- Most frequent examples for every value of the feature.
# -- Most frequent examples of words that do not have this feature.
# -- Examples of lemmas for which all (or many) values of the feature have been
#    observed. Show the inflection paradigm of the word! Try to fix the values
#    of the other features if possible. For example, if showing forms of
#    different cases, try not to mix singular and plural examples.
# -- Does the feature appear to be lexical? Is it rare to see multiple values
#    of the feature with the same lemma?
# -- If it is frequent to see different values of the feature with one lemma
#    (i.e. the feature seems to be inflectional), do the word forms really
#    change? Not necessarily always, but often enough?
# -- Are there two values of the feature that have always the same form when
#    they occur with instances of the same lemma? (This would indicate that the
#    values are context-sensitive. It might be useful to show examples of the
#    entire sentences.)
# -- Alternating word forms. Fixed combination of lemma and values of all
#    features, the current feature must have a non-empty value, more than one
#    word form must be observed. The most frequent examples only (the alternate
#    word form could be a typo; but we hope that typos are infrequent). Do not
#    do this for lexical features.
# -- If this is a layered feature, list all layers and give examples of words
#    that have set two or more layers of this feature.
# - Are there relations where the parent and the child agree in the feature?
#------------------------------------------------------------------------------
sub get_detailed_statistics_feature
{
    my $feature = shift;
    my $page;
    $page .= "\n\n--------------------------------------------------------------------------------\n\n";
    $page .= "## Treebank Statistics ($treebank_id)\n\n";
    # Count values. Dissolve multivalues.
    my @values = sort(keys(%{$fv{$feature}}));
    my %svalues;
    foreach my $v (@values)
    {
        my @svalues = split(/,/, $v);
        foreach my $sv (@svalues)
        {
            $svalues{$sv}++;
        }
    }
    my @svalues = sort(keys(%svalues));
    my $nsvalues = scalar(@svalues);
    my $universal = '';
    # Override alphabetic ordering of feature values.
    local %sort_values;
    if(exists($universal_features{$feature}))
    {
        $universal = 'universal';
        for(my $i = 0; $i <= $#{$universal_features{$feature}}; $i++)
        {
            $sort_values{$universal_features{$feature}[$i]} = $i;
        }
        # Are all values universal?
        my @lsvalues = grep {my $v = $_; scalar(grep {$_ eq $v} (@{$universal_features{$feature}})) == 0} (@svalues);
        if(@lsvalues)
        {
            $universal .= ' but the values '.join(', ', map {"`$_`"} (@lsvalues)).' are language-specific';
            foreach my $lsv (@lsvalues)
            {
                $sort_values{$lsv} = 1000;
            }
        }
    }
    else
    {
        $universal = 'language-specific';
    }
    $page .= "This feature is $universal.\n";
    if($nvalues == 1)
    {
        $page .= "It occurs only with 1 value: ";
    }
    else
    {
        $page .= "It occurs with $nsvalues different values: ";
    }
    $page .= join(', ', map {"`$_`"} (@svalues)).".\n";
    my @mvalues = map {s/,/|/g; $_} (grep {/,/} (@values));
    my $nmvalues = scalar(@mvalues);
    if($nmvalues > 0)
    {
        $page .= "Some words have combined values of the feature; $nmvalues combinations have been observed: ".join(', ', map {"`$_`"} (@mvalues)).".\n";
    }
    $page .= "\n";
    my $base_feature = $base_features{$feature};
    my @layers = sort(keys(%{$layers{$base_feature}}));
    if(scalar(@layers) > 1)
    {
        # We are linking e.g. from pt/feat/Number.html to u/overview/feat-layers.html.
        $page .= 'This is a <a href="../../u/overview/feat-layers.html">layered feature</a> with the following layers: '.join(', ', map {"[$layers{$base_feature}{$_}]()"} (@layers)).".\n\n";
    }
    my $n = $featureset{$feature};
    my $p = percent($n, $nword);
    $page .= "$n tokens ($p) have a non-empty value of `$feature`.\n";
    $n = scalar(keys($fw{$feature}));
    $p = percent($n, scalar(@words));
    $page .= "$n types ($p) occur at least once with a non-empty value of `$feature`.\n";
    $n = scalar(keys($fl{$feature}));
    $p = percent($n, scalar(@lemmas));
    $page .= "$n lemmas ($p) occur at least once with a non-empty value of `$feature`.\n";
    # List part-of-speech tags with which this feature occurs.
    my $list; ($list, $n) = list_keys_with_counts($ft{$feature}, $nword, "$langcode-pos/");
    $page .= "The feature is used with $n part-of-speech tags: $list.\n\n";
    my @tags = sort {$ft{$feature}{$b} <=> $ft{$feature}{$a}} (keys(%{$ft{$feature}}));
    foreach my $tag (@tags)
    {
        $page .= "### `$tag`\n\n";
        $n = $ft{$feature}{$tag};
        $p = percent($n, $tagset{$tag});
        $page .= "$n [$langcode-pos/$tag]() tokens ($p of all `$tag` tokens) have a non-empty value of `$feature`.\n\n";
        # Is this feature used exclusively with some other feature?
        # We are interested in features that can be non-empty with the current tag in a significant percentage of cases.
        my @other_features = grep {$tf{$tag}{$_} / $tagset{$tag} > 0.1} (keys(%{$tf{$tag}}));
        # Get all feature combinations observed with the current tag.
        my @fsets_packed = keys(%{$tfset{$tag}});
        my %other_features;
        foreach my $fsp (@fsets_packed)
        {
            my %fs;
            foreach my $fv (split(/\|/, $fsp))
            {
                my ($f, $v) = split(/=/, $fv);
                $fs{$f} = $v;
            }
            # Filter the feature combinations to those that have the current feature set.
            next if(!defined($fs{$feature}));
            # Count values of all other features (meaning all features that can be non-empty with this tag; even if they are empty in this combination).
            foreach my $f (@other_features)
            {
                unless($f eq $feature)
                {
                    my $v = $fs{$f} // 'EMPTY';
                    $other_features{"$f=$v"} += $tfset{$tag}{$fsp};
                }
            }
        }
        # Report feature-value pairs whose frequency exceeds 50% of the occurrences of the current feature.
        my @frequent_pairs = sort {$other_features{$b} <=> $other_features{$a}} (grep {$other_features{$_} / $ft{$feature}{$tag} > 0.5} (keys(%other_features)));
        if(scalar(@frequent_pairs) > 0)
        {
            splice(@frequent_pairs, $limit);
            @frequent_pairs = map
            {
                my $x = $_;
                my $n = $other_features{$x};
                my $p = percent($n, $ft{$feature}{$tag});
                $x =~ s/^(.+)=(.+)$/<tt><a href="$1.html">$1<\/a>=$2<\/tt>/;
                "$x ($n; $p)"
            }
            (@frequent_pairs);
            $page .= "The most frequent other feature values with which `$tag` and `$feature` co-occurred: ".join(', ', @frequent_pairs).".\n\n";
        }
        # List values of the feature with this tag.
        $page .= "`$tag` tokens may have the following values of `$feature`:\n\n";
        my @values = sort(map {s/^$feature=//; $_} (grep {m/^$feature=/} (keys(%{$tfv{$tag}}))));
        foreach my $value (@values)
        {
            $n = $tfv{$tag}{"$feature=$value"};
            $p = percent($n, $tf{$tag}{$feature});
            my $examples = prepare_examples($examples{"$tag\t$feature=$value"}, $limit);
            $page .= "* `$value` ($n; $p of non-empty `$feature`): ".fex($examples)."\n";
        }
        $n = $tagset{$tag} - $ft{$feature}{$tag};
        my $examples = prepare_examples($examples{"$tag\t$feature=EMPTY"}, $limit);
        # There might be no examples even if $n > 0. We collect examples only for universal features, not for language-specific ones.
        ###!!! We may want to collect them for language-specific features. But we do not know in advance what these features are!
        ###!!! Maybe we should use just general examples of the tag, and grep them for not having the feature set?
        if($examples)
        {
            $page .= "* `EMPTY` ($n): ".fex($examples)."\n";
        }
        $page .= "\n";
        # Show examples of lemmas for which all (or many) values of the feature have been observed.
        # This should provide an image of a complete paradigm with respect to this feature.
        # Try to fix the values of the other features if possible (e.g. do not mix singular and plural when showing case inflection).
        # $paradigm{$tag}{$f}{$lemma}{$v}{$other_features}{$word}++;
        my @paradigms = sort
        {
            my $result = scalar(keys(%{$paradigm{$tag}{$feature}{$b}})) <=> scalar(keys(%{$paradigm{$tag}{$feature}{$a}}));
            unless($result)
            {
                $result = $lemmatag{$b}{$tag} <=> $lemmatag{$a}{$tag};
            }
            $result
        }
        keys(%{$paradigm{$tag}{$feature}});
        # Do not show the paradigm if the lemma is empty ('_'). There would be thousands of word forms and the table would not be interesting.
        unless($paradigms[$i] eq '_')
        {
            $page .= get_paradigm_table($paradigms[$i], $tag, $feature);
        }
        # How many $lemmas have only one value of this feature? Is the feature lexical?
        # Do this only for feature-tag combinations that appear with enough lemmas.
        my $total = scalar(@paradigms);
        if($total >= 10)
        {
            my @lemmas_with_only_one_value = grep {scalar(keys(%{$paradigm{$tag}{$feature}{$_}})) == 1} (@paradigms);
            $n = scalar(@lemmas_with_only_one_value);
            $p = percent($n, $total);
            if($n / $total > 0.9)
            {
                $page .= "`$feature` seems to be **lexical feature** of `$tag`. $p lemmas ($n) occur only with one value of `$feature`.\n\n";
            }
        }
        ###!!! NOT YET IMPLEMENTED
        # If it is frequent to see different values of the feature with one lemma
        # (i.e. the feature seems to be inflectional), do the word forms really
        # change? Not necessarily always, but often enough?
        ###!!!
    }
    # Agreement in this feature between parent and child of a relation.
    my @agreement = grep {$agreement{$feature}{$_} > $disagreement{$feature}{$_}} (keys(%{$agreement{$feature}}));
    @agreement = sort {$agreement{$feature}{$b} <=> $agreement{$feature}{$a}} (@agreement);
    splice(@agreement, $limit);
    if(scalar(@agreement) > 0)
    {
        $page .= "## Relations with Agreement in `$feature`\n\n";
        $page .= "The $limit most frequent relations where parent and child node agree in `$feature`:\n";
        $page .= join(",\n", map
        {
            my $p = percent($agreement{$feature}{$_}, $agreement{$feature}{$_}+$disagreement{$feature}{$_});
            my $link = $_;
            $link =~ s/--\[(.*)?\]--/--[<a href="..\/dep\/$1.html">$1<\/a>]--/;
            "<tt>$link</tt> ($agreement{$feature}{$_}; $p)"
        }
        (@agreement)).".\n\n";
    }
    return $page;
}



#------------------------------------------------------------------------------
# Generates the paradigm table of a given lemma, focused on values of one
# particular feature.
#------------------------------------------------------------------------------
sub get_paradigm_table
{
    my $lemma = shift;
    my $tag = shift;
    my $feature = shift;
    my $page = '';
    my $paradigm = $paradigm{$tag}{$feature}{$lemma};
    # Override alphabetic ordering of feature values.
    my @values = sort
    {
        my $result = $sort_values{$a} <=> $sort_values{$b};
        unless($result)
        {
            $result = $a cmp $b;
        }
        $result
    }
    (keys(%{$paradigm}));
    if(scalar(@values) > 1)
    {
        # Get all combinations of other features observed with any value.
        my %other_features;
        my %sort_other_features;
        foreach my $v (@values)
        {
            my @other_features = keys(%{$paradigm->{$v}});
            foreach my $of (@other_features)
            {
                $other_features{$of}++;
                ###!!! Pokus s řazením rysů.
                # In general we want alphabetic ordering but there are some exceptions, e.g. singular number should precede plural.
                my $ofsort = $of;
                $ofsort =~ s/Gender=Masc/Gender=1Masc/;
                $ofsort =~ s/Gender=Fem/Gender=2Fem/;
                $ofsort =~ s/Gender=Com/Gender=3Com/;
                $ofsort =~ s/Gender=Neut/Gender=4Neut/;
                $ofsort =~ s/Number=Sing/Number=1Sing/;
                $ofsort =~ s/Number=Dual/Number=2Dual/;
                $ofsort =~ s/Number=Plur/Number=3Plur/;
                $ofsort =~ s/Degree=Pos/Degree=1Pos/;
                $ofsort =~ s/Degree=Cmp/Degree=2Cmp/;
                $ofsort =~ s/Degree=Sup/Degree=3Sup/;
                $ofsort =~ s/Degree=Abs/Degree=4Abs/;
                $sort_other_features{$of} = $ofsort;
            }
        }
        my @other_features = sort
        {
            my $aa = lc($sort_other_features{$a});
            my $bb = lc($sort_other_features{$b});
            $aa cmp $bb
        }
        (keys(%other_features));
        # Keep track of all individual other features.
        # We will want to hide those that appear everywhere.
        my %map_other_features;
        foreach my $of (@other_features)
        {
            my @of = split(/\|/, $of);
            foreach my $ofv (@of)
            {
                $map_other_features{$ofv}++;
            }
        }
        $page .= "<table>\n";
        $page .= "  <tr><th>Paradigm <i>$lemma</i></th>";
        foreach my $v (@values)
        {
            $page .= "<th><tt>$v</tt></th>";
        }
        $page .= "</tr>\n";
        foreach my $of (@other_features)
        {
            # Do not display other features that occur in all combinations.
            my @of = split(/\|/, $of);
            @of = grep {$map_other_features{$_} < scalar(@other_features)} (@of);
            my $showof = join('|', map {s/^(.+)=(.+)$/<a href="$1.html">$1<\/a>=$2/; $_} (@of));
            $page .= "  <tr><td><tt>$showof</tt></td>";
            foreach my $v (@values)
            {
                $page .= "<td>";
                my $vforms = $paradigm->{$v}{$of};
                prune_examples($vforms);
                my @vforms = sort {my $r = $vforms->{$b} <=> $vforms->{$a}; unless($r) {$r = $vforms->{$a} cmp $vforms->{$b}} $r} (keys(%{$vforms}));
                if(scalar(@vforms) > 0)
                {
                    $page .= fex(join(', ', @vforms));
                }
                $page .= "</td>";
            }
            $page .= "</tr>\n";
        }
        $page .= "</table>\n\n";
    }
    return $page;
}



#------------------------------------------------------------------------------
# Generates statistics of all relations and saves them in the docs repository.
#------------------------------------------------------------------------------
sub detailed_statistics_relations
{
    local $docspath = $konfig{docspath};
    local $langcode = $konfig{langcode};
    local $limit = 10;
    # Identify clusters of universal relations and their language-specific subtypes.
    local %clusters;
    local %base_relations;
    foreach my $deprel (@deprelset)
    {
        my ($base, $extension);
        if($deprel =~ m/^(\w+):(\w+)$/)
        {
            $base = $1;
            $extension = $2;
        }
        else
        {
            $base = $deprel;
            $extension = '';
        }
        $clusters{$base}{$extension} = $deprel;
        $base_relations{$deprel} = $base;
    }
    foreach my $deprel (@deprelset)
    {
        my $path = "$docspath/_includes/stats/$langcode/dep";
        mkdir($path) unless(-d $path);
        my $file = "$path/$deprel.md";
        # Language-specific relations do not have the colon in their file names.
        $file =~ s/:/-/;
        $file =~ s/aux\.md/aux_.md/;
        my $page = get_detailed_statistics_relation($deprel);
        print STDERR ("Writing $file\n");
        open(PAGE, "$mode$file") or die("Cannot write $file: $!");
        print PAGE ($page);
        close(PAGE);
    }
}



#------------------------------------------------------------------------------
# Detailed statistics about a relation:
#
# - Is this a language-specific subtype? Are there other subtypes of the same
#   universal relation?
# - If it is universal, does it have language-specific subtypes?
# - How many nodes are attached to their parent using this relation?
# - How often is this relation left-to-right vs. right-to-left?
# - What is the average length of this relation (right position minus left
#   position)?
# - How many different types are at least once attached using this relation?
# -- What are the most frequent types?
# - How many different types are at least once parents in this relation?
# -- What are the most frequent types?
# - Same for lemmas, tags and feature-value pairs.
# - What are the most frequent combinations of parent tag and child tag?
# -- For each combination, give the most frequent examples of word forms.
# -- Visualize these examples using Brat.
# - How often is this relation non-projective?
#------------------------------------------------------------------------------
sub get_detailed_statistics_relation
{
    my $deprel = shift;
    my $page;
    $page .= "\n\n--------------------------------------------------------------------------------\n\n";
    $page .= "## Treebank Statistics ($treebank_id)\n\n";
    # Universal versus language-specific.
    my $cluster = $clusters{$base_relations{$deprel}};
    my @subtypes = map {$cluster->{$_}} (grep {$_ ne ''} (sort(keys(%{$cluster}))));
    if($base_relations{$deprel} eq $deprel)
    {
        $page .= "This relation is universal.\n";
        my $nsubtypes = scalar(@subtypes);
        if($nsubtypes > 0)
        {
            $page .= "There are $nsubtypes language-specific subtypes of `$deprel`: ";
            $page .= join(', ', map {"[$_]()"} (@subtypes));
            $page .= ".\n";
        }
    }
    else
    {
        my $base = $base_relations{$deprel};
        $page .= "This relation is a language-specific subtype of [$base]().\n";
        my $nsubtypes = scalar(@subtypes) - 1;
        if($nsubtypes > 0)
        {
            $page .= "There are also $nsubtypes other language-specific subtypes of `$base`: ";
            $page .= join(', ', map {"[$_]()"} (grep {$_ ne $deprel} (@subtypes)));
            $page .= ".\n";
        }
    }
    $page .= "\n";
    # Counts.
    my $n = $deprelset{$deprel};
    my $p = percent($n, $nword);
    $page .= "$n nodes ($p) are attached to their parents as `$deprel`.\n\n";
    my $nltr = $ltrdeprel{$deprel};
    my $nrtl = $n - $nltr;
    if($nltr >= $nrtl)
    {
        $p = percent($nltr, $n);
        $page .= "$nltr instances of `$deprel` ($p) are left-to-right (parent precedes child).\n";
    }
    else
    {
        $p = percent($nrtl, $n);
        $page .= "$nrtl instances of `$deprel` ($p) are right-to-left (child precedes parent).\n";
    }
    my $avglen = $deprellen{$deprel} / $n;
    $page .= "Average distance between parent and child is $avglen.\n\n";
    # Word types, lemmas, tags and features.
    my $list;
    ($list, $n) = list_keys_with_counts($depreltags{$deprel}, $deprelset{$deprel}, "$langcode-pos/");
    $page .= "The following $n pairs of parts of speech are connected with `$deprel`: $list.\n\n";
    ###!!! Maybe we should not have used list_keys_with_counts() above because now we have to sort the same list again.
    my @tagpairs = sort {$depreltags{$deprel}{$b} <=> $depreltags{$deprel}{$a}} (keys(%{$depreltags{$deprel}}));
    for(my $i = 0; $i < 3; $i++)
    {
        last if($i > $#tagpairs);
        my @tags = split(/-/, $tagpairs[$i]);
        #my $sentence = $exentdtt{$deprel}{$tags[0]}{$tags[1]};
        #$page .= "* `$tagpairs[$i]`: _${sentence}_\n";
        my $conllu = $exconlludtt{$deprel}{$tags[0]}{$tags[1]};
        $page .= "\n~~~ conllu\n".$conllu."~~~\n\n";
    }
    $page .= "\n";
    return $page;
}



#------------------------------------------------------------------------------
# Formats example word(s) using MarkDown. Normally this means just surrounding
# the example by the markup for italics / emphasized. But italics is not used
# with languages using certain writing systems.
#------------------------------------------------------------------------------
sub fex
{
    my $example = shift;
    my $i = $languages{$konfig{langcode}}{i};
    if($i)
    {
        # We could use underscores or asterisks instead of <em> (MarkDown instead of HTML).
        # But <em> is safer. MarkDown syntax does not work in certain contexts.
        $example = '<em>'.$example.'</em>';
    }
    return $example;
}



#------------------------------------------------------------------------------
# Joins a list of examples to one string, using comma and space as the
# separator. Uses a language-specific comma character (Arabic does not use
# ','). This function should not be used for lists where example words are
# mixed with other stuff, e.g. counts in parentheses. The default comma should
# be used in such cases.
#------------------------------------------------------------------------------
sub jcomma
{
    my @list = @_;
    my $c = $languages{$konfig{langcode}}{c};
    return join($c.' ', @list);
}



#------------------------------------------------------------------------------
# Takes a hash of example words for a given phenomenon (e.g., for a POS tag).
# Values in the hash are frequencies of the words. Returns the list (as string)
# of the N most frequent examples, in descendeng order by frequency.
#------------------------------------------------------------------------------
sub prepare_examples
{
    my $examplehash = shift; # e.g. $examples{$tag}: keys are words, values are counts
    my $limit = shift; # how many most frequent examples shall be returned
    my @examples = keys(%{$examplehash});
    @examples = sort_and_truncate_examples($examplehash, \@examples, $limit);
    return jcomma(@examples);
}



#------------------------------------------------------------------------------
# Takes a hash of example words for a given phenomenon (e.g., for a POS tag).
# Also takes a list of elligible example words (this function does not call
# keys(%{$examplehash}) itself; hence the caller may grep the examples by
# additional criteria). Sorts the examples by frequencies and returns the N
# most frequent ones (as a real list, not as a string).
#------------------------------------------------------------------------------
sub sort_and_truncate_examples
{
    my $examplehash = shift; # e.g. $examples{$tag}: keys are words, values are counts
    my $selected_keys = shift; # arrayref; may be grepped before we sort them
    my $limit = shift; # how many most frequent examples shall be returned
    my @examples = sort
    {
        my $result = $examplehash->{$b} <=> $examplehash->{$a};
        unless($result)
        {
            $result = $a cmp $b;
        }
        $result
    }
    (@{$selected_keys});
    splice(@examples, $limit);
    return @examples;
}



#------------------------------------------------------------------------------
# Returns the list (as string) of elements with which this element has been
# observed, together with counts and percentages. For example, returns the list
# of dependency relation labels with which a part-of-speech tag has been seen.
#------------------------------------------------------------------------------
sub list_keys_with_counts
{
    my $freqhash = shift; # gives frequency for each key
    my $totalcount = shift; # total frequency of all keys (inefficient to compute here because it is typically already known) ###!!! OR NO?
    my $linkprefix = shift; # for links from POS to dependency relations, "$langcode-dep/" must be prepended; for link from POS to POS, the prefix is empty
    my @keys = sort
    {
        my $result = $freqhash->{$b} <=> $freqhash->{$a};
        unless($result)
        {
            $result = $a cmp $b;
        }
        $result
    }
    (keys(%{$freqhash}));
    my $n = scalar(@keys);
    my $linkprefix_is_pos = $linkprefix =~ m/-pos/;
    my $list = join(', ', map
    {
        my $x = $_;
        my $p = percent($freqhash->{$_}, $totalcount);
        my $link;
        if($linkprefix_is_pos && $x =~ m/-/)
        {
            my ($a, $b) = split(/-/, $x);
            $link = "[$linkprefix$a]()-[$linkprefix$b]()";
        }
        else
        {
            $link = "[$linkprefix$x]()";
        }
        "$link ($freqhash->{$x}; $p instances)"
    }
    (@keys));
    return ($list, $n);
}



#------------------------------------------------------------------------------
# Computes percentage, rounds it and adds the '%' symbol.
#------------------------------------------------------------------------------
sub percent
{
    my $part = shift;
    my $whole = shift;
    return 0 if($whole == 0);
    return sprintf("%d%%", ($part/$whole)*100+0.5);
}



#------------------------------------------------------------------------------
# Prints fundamental statistics about words, lemmas, part-of-speech tags,
# features and dependency relations to the standard output. The output of this
# function is included with each treebank in the stats.xml file.
#------------------------------------------------------------------------------
sub simple_xml_statistics
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
    print("  <feats unique=\"".scalar(@fvset)."\">\n");
    foreach my $feature (@fvset)
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
        print('    <feat name="'.$name.'" value="'.$value.'" upos="'.$upostags.'">'.$fvset{$feature}.'</feat><!-- ', join(', ', @examples), " -->\n");
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
