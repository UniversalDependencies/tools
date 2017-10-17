#!/usr/bin/perl
# Reads CoNLL(-U) data from STDIN, collects all features (FEAT column, delimited by vertical bars) and prints them sorted to STDOUT.
# Copyright © 2013-2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;

sub usage
{
    print STDERR ("cat *.conllu | perl conllu-stats.pl > stats.xml\n");
    print STDERR ("... generates the basic statistics that accompany each treebank.\n");
    print STDERR ("perl conllu-stats.pl --oformat detailed --data .. --docs ../docs --lang pt\n");
    print STDERR ("... adds detailed statistics of each tag, feature and relation to the documentation source pages.\n");
    print STDERR ("    data = parent folder of the data repositories, e.g. of UD_English\n");
    print STDERR ("    The script will analyze all treebanks of the given language.\n");
    print STDERR ("cat *.conllu | perl conllu-stats.pl --oformat hub\n");
    print STDERR ("... generates statistics parallel to the language-specific documentation hub.\n");
    print STDERR ("perl conllu-stats.pl --oformat hubcompare cs_pdt.conllu cs_cac.conllu sv.conllu\n");
    print STDERR ("... similar to hub but compares two or more treebanks side-by-side.\n");
}

use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;

# Read options.
$konfig{iformat} = '';
$konfig{oformat} = 'simple'; # simple = stats.xml; hub = markdown one-page summary; detailed = markdown, separate page for each tag/feat/rel
$konfig{relative} = 0; # relative frequencies of POS tags instead of absolute counts (affects only simple XML statistics)
$konfig{datapath} = '.'; # if detailed: parent folder of the data repositories (of UD_$language).
$konfig{docspath} = '../docs'; # if detailed: where is the docs repository? We will modify the page sources there.
$konfig{langcode} = ''; # if detailed; used to identify docs that shall be modified, and also in links inside
GetOptions
(
    'iformat=s'  => \$konfig{iformat},
    'oformat=s'  => \$konfig{oformat},
    'relative'   => \$konfig{relative},
    'data=s'     => \$konfig{datapath},
    'docs=s'     => \$konfig{docspath},
    'language=s' => \$konfig{langcode},
    'help'       => \$konfig{help}
);
exit(usage()) if($konfig{help});
if($konfig{oformat} eq 'detailed' && $konfig{langcode} eq '')
{
    usage();
    die("Missing language code for detailed analysis");
}
# Format "2009" toggles the CoNLL 2009 data format.
my $i_feat_column = $konfig{iformat} eq '2009' ? 6 : 5;
my %universal_features =
(
    'PronType' => ['Prs', 'Rcp', 'Art', 'Int', 'Rel', 'Dem', 'Tot', 'Neg', 'Ind'],
    'NumType'  => ['Card', 'Ord', 'Mult', 'Frac', 'Sets', 'Dist', 'Range', 'Gen'],
    'Poss'     => ['Yes'],
    'Reflex'   => ['Yes'],
    'Foreign'  => ['Yes'],
    'Abbr'     => ['Yes'],
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
    'Evident'  => ['Nfh'],
    'Person'   => ['1', '2', '3'],
    'Polite'   => ['Infm', 'Form'],
    'Polarity' => ['Pos', 'Neg'],
);
my %languages =
(   # i ... should we use italics when displaying examples from this language?
    # c ... the character to be used as example separating comma.
    'am'  => {'name' => 'Amharic',    'i' => 0, 'c' => ','},
    'grc' => {'name' => 'Ancient Greek', 'i' => 1, 'c' => ','},
    'ar'  => {'name' => 'Arabic',     'i' => 0, 'c' => '،'},
    'eu'  => {'name' => 'Basque',     'i' => 1, 'c' => ','},
    'be'  => {'name' => 'Belarusian', 'i' => 1, 'c' => ','},
    'bg'  => {'name' => 'Bulgarian',  'i' => 1, 'c' => ','},
    'ca'  => {'name' => 'Catalan',    'i' => 1, 'c' => ','},
    'zh'  => {'name' => 'Chinese',    'i' => 0, 'c' => '、'},
    'cop' => {'name' => 'Coptic',     'i' => 0, 'c' => ','},
    'hr'  => {'name' => 'Croatian',   'i' => 1, 'c' => ','},
    'cs'  => {'name' => 'Czech',      'i' => 1, 'c' => ','},
    'da'  => {'name' => 'Danish',     'i' => 1, 'c' => ','},
    'nl'  => {'name' => 'Dutch',      'i' => 1, 'c' => ','},
    'en'  => {'name' => 'English',    'i' => 1, 'c' => ','},
    'et'  => {'name' => 'Estonian',   'i' => 1, 'c' => ','},
    'fi'  => {'name' => 'Finnish',    'i' => 1, 'c' => ','},
    'fr'  => {'name' => 'French',     'i' => 1, 'c' => ','},
    'gl'  => {'name' => 'Galician',   'i' => 1, 'c' => ','},
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
    'lv'  => {'name' => 'Latvian',    'i' => 1, 'c' => ','},
    'lt'  => {'name' => 'Lithuanian', 'i' => 1, 'c' => ','},
    'no'  => {'name' => 'Norwegian',  'i' => 1, 'c' => ','},
    'cu'  => {'name' => 'Old Church Slavonic', 'i' => 1, 'c' => ','},
    'fa'  => {'name' => 'Persian',    'i' => 0, 'c' => '،'},
    'pl'  => {'name' => 'Polish',     'i' => 1, 'c' => ','},
    'pt'  => {'name' => 'Portuguese', 'i' => 1, 'c' => ','},
    'ro'  => {'name' => 'Romanian',   'i' => 1, 'c' => ','},
    'ru'  => {'name' => 'Russian',    'i' => 1, 'c' => ','},
    'sa'  => {'name' => 'Sanskrit',   'i' => 0, 'c' => ','},
    'sk'  => {'name' => 'Slovak',     'i' => 1, 'c' => ','},
    'sl'  => {'name' => 'Slovenian',  'i' => 1, 'c' => ','},
    'es'  => {'name' => 'Spanish',    'i' => 1, 'c' => ','},
    'sv'  => {'name' => 'Swedish',    'i' => 1, 'c' => ','},
    'swl' => {'name' => 'Swedish Sign Language', 'i' => 1, 'c' => ','},
    'ta'  => {'name' => 'Tamil',      'i' => 0, 'c' => ','},
    'tr'  => {'name' => 'Turkish',    'i' => 1, 'c' => ','},
    'uk'  => {'name' => 'Ukrainian',  'i' => 1, 'c' => ','},
    'ur'  => {'name' => 'Urdu',       'i' => 0, 'c' => '،'},
    'ug'  => {'name' => 'Uyghur',     'i' => 0, 'c' => '،'},
    'vi'  => {'name' => 'Vietnamese', 'i' => 1, 'c' => ','},
);
if($konfig{oformat} eq 'detailed')
{
    if(!exists($languages{$konfig{langcode}}))
    {
        die("Unknown language code '$konfig{langcode}'");
    }
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
        # We set mode '>' for the first treebank in the language but it is not enough.
        # If a label occurs only in the second treebank, nothing will be written with the '>' mode and the new statistics will be appended to the old ones!
        # And if a label was used in the past but has become obsolete now, we must remove the corresponding file.
        # Therefore we will now remove the entire folder subtree and start from scratch.
        if(-d $target_path)
        {
            # But do not remove the subtree after the first treebank has been processed.
            if($mode eq '>')
            {
                system("rm -rf $target_path");
                mkdir($target_path) or die("Cannot create folder $target_path: $!");
            }
        }
        else
        {
            mkdir($target_path) or die("Cannot create folder $target_path: $!");
            mkdir("$target_path/pos") or die("Cannot create folder $target_path/pos: $!");
            mkdir("$target_path/feat") or die("Cannot create folder $target_path/feat: $!");
            mkdir("$target_path/dep") or die("Cannot create folder $target_path/dep: $!");
        }
        process_treebank();
        $mode = '>>';
    }
}
elsif($konfig{oformat} eq 'hubcompare')
{
    print <<EOF
---
layout: base
title:  'Comparison of Treebank Statistics'
permalink: cs/overview/cs-hub-comparison.html
udver: '2'
---

EOF
    ;
    my @treebanks = @ARGV;
    my $n_treebanks = scalar(@treebanks);
    my $width_percent = sprintf("%d", 100/$n_treebanks);
    my @tbkhubs;
    my $max_cells = 0;
    print STDERR ("The following treebanks will be compared: ", join(', ', @treebanks), "\n");
    foreach my $treebank (@treebanks)
    {
        print STDERR ("Processing $treebank...\n");
        @ARGV = ($treebank);
        my @cells = process_treebank();
        unshift(@cells, "<h1>$treebank</h1>\n");
        push(@tbkhubs, \@cells);
        $max_cells = scalar(@cells) if(scalar(@cells) > $max_cells);
    }
    print("<table>\n");
    for(my $i = 0; $i < $max_cells; $i++)
    {
        print("<tr>\n");
        foreach my $hub (@tbkhubs)
        {
            print("  <td width=\"$width_percent\%\" valign=\"top\">\n");
            print("$hub->[$i]\n");
            print("  </td>\n");
        }
        print("</tr>\n");
    }
    print("</table>\n");
}
else
{
    # Take either STDIN or the CoNLL-U files specified on the command line.
    if(scalar(@ARGV)>0)
    {
        print STDERR ("The following files will be processed: ", join(', ', @ARGV), "\n");
    }
    else
    {
        print STDERR ("No command-line arguments found. Standard input will be processed.\n");
    }
    process_treebank();
}



#==============================================================================
# We collect counts and examples of a large number of phenomena. This is an
# attempt to keep them all in one large hash.
#
# %stats
#   Absolute count of some sort of unit:
#     {nsent} ... number of sentences (trees) in the corpus
#     {ntok} .... number of tokens in the corpus
#     {ntoksano} ... number of tokens not followed by a space
#     {nfus} .... number of fused multi-word tokens in the corpus
#     {nword} ... number of syntactic words (nodes) in the corpus
#   Inventories of individual data items and their frequencies
#   (hashes: item => frequency):
#     {words} ... inventory of word forms
#     {fusions} ... inventory of multi-word token forms
#     {lemmas} ... inventory of lemmas
#     {tags} ... inventory of UPOS tags
#     {features} ... inventory of feature names
#     {fvpairs} ... inventory of feature-value pairs
#     {deprels} ... inventory of dependency relation labels
#   Examples of words that appeared with a particular property. Right now we
#   have just one huge hash but it might be useful to split it in the future
#   (hash: property => {exampleWord => frequency}):
#     {example}{tag} ... inventory of words that occurred with a particular tag
#   Combinations of annotation items and their frequencies
#   (hashes: item1 => item2 ... => frequency):
#     {fvt}{$fvpair}{$tag} ... feature-value pair with UPOS tag
#     {fvtverbform}{$fvpair}{$tag} ... feature-value pair with UPOS tag and VerbForm if nonempty
#     {tfv}{$tag}{$fvpair} ... UPOS tag with feature-value pair
#==============================================================================
sub reset_counters
{
    my $stats = shift;
    $stats->{nsent} = 0;
    $stats->{ntok} = 0;
    $stats->{ntoksano} = 0;
    $stats->{nfus} = 0;
    $stats->{nword} = 0;
    $stats->{words} = {};
    $stats->{fusions} = {};
    $stats->{lemmas} = {};
    $stats->{tags} = {};
    $stats->{features} = {};
    $stats->{fvpairs} = {};
    $stats->{deprels} = {};
    # example words and lemmas
    $stats->{examples} = {};
    # combinations
    $stats->{fvt} = {};
    $stats->{fvtverbform} = {};
    $stats->{tfv} = {};
}



#------------------------------------------------------------------------------
# Reads the standard input (simple stats) or all CoNLL-U files in one treebank
# (detailed stats) and analyzes them.
#------------------------------------------------------------------------------
sub process_treebank
{
    local %stats;
    reset_counters(\%stats);
    local @sentence;
    # Counters visible to the summarizing functions.
    local %tlw;
    local %wordtag;
    local %lemmatag;
    local %exentwt;
    local %exentlt;
    local %tfset;
    local %tfsetjoint;
    local %tf;
    local %ft;
    local %fw;
    local %fl;
    local %paradigm;
    local %fv;
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
            $stats{nsent}++;
            splice(@sentence);
        }
        # Lines with fused tokens do not contain features but we want to count the fusions.
        elsif(m/^(\d+)-(\d+)\t(\S+)/)
        {
            my $i0 = $1;
            my $i1 = $2;
            my $fusion = $3;
            my $size = $i1-$i0+1;
            $stats{ntok} -= $size-1;
            $stats{ntoksano}++ if(m/SpaceAfter=No/);
            $stats{nfus}++;
            # Remember the occurrence of the fusion.
            $stats{fusions}{$fusion}++ unless($fusion eq '_');
        }
        else
        {
            $stats{ntok}++;
            $stats{nword}++;
            # Get rid of the line break.
            s/\r?\n$//;
            # Split line into columns.
            # Since UD 2.0 the FORM and LEMMA may contain the space character,
            # hence we cannot split on /\s+/ but we must use /\t/ only!
            my @columns = split(/\t/, $_);
            push(@sentence, \@columns);
        }
    }
    # Process the last sentence even if it is not correctly terminated.
    if(@sentence)
    {
        print STDERR ("WARNING! The last sentence is not properly terminated by an empty line.\n");
        print STDERR ("         (An empty line means two consecutive LF characters, not just one!)\n");
        print STDERR ("         Counting the words from the bad sentence anyway.\n");
        process_sentence(@sentence);
        $stats{nsent}++;
        splice(@sentence);
    }
    prune_examples($stats{fusions});
    local @fusions = sort {my $r = $stats{fusions}{$b} <=> $stats{fusions}{$a}; unless($r) {$r = $a cmp $b}; $r} (keys(%{$stats{fusions}}));
    prune_examples($stats{words});
    local @words = sort {my $r = $stats{words}{$b} <=> $stats{words}{$a}; unless($r) {$r = $a cmp $b}; $r} (keys(%{$stats{words}}));
    prune_examples($stats{lemmas});
    local @lemmas = sort {my $r = $stats{lemmas}{$b} <=> $stats{lemmas}{$a}; unless($r) {$r = $a cmp $b}; $r} (keys(%{$stats{lemmas}}));
    # Sort the features alphabetically before printing them.
    local @tagset = sort(keys(%{$stats{tags}}));
    local @featureset = sort {lc($a) cmp lc($b)} (keys(%{$stats{features}}));
    local @fvset = sort {lc($a) cmp lc($b)} (keys(%{$stats{fvpairs}}));
    local @deprelset = sort(keys(%{$stats{deprels}}));
    # Examples may contain uppercase letters only if all-lowercase version does not exist.
    my @ltagset = map {$_.'-lemma'} (@tagset);
    foreach my $key (keys(%{$stats{examples}}))
    {
        my @examples = keys(%{$stats{examples}{$key}});
        foreach my $example (@examples)
        {
            if(lc($example) ne $example && exists($stats{examples}{$key}{lc($example)}))
            {
                $stats{examples}{$key}{lc($example)} += $stats{examples}{$key}{$example};
                delete($stats{examples}{$key}{$example});
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
    if($konfig{oformat} eq 'hub')
    {
        # The hub_statistics() function returns a list of MarkDown sections.
        print(join("\n", hub_statistics()));
    }
    elsif($konfig{oformat} eq 'hubcompare')
    {
        # Only collect a structured report and return it.
        # Multiple treebanks will be scanned and their reports combined by the caller.
        return hub_statistics();
    }
    elsif($konfig{oformat} eq 'detailed')
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
        $stats{ntoksano}++ if($node->[9] =~ m/SpaceAfter=No/);
        # Remember the occurrence of the word form (syntactic word).
        $stats{words}{$word}++ unless($word eq '_');
        # Remember the occurrence of the lemma.
        $stats{lemmas}{$lemma}++ unless($lemma eq '_');
        # Remember the occurrence of the universal POS tag.
        $stats{tags}{$tag}++;
        $tlw{$tag}{$lemma}{$word}++;
        # We can also print example forms and lemmas that had the tag.
        $stats{examples}{$tag}{$word}++;
        $stats{examples}{$tag.'-lemma'}{$lemma}++;
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
        $stats{examples}{$tagfeatures}{$word}++;
        # Skip if there are no features.
        my %features_found_here;
        unless($features eq '_')
        {
            my @features = split(/\|/, $features);
            my $tagverbform = $tag;
            my @verbforms = map {my $x = $_; $x =~ s/^VerbForm=//; $x} (grep {m/^VerbForm=/} (@features));
            if(scalar(@verbforms) > 0)
            {
                $tagverbform .= "-$verbforms[0]";
            }
            foreach my $fv (@features)
            {
                $stats{fvpairs}{$fv}++;
                # We can also list tags with which the feature occurred.
                $stats{fvt}{$fv}{$tag}++;
                $stats{fvtverbform}{$fv}{$tagverbform}++;
                $stats{tfv}{$tag}{$fv}++;
                # We can also print example words that had the feature.
                $stats{examples}{$fv}{$word}++;
                $stats{examples}{"$tag\t$fv"}{$word}++;
                $stats{examples}{"$tagverbform\t$fv"}{$word}++ if($tagverbform ne $tag);
                # Aggregate feature names over all values.
                my ($f, $v) = split(/=/, $fv);
                $stats{features}{$f}++;
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
                $stats{examples}{"$tag\t$f=EMPTY"}{$word}++;
            }
        }
        # Remember the occurrence of each dependency relation.
        $stats{deprels}{$deprel}++;
        $ltrdeprel{$deprel}++ if($head < $id);
        $deprellen{$deprel} += abs($id - $head);
        $tagdeprel{$tag}{$deprel}++;
        $stats{examples}{$deprel.'-lemma'}{$lemma}++;
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
        $ntokens_total += $stats{tags}{$tag};
        $ntypes{$tag} = scalar(keys(%{$stats{examples}{$tag}}));
        $ntypes_total += $ntypes{$tag};
        $nlemmas{$tag} = scalar(keys(%{$stats{examples}{$tag.'-lemma'}}));
        $nlemmas_total += $nlemmas{$tag};
    }
    local $flratio = $ntypes_total/$nlemmas_total;
    # Rank tags by number of lemmas, types and tokens.
    local %rtokens;
    local @tags = sort {$stats{tags}{$b} <=> $stats{tags}{$a}} (@tagset);
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
    my $ntokens = $stats{tags}{$tag};
    my $ptokens = percent($ntokens, $ntokens_total);
    my $ptypes = percent($ntypes{$tag}, $ntypes_total);
    my $plemmas = percent($nlemmas{$tag}, $nlemmas_total);
    $page .= "There are $nlemmas{$tag} `$tag` lemmas ($plemmas), $ntypes{$tag} `$tag` types ($ptypes) and $ntokens `$tag` tokens ($ptokens).\n";
    $page .= "Out of $ntags observed tags, the rank of `$tag` is: $rlemmas{$tag} in number of lemmas, $rtypes{$tag} in number of types and $rtokens{$tag} in number of tokens.\n\n";
    my $examples = prepare_examples($stats{examples}{$tag.'-lemma'}, $limit);
    $page .= "The $limit most frequent `$tag` lemmas: ".fex($examples)."\n\n";
    $examples = prepare_examples($stats{examples}{$tag}, $limit);
    $page .= "The $limit most frequent `$tag` types:  ".fex($examples)."\n\n";
    # Examples of ambiguous lemmas that can be this part of speech or at least one other part of speech.
    my @examples = grep {scalar(keys(%{$lemmatag{$_}})) > 1} (keys(%{$stats{examples}{$tag.'-lemma'}}));
    @examples = sort_and_truncate_examples($stats{examples}{$tag.'-lemma'}, \@examples, $limit);
    @examples = map {my $l = $_; my @t = map {"[$_]() $lemmatag{$l}{$_}"} (sort {$lemmatag{$l}{$b} <=> $lemmatag{$l}{$a}} (keys(%{$lemmatag{$l}}))); fex($l).' ('.join(', ', @t).')'} (@examples);
    $page .= "The $limit most frequent ambiguous lemmas: ".join(', ', @examples)."\n\n";
    # Examples of ambiguous types that can be this part of speech or at least one other part of speech.
    @examples = grep {scalar(keys(%{$wordtag{$_}})) > 1} (keys(%{$stats{examples}{$tag}}));
    @examples = sort_and_truncate_examples($stats{examples}{$tag}, \@examples, $limit);
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
        my ($list, $n) = list_keys_with_counts($tf{$tag}, $stats{tags}{$tag}, "$langcode-feat/");
        $page .= "`$tag` occurs with $n features: $list\n\n";
        my @featurepairs = map {"`$_`"} (sort(keys(%{$stats{tfv}{$tag}})));
        my $nfeaturepairs = scalar(@featurepairs);
        $page .= "`$tag` occurs with $nfeaturepairs feature-value pairs: ".join(', ', @featurepairs)."\n\n";
        my @featuresets = sort {$tfset{$tag}{$b} <=> $tfset{$tag}{$a}} (keys(%{$tfset{$tag}}));
        my $nfeaturesets = scalar(@featuresets);
        $examples = prepare_examples($stats{examples}{$tag."\t".$featuresets[0]}, $limit);
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
    my ($list, $n) = list_keys_with_counts($tagdeprel{$tag}, $stats{tags}{$tag}, "$langcode-dep/");
    $page .= "`$tag` nodes are attached to their parents using $n different relations: $list\n\n";
    ($list, $n) = list_keys_with_counts($parenttag{$tag}, $stats{tags}{$tag}, '');
    $page .= "Parents of `$tag` nodes belong to $n different parts of speech: $list\n\n";
    my $n0c = $tagdegree{$tag}{0} // 0;
    my $p0c = percent($n0c, $stats{tags}{$tag});
    $page .= "$n0c ($p0c) `$tag` nodes are leaves.\n\n";
    if($maxtagdegree{$tag} > 0)
    {
        my $n1c = $tagdegree{$tag}{1} // 0;
        my $p1c = percent($n1c, $stats{tags}{$tag});
        $page .= "$n1c ($p1c) `$tag` nodes have one child.\n\n";
        if($maxtagdegree{$tag} > 1)
        {
            my $n2c = $tagdegree{$tag}{2} // 0;
            my $p2c = percent($n2c, $stats{tags}{$tag});
            $page .= "$n2c ($p2c) `$tag` nodes have two children.\n\n";
            if($maxtagdegree{$tag} > 2)
            {
                my $n3c = $tagdegree{$tag}{3} // 0;
                my $p3c = percent($n3c, $stats{tags}{$tag});
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
    my $n = $stats{features}{$feature};
    my $p = percent($n, $stats{nword});
    $page .= "$n tokens ($p) have a non-empty value of `$feature`.\n";
    $n = scalar(keys($fw{$feature}));
    $p = percent($n, scalar(@words));
    $page .= "$n types ($p) occur at least once with a non-empty value of `$feature`.\n";
    $n = scalar(keys($fl{$feature}));
    $p = percent($n, scalar(@lemmas));
    $page .= "$n lemmas ($p) occur at least once with a non-empty value of `$feature`.\n";
    # List part-of-speech tags with which this feature occurs.
    my $list; ($list, $n) = list_keys_with_counts($ft{$feature}, $stats{nword}, "$langcode-pos/");
    $page .= "The feature is used with $n part-of-speech tags: $list.\n\n";
    my @tags = sort {$ft{$feature}{$b} <=> $ft{$feature}{$a}} (keys(%{$ft{$feature}}));
    foreach my $tag (@tags)
    {
        $page .= "### `$tag`\n\n";
        $n = $ft{$feature}{$tag};
        $p = percent($n, $stats{tags}{$tag});
        $page .= "$n [$langcode-pos/$tag]() tokens ($p of all `$tag` tokens) have a non-empty value of `$feature`.\n\n";
        # Is this feature used exclusively with some other feature?
        # We are interested in features that can be non-empty with the current tag in a significant percentage of cases.
        my @other_features = grep {$tf{$tag}{$_} / $stats{tags}{$tag} > 0.1} (keys(%{$tf{$tag}}));
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
        my @values = sort(map {s/^$feature=//; $_} (grep {m/^$feature=/} (keys(%{$stats{tfv}{$tag}}))));
        foreach my $value (@values)
        {
            $n = $stats{tfv}{$tag}{"$feature=$value"};
            $p = percent($n, $tf{$tag}{$feature});
            my $examples = prepare_examples($stats{examples}{"$tag\t$feature=$value"}, $limit);
            $page .= "* `$value` ($n; $p of non-empty `$feature`): ".fex($examples)."\n";
        }
        $n = $stats{tags}{$tag} - $ft{$feature}{$tag};
        my $examples = prepare_examples($stats{examples}{"$tag\t$feature=EMPTY"}, $limit);
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
    my $n = $stats{deprels}{$deprel};
    my $p = percent($n, $stats{nword});
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
    ($list, $n) = list_keys_with_counts($depreltags{$deprel}, $stats{deprels}{$deprel}, "$langcode-pos/");
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
    print("    <total><sentences>$stats{nsent}</sentences><tokens>$stats{ntok}</tokens><words>$stats{nword}</words><fused>$stats{nfus}</fused></total>\n");
    ###!!! We do not know what part of the data is for training, development or testing. We would have to change the calling syntax.
    #print("    <train></train>\n");
    #print("    <dev></dev>\n");
    #print("    <test></test>\n");
    print("  </size>\n");
    print('  <lemmas unique="', scalar(@lemmas), '" />');
    splice(@lemmas, 15);
    # XML comment must not contain '--' but some treebanks do. Replace it by ndash.
    my $ex = join(', ', @lemmas);
    $ex =~ s/--/\x{2013}/g;
    print("<!-- $ex -->\n");
    print('  <forms unique="', scalar(@words), '" />');
    splice(@words, 15);
    $ex = join(', ', @words);
    $ex =~ s/--/\x{2013}/g;
    print("<!-- $ex -->\n");
    print('  <fusions unique="', scalar(@fusions), '" />');
    splice(@fusions, 15);
    $ex = join(', ', @fusions);
    $ex =~ s/--/\x{2013}/g;
    print("<!-- $ex -->\n");
    # CoNLL 2017 shared task, surprise languages: I want to make some statistics public together with the language names
    # but I do not want to reveal the number of tokens in the test set (the participants have to do the tokenization themselves).
    # Therefore the POS tag statistics should not give absolute counts (number of tokens is a simple sum of the counts).
    print("  <!-- Statistics of universal POS tags. The comments show the most frequent lemmas. -->\n");
    print("  <tags unique=\"".scalar(@tagset)."\">\n");
    foreach my $tag (@tagset)
    {
        my @keys = keys(%{$stats{examples}{$tag.'-lemma'}});
        my @examples = sort_and_truncate_examples($stats{examples}{$tag.'-lemma'}, \@keys, 10);
        $ex = join(', ', @examples);
        $ex =~ s/--/\x{2013}/g;
        # Absolute or relative count?
        my $c = $stats{tags}{$tag};
        $c /= $stats{ntok} if($konfig{relative});
        print('    <tag name="'.$tag.'">'.$c."</tag><!-- $ex -->\n");
    }
    print("  </tags>\n");
    # Print the list of features as an XML structure that can be used in the treebank description XML file.
    print("  <!-- Statistics of features and values. The comments show the most frequent word forms. -->\n");
    print("  <feats unique=\"".scalar(@fvset)."\">\n");
    foreach my $feature (@fvset)
    {
        my @keys = keys(%{$stats{examples}{$feature}});
        my @examples = sort_and_truncate_examples($stats{examples}{$feature}, \@keys, 10);
        my $upostags = join(',', sort(keys(%{$stats{fvt}{$feature}})));
        my ($name, $value) = split(/=/, $feature);
        $ex = join(', ', @examples);
        $ex =~ s/--/\x{2013}/g;
        # Absolute or relative count?
        my $c = $stats{fvpairs}{$feature};
        $c /= $stats{ntok} if($konfig{relative});
        print('    <feat name="'.$name.'" value="'.$value.'" upos="'.$upostags.'">'.$c."</feat><!-- $ex -->\n");
    }
    print("  </feats>\n");
    # Print the list of dependency relations as an XML structure that can be used in the treebank description XML file.
    print("  <!-- Statistics of universal dependency relations. -->\n");
    print("  <deps unique=\"".scalar(@deprelset)."\">\n");
    foreach my $deprel (@deprelset)
    {
        # Absolute or relative count?
        my $c = $stats{deprels}{$deprel};
        $c /= $stats{ntok} if($konfig{relative});
        print('    <dep name="'.$deprel.'">'.$c."</dep>\n");
    }
    print("  </deps>\n");
    print("</treebank>\n");
}



#------------------------------------------------------------------------------
# Prints statistics of phenomena that should be mentioned at the language-
# specific documentation hub on Github.
#------------------------------------------------------------------------------
sub hub_statistics
{
    my @table;
    my $cell = '';
    # We have to generate HTML instead of MarkDown because the MarkDown syntax is not recognized inside HTML tables.
    $cell .= "<h2>Tokenization and Word Segmentation</h2>\n\n";
    $cell .= "<ul>\n";
    if($stats{nfus} == 0)
    {
        $cell .= "<li>This corpus contains $stats{nsent} sentences and $stats{ntok} tokens.</li>\n";
    }
    else
    {
        $cell .= "<li>This corpus contains $stats{nsent} sentences, $stats{ntok} tokens and $stats{nword} syntactic words.</li>\n";
    }
    if($stats{ntoksano} > 0)
    {
        my $percentage = $stats{ntoksano} / $stats{ntok} * 100;
        $cell .= sprintf("<li>This corpus contains $stats{ntoksano} tokens (%d%%) that are not followed by a space.</li>\n", $percentage+0.5);
    }
    # Words with spaces.
    my @words_with_spaces = sort(grep {m/\s/} keys(%{$stats{words}}));
    my $n_wws = scalar(@words_with_spaces);
    if($n_wws > 0)
    {
        $cell .= "<li>This corpus contains $n_wws types of words with spaces: ".join(', ', @words_with_spaces)."</li>\n";
    }
    else
    {
        $cell .= "<li>This corpus does not contain words with spaces.</li>\n";
    }
    # Words combining letters and punctuation.
    my @words_with_punctuation = sort(grep {m/\pP\pL|\pL\pP/} keys(%{$stats{words}}));
    my $n_wwp = scalar(@words_with_punctuation);
    if($n_wwp > 0)
    {
        $cell .= "<li>This corpus contains $n_wwp types of words that contain both letters and punctuation: ".join(', ', @words_with_punctuation)."</li>\n";
    }
    else
    {
        $cell .= "<li>This corpus does not contain words that contain both letters and punctuation.</li>\n";
    }
    # Multi-word tokens.
    if($stats{nfus} > 0)
    {
        my $avgsize = ($stats{nword} - $stats{ntok} + $stats{nfus}) / $stats{nfus};
        $cell .= sprintf("<li>This corpus contains $stats{nfus} multi-word tokens. On average, one multi-word token consists of %.2f syntactic words.</li>\n", $avgsize);
        my @fusion_examples = sort(keys(%{$stats{fusions}}));
        my $n_types_mwt = scalar(@fusion_examples);
        $cell .= "<li>There are $n_types_mwt types of multi-word tokens: ".join(', ', @fusion_examples).".</li>\n";
    }
    $cell .= "</ul>\n";
    push(@table, $cell);
    $cell = '';
    # Morphology and part-of-speech tags.
    $cell .= "<h2>Morphology</h2>\n\n";
    $cell .= "<ul>\n";
    my $n_tags_used = scalar(@tagset);
    $cell .= "<li>This corpus uses $n_tags_used UPOS tags out of 17 possible: ".join(', ', @tagset)."</li>\n";
    if($n_tags_used < 17)
    {
        my @unused_tags = grep {!exists($stats{tags}{$_})} ('NOUN', 'PROPN', 'PRON', 'ADJ', 'DET', 'NUM', 'VERB', 'AUX', 'ADV', 'ADP', 'SCONJ', 'CCONJ', 'PART', 'INTJ', 'SYM', 'PUNCT', 'X');
        $cell .= "<li>This corpus does not use the following tags: ".join(', ', @unused_tags)."</li>\n";
    }
    if(exists($stats{tags}{PART}))
    {
        my @part_examples = sort(keys(%{$stats{examples}{PART}}));
        my $n_types_part = scalar(@part_examples);
        $cell .= "<li>This corpus contains $n_types_part word types tagged as particles (PART): ".join(', ', @part_examples).".</li>\n";
    }
    # Verb forms.
    my @verbforms = sort(map {my $x = $_; $x =~ s/^VerbForm=//; $x} (grep {m/^VerbForm=/} (keys(%{$stats{fvpairs}}))));
    my $n_verbforms = scalar(@verbforms);
    if($n_verbforms > 0)
    {
        $cell .= "<li>There are $n_verbforms (de)verbal forms:\n";
        $cell .= "<ul>\n";
        foreach my $verbform (@verbforms)
        {
            my $fvpair = "VerbForm=$verbform";
            my @upostags = sort(keys(%{$stats{fvt}{$fvpair}}));
            $cell .= "  <li>$verbform\n";
            $cell .= "  <ul>\n";
            foreach my $upos (@upostags)
            {
                my @keys = keys(%{$stats{examples}{"$upos\t$fvpair"}});
                my @examples = sort_and_truncate_examples($stats{examples}{"$upos\t$fvpair"}, \@keys, 10);
                $cell .= "    <li>$upos: ".join(', ', @examples)."</li>\n";
            }
            $cell .= "  </ul>\n";
            $cell .= "  </li>\n";
        }
        $cell .= "</ul>\n";
        $cell .= "</li>\n";
    }
    else
    {
        $cell .= "<li>This corpus does not use the VerbForm feature.</li>\n";
    }
    push(@table, $cell);
    $cell = '';
    $cell .= "<h3>Nominal Features</h3>\n\n";
    foreach my $feature (qw(Gender Animacy Number Case PrepCase Definite))
    {
        $cell .= summarize_feature_for_hub($feature);
        push(@table, $cell);
        $cell = '';
    }
    $cell .= "<h3>Degree and Polarity</h3>\n\n";
    foreach my $feature (qw(Degree Polarity Variant))
    {
        $cell .= summarize_feature_for_hub($feature);
        push(@table, $cell);
        $cell = '';
    }
    $cell .= "<h3>Verbal Features</h3>\n\n";
    foreach my $feature (qw(Aspect Mood Tense Voice Evident))
    {
        $cell .= summarize_feature_for_hub($feature);
        push(@table, $cell);
        $cell = '';
    }
    $cell .= "<h3>Pronouns, Determiners, Quantifiers</h3>\n\n";
    foreach my $feature ('PronType', 'NumType', 'Poss', 'Reflex', 'Person', 'Polite', 'Gender[psor]', 'Number[psor]')
    {
        $cell .= summarize_feature_for_hub($feature);
        push(@table, $cell);
        $cell = '';
    }
    $cell .= "<h3>Other Features</h3>\n\n";
    my @otherfeatures = grep {!m/^(Gender|Animacy|Number|Case|PrepCase|Definite|Degree|Polarity|Variant|VerbForm|Mood|Aspect|Tense|Voice|Evident|PronType|NumType|Poss|Reflex|Person|Polite|Gender\[psor\]|Number\[psor\]|)$/} (@featureset);
    foreach my $feature (@otherfeatures)
    {
        $cell .= summarize_feature_for_hub($feature);
    }
    push(@table, $cell);
    # Syntax.
    $cell = '';
    $cell .= "<h2>Syntax</h2>\n\n";
    $cell .= "<h3>Auxiliary Verbs and Copula</h3>\n\n";
    $cell .= "<ul>\n";
    if(exists($stats{deprels}{cop}))
    {
        my @cop_lemmas = sort(keys(%{$stats{examples}{'cop-lemma'}}));
        my $n_lemmas_cop = scalar(@cop_lemmas);
        $cell .= "<li>This corpus uses $n_lemmas_cop lemmas as copulas (cop): ".join(', ', @cop_lemmas).".</li>\n";
    }
    else
    {
        $cell .= "<li>This corpus does not contain copulas.</li>\n";
    }
    if(exists($stats{deprels}{aux}))
    {
        my @aux_lemmas = sort(keys(%{$stats{examples}{'aux-lemma'}}));
        my $n_lemmas_aux = scalar(@aux_lemmas);
        $cell .= "<li>This corpus uses $n_lemmas_aux lemmas as auxiliaries (aux): ".join(', ', @aux_lemmas).".</li>\n";
    }
    if(exists($stats{deprels}{'aux:pass'}))
    {
        my @aux_lemmas = sort(keys(%{$stats{examples}{'aux:pass-lemma'}}));
        my $n_lemmas_aux = scalar(@aux_lemmas);
        $cell .= "<li>This corpus uses $n_lemmas_aux lemmas as passive auxiliaries (aux:pass): ".join(', ', @aux_lemmas).".</li>\n";
    }
    if(!exists($stats{deprels}{aux}) && !exists($stats{deprels}{'aux:pass'}))
    {
        $cell .= "<li>This corpus does not contain auxiliaries.</li>\n";
    }
    $cell .= "</ul>\n";
    push(@table, $cell);
    $cell = '';
    $cell .= "<h3>Core Arguments, Oblique Arguments and Adjuncts</h3>\n\n";
    $cell .= "TBD\n";
    push(@table, $cell);
    $cell = '';
    $cell .= "<h3>Relations Overview</h3>\n\n";
    $cell .= "<ul>\n";
    my @deprel_subtypes = grep {m/:/} (@deprelset);
    my %supertypes;
    foreach my $deprel (@deprel_subtypes)
    {
        $deprel =~ m/^(.+?):/;
        $supertypes{$1}++;
    }
    my $n_deprel_subtypes = scalar(@deprel_subtypes);
    if($n_deprel_subtypes > 0)
    {
        $cell .= "<li>This corpus uses $n_deprel_subtypes relation subtypes: ".join(', ', @deprel_subtypes)."</li>\n";
        # Are there main types that only occur as part of subtypes?
        my @supertypes = sort(grep {!exists($stats{deprels}{$_})} (keys(%supertypes)));
        my $n = scalar(@supertypes);
        if($n > 0)
        {
            $cell .= "<li>The following $n main types are not used alone, they are always subtyped: ".join(', ', @supertypes)."</li>\n";
        }
    }
    else
    {
        $cell .= "<li>This corpus does not use relation subtypes.</li>\n";
    }
    my @udeprels = qw(nsubj obj iobj csubj ccomp xcomp obl vocative expl dislocated advcl advmod discourse aux cop mark nmod appos nummod acl amod det clf case conj cc fixed flat compound list parataxis orphan goeswith reparandum punct root dep);
    my @unused = grep {!exists($stats{deprels}{$_}) && !exists($supertypes{$_})} (@udeprels);
    my $n_unused = scalar(@unused);
    if($n_unused > 0)
    {
        $cell .= "<li>The following $n_unused relation types are not used in this corpus at all: ".join(', ', @unused)."</li>\n";
    }
    $cell .= "</ul>\n";
    push(@table, $cell);
    # Return the list of cells to the caller. They may want to combine it with reports on other treebanks before printing it.
    return @table;
}
sub summarize_feature_for_hub
{
    my $feature = shift; # only feature name
    my $markdown = '';
    my @values = sort(map {my $x = $_; $x =~ s/^\Q$feature=//; $x} (grep {m/^\Q$feature=/} (keys(%{$stats{fvpairs}}))));
    my $n_values = scalar(@values);
    if($n_values > 0)
    {
        $markdown .= "<li>$feature\n";
        $markdown .= "  <ul>\n";
        foreach my $value (@values)
        {
            my $fvpair = "$feature=$value";
            my @upostags = sort(keys(%{$stats{fvtverbform}{$fvpair}}));
            $markdown .= "    <li>$value\n";
            $markdown .= "      <ul>\n";
            foreach my $upos (@upostags)
            {
                my @keys = keys(%{$stats{examples}{"$upos\t$fvpair"}});
                my @examples = sort_and_truncate_examples($stats{examples}{"$upos\t$fvpair"}, \@keys, 10);
                $markdown .= "        <li>$upos: ".join(', ', @examples)."</li>\n";
            }
            $markdown .= "      </ul>\n";
            $markdown .= "    </li>\n";
        }
        $markdown .= "  </ul>\n";
        $markdown .= "</li>\n";
    }
    return $markdown;
}
