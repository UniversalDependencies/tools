#!/usr/bin/env perl
# Reads a PROIEL treebank and prints the Bible references it contains.
# Copyright © 2025 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

sub usage
{
    print STDERR ("Usage: $0 file1.conllu [file2.conllu ...]\n");
    # perl tools\survey_bible_sentences.pl UD_Ancient_Hebrew-PTNK\hbo_ptnk-ud-train.conllu UD_Ancient_Hebrew-PTNK\hbo_ptnk-ud-dev.conllu UD_Ancient_Hebrew-PTNK\hbo_ptnk-ud-test.conllu UD_Ancient_Greek-PTNK\grc_ptnk-ud-train.conllu UD_Ancient_Greek-PTNK\grc_ptnk-ud-dev.conllu UD_Ancient_Greek-PTNK\grc_ptnk-ud-test.conllu UD_Ancient_Greek-PROIEL\grc_proiel-ud-train.conllu UD_Ancient_Greek-PROIEL\grc_proiel-ud-dev.conllu UD_Ancient_Greek-PROIEL\grc_proiel-ud-test.conllu UD_Latin-PROIEL\la_proiel-ud-train.conllu UD_Latin-PROIEL\la_proiel-ud-dev.conllu UD_Latin-PROIEL\la_proiel-ud-test.conllu UD_Gothic-PROIEL\got_proiel-ud-train.conllu UD_Gothic-PROIEL\got_proiel-ud-dev.conllu UD_Gothic-PROIEL\got_proiel-ud-test.conllu UD_Old_Church_Slavonic-PROIEL\cu_proiel-ud-train.conllu UD_Old_Church_Slavonic-PROIEL\cu_proiel-ud-dev.conllu UD_Old_Church_Slavonic-PROIEL\cu_proiel-ud-test.conllu UD_Classical_Armenian-CAVaL\xcl_caval-ud-train.conllu UD_Classical_Armenian-CAVaL\xcl_caval-ud-dev.conllu UD_Classical_Armenian-CAVaL\xcl_caval-ud-test.conllu UD_Coptic-Scriptorium\cop_scriptorium-ud-train.conllu UD_Coptic-Scriptorium\cop_scriptorium-ud-dev.conllu UD_Coptic-Scriptorium\cop_scriptorium-ud-test.conllu UD_Coptic-Bohairic\cop_bohairic-ud-train.conllu UD_Coptic-Bohairic\cop_bohairic-ud-dev.conllu UD_Coptic-Bohairic\cop_bohairic-ud-test.conllu UD_Faroese-FarPaHC\fo_farpahc-ud-train.conllu UD_Faroese-FarPaHC\fo_farpahc-ud-dev.conllu UD_Faroese-FarPaHC\fo_farpahc-ud-test.conllu UD_Icelandic-IcePaHC\is_icepahc-ud-train.conllu UD_Icelandic-IcePaHC\is_icepahc-ud-dev.conllu UD_Icelandic-IcePaHC\is_icepahc-ud-test.conllu UD_Romanian-Nonstandard\ro_nonstandard-ud-train.conllu UD_Romanian-Nonstandard\ro_nonstandard-ud-dev.conllu UD_Romanian-Nonstandard\ro_nonstandard-ud-test.conllu UD_Yoruba-YTB\yo_ytb-ud-test.conllu > bible.txt
}

my @files = @ARGV;
if(scalar(@files) == 0)
{
    usage();
    die("No file name arguments found");
}
# The labels used to refer to Bible books should be ideally standardized across UD.
# The labels in this list are derived from the standard at https://guide.unwsp.edu/c.php?g=1321431&p=9721744
# (but they are uppercased and inner spaces are removed). The order of the books also follows the same source.
# See also https://github.com/UniversalDependencies/tools/commit/fa9f43cf76ab223775485e45bd466fec2b46ea9c#commitcomment-157312840
my @bible_books = qw(GEN EXOD LEV NUM DEUT JOSH JUDG RUTH 1SAM 2SAM 1KGS 2KGS 1CHR 2CHR EZRA NEH ESTH JOB PS PROV ECCL SONG ISA JER LAM EZEK DAN HOS JOEL AMOS OBAD JONAH MIC NAH HAB ZEPH HAG ZECH MAL
                     TOB JDT ADDESTH WIS SIR BAR EPJER ADDDAN PRAZAR SGTHREE SUS BEL 1MACC 2MACC 1ESD PRMAN PS151 3MACC 2ESD 4MACC
                     MATT MARK LUKE JOHN ACTS ROM 1COR 2COR GAL EPH PHIL COL 1THESS 2THESS 1TIM 2TIM TITUS PHLM HEB JAS 1PET 2PET 1JOHN 2JOHN 3JOHN JUDE REV);
# Some datasets use the full names or alternative abbreviations of the books.
my %bible_book_names =
(
    'Genesis'        => 'GEN',
    'Exodus'         => 'EXOD',
    'EXO'            => 'EXOD',
    'Leviticus'      => 'LEV',
    'Ruth'           => 'RUTH',
    'RUT'            => 'RUTH',
    '1KGDMS'         => '1SAM', # Septuagint joins Samuel and Kings into Kingdoms
    '2KGDMS'         => '2SAM', # Septuagint joins Samuel and Kings into Kingdoms
    '3KGDMS'         => '1KGS', # Septuagint joins Samuel and Kings into Kingdoms
    '4KGDMS'         => '2KGS', # Septuagint joins Samuel and Kings into Kingdoms
    'PSALM'          => 'PS',
    'PSALMS'         => 'PS',
    'PSS'            => 'PS',
    'QOH'            => 'ECCL',
    'CANT'           => 'SONG',
    'Habakkuk'       => 'HAB',
    'JUDIT'          => 'JDT',
    'MARC'           => 'MARK',
    'LUCA'           => 'LUKE',
    'IOAN'           => 'JOHN',
    'PAVEL_ROM'      => 'ROM',
    'PAVEL_1.CORINT' => '1COR',
    'PAVEL_2.CORINT' => '2COR',
    'PAVEL_GALAT'    => 'GAL',
    'PAVEL_EFES'     => 'EPH',
    'PAVEL_FILIP'    => 'PHIL',
    'PAVEL_COLAS'    => 'COL',
    'PAVEL_SOLUN.1'  => '1THESS',
    'PAVEL_SOLUN.2'  => '2THESS',
    'PAVEL_TIM.1'    => '1TIM',
    'PAVEL_TIM.2'    => '2TIM',
    'TIT'            => 'TITUS',
    'PAVEL_TIT'      => 'TITUS',
    'PHILEM'         => 'PHLM',
    'PAVEL_FILIMON'  => 'PHLM',
    'PAVEL_EVREI'    => 'HEB',
    'IACOB'          => 'JAS',
    'PETRU.1'        => '1PET',
    'PETRU.2'        => '2PET',
    'IOAN.1'         => '1JOHN',
    'IOAN.2'         => '2JOHN',
    'IOAN.3'         => '3JOHN',
    'IUDA'           => 'JUDE',
    'IOAN_APOC'      => 'REV'
);
my %bible_ord;
for(my $i = 0; $i <= $#bible_books; $i++)
{
    $bible_ord{$bible_books[$i]} = $i;
}
my @sentences;
foreach my $file (@files)
{
    my $file_without_path = $file;
    $file_without_path =~ s:^.*/::;
    $file_without_path =~ s:^.*\\::;
    $file_without_path =~ s:\.conllu$::;
    my $current_source;
    my $current_sent_id;
    my $current_text;
    my %refs;
    open(my $fh, $file) or die("Cannot read '$file': $!");
    while(<$fh>)
    {
        s/\r?\n$//;
        if(m/^\#\s*(?:source|citation-part)\s*=\s*(.+)$/)
        {
            $current_source = $1;
        }
        elsif(m/^\#\s*sent_id\s*=\s*(.+)$/)
        {
            $current_sent_id = $1;
        }
        elsif(m/^\#\s*text\s*=\s*(.+)$/)
        {
            $current_text = $1;
        }
        elsif(m/^[0-9]+\t/)
        {
            my @f = split(/\t/, $_);
            my @misc = split(/\|/, $f[9]);
            foreach my $m (@misc)
            {
                if($m =~ m/^ref=(.+)$/i)
                {
                    my $r = $1;
                    # Fix typo in ro_nonstandard.
                    $r = 'MATT6.33.content' if($r eq '6.33.content');
                    $refs{$r}++;
                }
            }
        }
        elsif(m/^\s*$/)
        {
            unless($current_source =~ m/^(Histories|Opus|Epistulae|Commentarii|De officiis|Kiev|Psalterium|Codex Suprasliensis)/ ||
                   $current_sent_id =~ m/^(MX.Hist|06Khor1)/ || # Classical Armenian
                   $current_sent_id =~ m/^(bohairic_)?(apophthegmata|besa|martyrdom|shenoute|life|dormition|proclus|pseudo|lausiac)/ || # Coptic
                   $current_sent_id =~ m/\.(NAR-SAG|NAR-REL|REL-OTH|REL-SER|NAR-FIC|SCI-LIN|REL-SAG|BIO-TRA|LAW-LAW|NAR-HIS|BIO-AUT|BIO-OTH|SCI-NAT),/ || # Icelandic
                   $file =~ m/ro_nonstandard/ && (!defined($current_source) || $current_source =~ m/^(title|pred|No|PART|ANAFORA|COMPLETARE|N?NEAMUL|CREZ|FIGURA|PRED|PAVEL_PRED|PCREZ|[0-9])/) || # Romanian
                   $current_sent_id =~ m/^wiki/) # Yoruba
            {
                # xcl_caval has no source comment and no ref attributes in MISC.
                # Its sentence ids are the Bible refs, possibly extended by 'a', 'b', etc.
                my @refs = sort(keys(%refs));
                if(scalar(@refs) == 0)
                {
                    if($current_sent_id =~ m/^([A-Z0-9]+)_([0-9]+)\.([0-9]+)[a-z]*(?:-[0-9]+[a-z]*)?$/)
                    {
                        $refs[0] = $1.'_'.$2.'.'.$3;
                    }
                    # grc_ptnk and hbo_ptnk also have the information in sentence ids
                    # but they do not use the abbreviations of the book names.
                    elsif($current_sent_id =~ m/^(Masoretic|Septuagint)-([A-Za-z]+)-([0-9]+):([0-9]+)(?:-[0-9]+)?-(hbo|grc)$/ && exists($bible_book_names{$2}))
                    {
                        $refs[0] = $bible_book_names{$2}.'_'.$3.'.'.$4;
                    }
                    # cop_scriptorium also has the information in sentence ids.
                    # It uses a different encoding from the above.
                    elsif($current_sent_id =~ m/^(?:sahidica?|bohairic)_(1corinthians|mark|ruth|habakkuk)-(?:bohairic_)?(1Cor|Mark|Ruth|Habakkuk)_([0-9]+)_s([0-9]+)$/)
                    {
                        my $book = exists($bible_book_names{$2}) ? $bible_book_names{$2} : uc($2);
                        $refs[0] = $book.'_'.($3*1).'.'.($4*1);
                    }
                    # fo_farpahc and is_icepahc also have the information in sentence ids
                    # and they also use their own encoding.
                    elsif($current_sent_id =~ m/^[0-9]+\.(?:NT)?(JOHN|ACTS|JUDIT)\.REL-BIB,\.?([0-9]+)(?:\.[0-9]+)?(?:-dev|-test)?$/)
                    {
                        $refs[0] = $1.'_1.'.$2;
                    }
                }
                my ($ref_book, $ref_index) = split(/_/, $refs[0]);
                my ($ref_book, $ref_index) = split_book_ref($refs[0], \%bible_book_names);
                # The book reference may have been changed to standard; project that back to the full reference string.
                $refs[0] = $ref_book.'_'.$ref_index;
                if($ref_index =~ m/^[0-9]/)
                {
                    my ($ref_chapter, $ref_verse) = split_chapter_ref($ref_index);
                    my %sentence =
                    (
                        'refs'        => join(',', @refs),
                        'ref_book'    => $ref_book,
                        'ref_chapter' => $ref_chapter,
                        'ref_verse'   => $ref_verse,
                        'source'      => $current_source,
                        'file'        => $file_without_path,
                        'sent_id'     => $current_sent_id,
                        'text'        => $current_text
                    );
                    push(@sentences, \%sentence);
                }
            }
            $current_source = undef;
            $current_sent_id = undef;
            $current_text = undef;
            %refs = ();
        }
    }
    close($fh);
}
# Sort the sentences across languages to see the parallel ones.
@sentences = sort
{
    my $r = $bible_ord{$a->{ref_book}} <=> $bible_ord{$b->{ref_book}};
    unless($r)
    {
        $r = $a->{ref_chapter} <=> $b->{ref_chapter};
        unless($r)
        {
            $r = $a->{ref_verse} <=> $b->{ref_verse};
            unless($r)
            {
                $r = $a->{file} cmp $b->{file};
                unless($r)
                {
                    $r = $a->{sent_id} cmp $b->{sent_id};
                }
            }
        }
    }
    $r
}
(@sentences);
foreach my $s (@sentences)
{
    my $shortsource = substr($s->{source}, 0, 20);
    print("$s->{refs}\t$shortsource\t$s->{file}\t$s->{sent_id}\t$s->{text}\n");
}



#------------------------------------------------------------------------------
# Takes a Bible reference and splits it to book label and the rest (index of
# the verse inside the book). Attempts to account for various formats in which
# the references appear in treebanks.
#------------------------------------------------------------------------------
sub split_book_ref
{
    my $reference = shift;
    my $bible_book_names = shift; # reference to relabeling hash
    my $book;
    my $rest;
    if($reference =~ m/^(PSALM|PAVEL_(?:ROM|COLAS))\.(.+)$/)
    {
        $book = $1;
        $rest = $2;
    }
    elsif($reference =~ m/^(PAVEL_(?:SOLUN|TIM)\.[12]|IOAN_APOC)_(.+)$/)
    {
        $book = $1;
        $rest = $2;
    }
    elsif($reference =~ m/^(PAVEL_(?:[12]\.)?[A-Z]+|PETRU\.[12]|IOAN\.[123])_(.+)$/)
    {
        $book = $1;
        $rest = $2;
    }
    elsif($reference =~ m/^([0-9]*[A-Z]+)_?(.+)$/)
    {
        $book = $1;
        $rest = $2;
    }
    if(exists($bible_book_names->{$book}))
    {
        $book = $bible_book_names->{$book};
    }
    return ($book, $rest);
}



#------------------------------------------------------------------------------
# Takes a Bible verse reference (after stripping the book label) and splits it
# to chapter number and the rest (index of the verse inside the chapter,
# possibly multiple verses or specification of a part of the verse). Attempts
# to account for various formats in which the references appear in treebanks.
#------------------------------------------------------------------------------
sub split_chapter_ref
{
    my $reference = shift;
    my $chapter;
    my $rest;
    if($reference =~ m/^([0-9]+)[:\.](.+)$/)
    {
        $chapter = $1*1;
        $rest = $2;
    }
    else
    {
        $chapter = $reference;
    }
    return ($chapter, $rest);
}
