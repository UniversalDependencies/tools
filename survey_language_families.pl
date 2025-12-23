#!/usr/bin/env perl
# Reads all UD treebanks in the UD folder, counts regular nodes (i.e. syntactic
# words/tokens) in all of them. Skips treebanks that do not contain the under-
# lying texts. Prints the counts grouped by language family.
# Copyright © 2023 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
use udlib;

sub usage
{
    print STDERR ("Usage: $0 --udpath /data/udreleases/2.12 --langyaml /data/ud/docs-automation/codes_and_flags.yaml\n");
    print STDERR ("Usage: $0 --input release --udpath /net/data/universal-dependencies-2.17 --output tbkstats > tbkstats.2.17.txt\n");
    print STDERR ("Usage: $0 --input tbkstats --output famstats|fampie < tbkstats.2.17.txt\n");
    print STDERR ("Usage: for i in 1.0 1.1 1.2 1.3 1.4 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 2.10 2.11 2.12 2.13 2.14 2.15 2.16 2.17 ; do survey_language_families.pl --input tbkstats --output fampie --relid $i < tbkstats.$i.txt ; done > log.tex\n");
}

#my $udpath = 'C:/Users/zeman/Documents/lingvistika-projekty/ud-repos';
my $udpath = '/net/data/universal-dependencies-2.12';
my $langyamlpath = '/net/work/people/zeman/unidep/docs-automation/codes_and_flags.yaml';
my $input = 'release'; # release: read directly the UD treebanks; tbkstats: read the statistics saved after reading the release previously (to be read from STDIN or file given as argument)
my $output = 'tbkstats'; # tbkstats: write treebank stats as tsv (to speed up later analysis); famstats: write family/genus/languages/words stats as several tables; fampie: latex pie chart
my $families = 0; # survey language families
my $genera_of_family; # survey genera of given family
my $languages = 0; # count languages per group
my $words = 0; # count words per group
my $relid; # release id to put to headers when printing output
GetOptions
(
    'udpath=s'   => \$udpath,
    'langyaml=s' => \$langyamlpath,
    'input=s'    => \$input,
    'output=s'   => \$output,
    'families'   => \$families,
    'genera=s'   => \$genera_of_family,
    'languages'  => \$languages,
    'words'      => \$words,
    'relid=s'    => \$relid
);
$families = 1 if(!$families && !$genera_of_family);
$words = 1 if(!$languages && !$words);
my $relidheader = $relid ? " in UD $relid" : '';

my @treebank_data;
if($input eq 'tbkstats')
{
    @treebank_data = read_treebank_data();
}
else
{
    my $languages = udlib::get_language_hash($langyamlpath);
    @treebank_data = read_release($udpath, $languages);
}
if($output eq 'tbkstats')
{
    print_treebank_data(@treebank_data);
}
else
{
    my ($nlanguages, $nwords, $family_languages, $iegenus_languages, $family_words, $iegenus_words) = compute_famstats(@treebank_data);
    if($output eq 'fampie')
    {
        # Print the pie charts with family/genus/languages/words proportions.
        if(0)
        {
            if($families && $languages)
            {
                print(get_family_piechart($family_languages));
            }
            if($genera_of_family && $languages)
            {
                print(get_family_piechart($iegenus_languages));
            }
            if($families && $words)
            {
                print(get_family_piechart($family_words));
            }
            if($genera_of_family && $words)
            {
                print(get_family_piechart($iegenus_words));
            }
        }
        else
        {
            ###!!! Temporarily hardcoded: Regardless of command line options, loop over all UD releases on the ÚFAL network.
            my $table = <<EOF
\\begin{tabular}{lcccccc}
\\Huge\\bf UD & \\Huge\\bf Languages & \\Huge\\bf Words & \\Huge\\bf Languages in IE & \\Huge\\bf Words in IE & \\Huge\\bf Languages in Url & \\Huge\\bf Words in Url \\\\\\midrule
EOF
            ;
            #foreach my $release ('1.0', '1.1', '1.2', '1.3', '1.4', '2.0', '2.1', '2.2', '2.3', '2.4', '2.5', '2.6', '2.7', '2.8', '2.9', '2.10', '2.11', '2.12', '2.13', '2.14', '2.15', '2.16', '2.17')
            foreach my $release ('1.0', '1.2', '1.4', '2.0', '2.3', '2.6', '2.9', '2.12', '2.15', '2.17')
            {
                @ARGV = ("tbkstats.$release.txt");
                my @treebank_data = read_treebank_data();
                my ($nlanguages, $nwords, $family_languages, $iegenus_languages, $family_words, $iegenus_words) = compute_famstats(@treebank_data);
                my ($aagenus_languages, $aagenus_words) = compute_genstats('Uralic', @treebank_data);
                my $pie1 = get_family_piechart($family_languages);
                my $pie2 = get_family_piechart($family_words);
                my $pie3 = get_family_piechart($iegenus_languages);
                my $pie4 = get_family_piechart($iegenus_words);
                my $pie5 = get_family_piechart($aagenus_languages);
                my $pie6 = get_family_piechart($aagenus_words);
                $table .= "\\Huge\\bf \\raisebox{7ex}{$release} & $pie1 & $pie2 & $pie3 & $pie4 & $pie5 & $pie6 \\\\\n";
            }
            $table .= "\\end{tabular}\n";
            print(get_latex_standalone($table));
        }
    }
    else
    {
        # Print the language statistics.
        if($families && $languages)
        {
            print("Number of languages per family\n");
            print_family_statistics($family_languages);
            print("\n");
        }
        if($genera_of_family && $languages)
        {
            print("Number of languages per Indo-European genus\n");
            print_family_statistics($iegenus_languages);
            print("\n");
        }
        # Print the word statistics.
        if($families && $words)
        {
            print("Number of words per language family\n");
            print_family_statistics($family_words);
            print("\n");
        }
        if($genera_of_family && $words)
        {
            print("Number of words per Indo-European genus\n");
            print_family_statistics($iegenus_words);
        }
    }
}



#------------------------------------------------------------------------------
# Prints family/genus statistics as a tsv table. Takes a hash where the keys
# are names of language families (or genera), and values are numbers of
# languages (or words) within that family/genus.
#------------------------------------------------------------------------------
sub print_family_statistics
{
    my $stats = shift; # hash reference
    my @sorted_keys = sort
    {
        my $r = $stats->{$b} <=> $stats->{$a};
        unless($r)
        {
            $r = $a cmp $b;
        }
        $r
    }
    (keys(%{$stats}));
    my $n = 0;
    foreach my $key (@sorted_keys)
    {
        $n += $stats->{$key};
    }
    foreach my $key (@sorted_keys)
    {
        printf("%s\t%d\t%d %%\n", $key, $stats->{$key}, $stats->{$key}/$n*100+0.5);
    }
}



#------------------------------------------------------------------------------
# Prints family/genus statistics as a pie chart (source for LaTeX/pgfplot).
# Takes a hash where the keys are names of language families (or genera), and
# values are numbers of languages (or words) within that family/genus.
#------------------------------------------------------------------------------
sub get_family_piechart
{
    my $stats = shift; # hash reference
    my @sorted_keys = sort
    {
        my $r = $stats->{$b} <=> $stats->{$a};
        unless($r)
        {
            $r = $a cmp $b;
        }
        $r
    }
    (keys(%{$stats}));
    # Get the sum of the values.
    my $n = 0;
    foreach my $key (@sorted_keys)
    {
        $n += $stats->{$key};
    }
    # Compute the percentages. Cut off at a predefined threshold; anything
    # smaller will be included in "Other".
    my @cutoff_keys;
    my %cutoff_stats;
    my $threshold = 0.018;
    my $percent_sum = 0;
    my $use_other = 0;
    my $other_key;
    foreach my $key (@sorted_keys)
    {
        my $share = $stats->{$key}/$n;
        my $rounded = sprintf("%d", $share*100+0.5);
        if($share >= $threshold)
        {
            push(@cutoff_keys, $key);
            $cutoff_stats{$key} = $rounded;
            $percent_sum += $rounded;
        }
        else
        {
            $use_other++;
            $other_key = $key;
        }
    }
    # If there were too small families, the remaining percentage will be labeled
    # as "Other". This could happen also due to rounding errors.
    # If there is only one category that would fall into "Other", keep its name
    # even if it is smaller than the threshold.
    if($percent_sum < 100)
    {
        if($use_other > 1)
        {
            push(@cutoff_keys, 'Other');
            $cutoff_stats{Other} = 100-$percent_sum;
        }
        elsif($use_other)
        {
            push(@cutoff_keys, $other_key);
            $cutoff_stats{$other_key} = 100-$percent_sum;
        }
        # If there is no "Other" category, distribute the extra mass to the largest categories.
        else
        {
            for(my $i = 0; $i < 100-$percent_sum; $i++)
            {
                $cutoff_stats{$cutoff_keys[$i]}++;
            }
        }
    }
    # However, rounding errors could also lead to overflow, in which case we will
    # penalize the largest categories.
    elsif($percent_sum > 100)
    {
        for(my $i = 0; $i < $percent_sum-100; $i++)
        {
            $cutoff_stats{$cutoff_keys[$i]}--;
        }
    }
    # If there are no data for the piechart, return empty string, not empty piechart (on which LaTeX would choke up).
    return '' if(scalar(@cutoff_keys) == 0);
    my $famcolor =
    {
        'Indo-European'  => 'blue!60',
        'Afro-Asiatic'   => 'orange!60',
        'Uralic'         => 'teal!60',
        'Tupian'         => 'yellow!40',
        'Turkic'         => 'red!60',
        'Austronesian'   => 'green!60!teal',
        'Niger-Congo'    => 'brown',
        'Sino-Tibetan'   => 'magenta!60',
        'Dravidian'      => 'cyan!60',
        'Austro-Asiatic' => 'red!60!orange',
        'Japanese'       => 'yellow!20',
        'Korean'         => 'cyan!20',
        'Basque'         => 'black!60',
        'Code switching' => 'black!20',
        'Sign Language'  => 'black!20',
        'Other'          => 'black!10',
        # Indo-European genera
        'Slavic'         => 'red!60',
        'Baltic'         => 'magenta!60',
        'Germanic'       => 'blue!60',
        'Romance'        => 'orange!60',
        'Celtic'         => 'green!60!teal',
        'Italic'         => 'yellow!40',
        'Greek'          => 'cyan!60',
        'Iranian'        => 'teal!60',
        'Indic'          => 'yellow!20',
        'Armenian'       => 'red!60!orange',
        'Albanian'       => 'brown',
        'Anatolian'      => 'black!60',
        # Uralic genera
        'Sami'           => 'orange!60',
        'Finnic'         => 'teal!60',
        'Mordvin'        => 'green!60!teal',
        'Permic'         => 'blue!60',
        'Samoyedic'      => 'yellow!40',
        'Ugric'          => 'red!60',
        # Afro-Asiatic genera
        'Semitic'        => 'teal!60',
        'Egyptian'       => 'red!60',
        'West Chadic'    => 'orange!60',
        'Cushitic'       => 'cyan!60',
    };
    my $color = join(', ', map {$famcolor->{$_}} (@cutoff_keys));
    my $pie = '';
    $pie .= "    \\begin{tikzpicture}\n";
    $pie .= "      \\pie[rotate=45, color={$color}, scale font]{\n";
    $pie .= join(",\n", map {sprintf("        %d/$_", $cutoff_stats{$_})} (@cutoff_keys))."\n";
    $pie .= "      }\n";
    $pie .= "    \\end{tikzpicture}";
    return $pie;
}



#------------------------------------------------------------------------------
# Given treebank data collected on a UD release, computes statistics of the
# number of languages and words per family or Indo-European genus.
#------------------------------------------------------------------------------
sub compute_famstats
{
    my @treebank_data = @_;
    my %family_languages;
    my %iegenus_languages;
    my %family_words;
    my %iegenus_words;
    my $nwords = 0;
    foreach my $treebank (@treebank_data)
    {
        $family_languages{$treebank->{family}}{$treebank->{language}}++;
        $family_words{$treebank->{family}} += $treebank->{stats}{nword};
        if($treebank->{family} eq 'Indo-European')
        {
            $iegenus_languages{$treebank->{genus}}{$treebank->{language}}++;
            $iegenus_words{$treebank->{genus}} += $treebank->{stats}{nword};
        }
        $nwords += $treebank->{stats}{nword};
    }
    # Recompute the language hashes to only remember the number of languages, not folders per language.
    my $nlanguages = 0;
    foreach my $f (keys(%family_languages))
    {
        $family_languages{$f} = scalar(keys(%{$family_languages{$f}}));
        $nlanguages += $family_languages{$f};
    }
    foreach my $g (keys(%iegenus_languages))
    {
        $iegenus_languages{$g} = scalar(keys(%{$iegenus_languages{$g}}));
    }
    return ($nlanguages, $nwords, \%family_languages, \%iegenus_languages, \%family_words, \%iegenus_words);
}



#------------------------------------------------------------------------------
# Given treebank data collected on a UD release, computes statistics of the
# number of languages and words per genus in a particular family.
#------------------------------------------------------------------------------
sub compute_genstats
{
    my $family = shift;
    my @treebank_data = @_;
    my %genus_languages;
    my %genus_words;
    foreach my $treebank (@treebank_data)
    {
        next if($treebank->{family} ne $family);
        $genus_languages{$treebank->{genus}}{$treebank->{language}}++;
        $genus_words{$treebank->{genus}} += $treebank->{stats}{nword};
    }
    # Recompute the language hashes to only remember the number of languages, not folders per language.
    foreach my $g (keys(%genus_languages))
    {
        $genus_languages{$g} = scalar(keys(%{$genus_languages{$g}}));
    }
    return (\%genus_languages, \%genus_words);
}



#------------------------------------------------------------------------------
# Collects statistics about a UD release (found in the given path). Returns a
# list of hashes, each hash describing one treebank. Treebanks of unknown
# languages and treebanks without the underlying text are ignored.
#------------------------------------------------------------------------------
sub read_release
{
    my $udpath = shift;
    my $languages = shift;
    my @folders = udlib::list_ud_folders($udpath);
    # UD r1.0 used language codes as folder names, unlike all subsequent releases.
    # Make sure that we can read it, too.
    my $r10names = 0;
    my $r10translation = {'cs' => 'UD_Czech', 'de' => 'UD_German', 'en' => 'UD_English', 'es' => 'UD_Spanish', 'fi' => 'UD_Finnish', 'fr' => 'UD_French', 'ga' => 'UD_Irish', 'hu' => 'UD_Hungarian', 'it' => 'UD_Italian', 'sv' => 'UD_Swedish'};
    if($udpath =~ m/1\.0/ && scalar(@folders) == 0)
    {
        opendir(DIR, $udpath) or die("Cannot read the contents of '$udpath': $!");
        @folders = sort(grep {-d "$udpath/$_" && m/^[a-z]+$/} (readdir(DIR)));
        closedir(DIR);
        $r10names = 1;
    }
    my $n = scalar(@folders);
    print STDERR ("Reading UD release from $udpath ($n treebank folders)...\n");
    my @treebank_data;
    foreach my $folder (@folders)
    {
        my $normalized_folder = $r10names && exists($r10translation->{$folder}) ? $r10translation->{$folder} : $folder;
        my ($language, $treebank) = udlib::decompose_repo_name($normalized_folder);
        if(!exists($languages->{$language}))
        {
            ###!!! This will fail on some treebanks in older UD releases because
            ###!!! some languages were later renamed:
            ###!!! Kurmanji => Northern Kurdish, Old Russian => Old East Slavic, Swiss German => Alemannic
            print STDERR ("Skipping $folder because language $language is unknown.\n");
            next;
        }
        my $metadata = udlib::read_readme($folder, $udpath);
        # Avoid 'no' but do not require 'yes' because old releases did not have this metadata field.
        if($metadata->{'Includes text'} =~ m/^n/i)
        {
            print STDERR ("Skipping $folder because it lacks underlying text.\n");
            next;
        }
        print STDERR ("Reading $folder...\n");
        my $ltcode = udlib::get_ltcode_from_repo_name($normalized_folder, $languages);
        my $stats = udlib::collect_statistics_about_ud_treebank("$udpath/$folder", $ltcode);
        my $family = $languages->{$language}{family};
        $family = 'Indo-European' if($family eq 'IE');
        my $genus = $languages->{$language}{genus};
        my $record =
        {
            'folder'   => $folder,
            'family'   => $family,
            'genus'    => $genus,
            'language' => $language,
            'treebank' => $treebank,
            'ltcode'   => $ltcode,
            'stats'    => $stats
        };
        push(@treebank_data, $record);
    }
    return @treebank_data;
}



#------------------------------------------------------------------------------
# Prints the statistics about a release as tab-separated values. This may be
# useful if we want to analyze the data later, as it saves us reading the
# complete treebanks every time (which may take considerable time).
#------------------------------------------------------------------------------
sub print_treebank_data
{
    my @treebank_data = @_;
    foreach my $t (@treebank_data)
    {
        print("$t->{folder}\t$t->{family}\t$t->{genus}\t$t->{language}\t$t->{treebank}\t$t->{ltcode}\t$t->{stats}{nword}\n");
    }
}



#------------------------------------------------------------------------------
# Reads the tab-separated values previously written by print_treebank_data().
#------------------------------------------------------------------------------
sub read_treebank_data
{
    my @treebank_data;
    while(<>)
    {
        chomp;
        my @f = split(/\t/);
        my $record =
        {
            'folder'   => $f[0],
            'family'   => $f[1],
            'genus'    => $f[2],
            'language' => $f[3],
            'treebank' => $f[4],
            'ltcode'   => $f[5],
            'stats'    => {'nword' => $f[6]}
        };
        push(@treebank_data, $record);
    }
    return @treebank_data;
}



#------------------------------------------------------------------------------
# Takes the body of a LaTeX document, wraps it in standalone preamble + begin
# and end{document}, returns the result.
#------------------------------------------------------------------------------
sub get_latex_standalone()
{
    my $document = shift;
    my $latex = <<EOF
\\documentclass{standalone}  % produce a document exactly as big as needed for the figure (or other contents) inside
\\usepackage{booktabs} % toprule, midrule, bottomrule
\\usepackage{tikz}
\\usepackage{pgf-pie} % draw pie charts using tikz
\\begin{document}
$document
\\end{document}
EOF
    ;
    return $latex;
}
