# Common Perl functions to manipulate UD repositories.
# Copyright © 2016 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

package udlib;

use Carp;
use JSON::Parse 'json_file_to_perl';
use YAML qw(LoadFile);
use utf8;



#------------------------------------------------------------------------------
# Reads the YAML file with information about languages from the repository
# docs-automation. Returns a reference to a hash indexed by the English names
# of the languages, with sub-fields 'flag', 'lcode', 'family'.
#------------------------------------------------------------------------------
sub get_language_hash
{
    my $path = shift;
    $path = 'docs-automation/codes_and_flags.yaml' if(!defined($path));
    return LoadFile($path);
}



#------------------------------------------------------------------------------
# Takes a name of a UD treebank repository, e.g., UD_Ancient_Greek-PROIEL.
# Decomposes it into language name and treebank name and returns the two
# strings. If language name contains underscores, they are replaced by spaces
# (it looks better in reports and it is also the required name form to access
# language information read from YAML by get_language_hash()).
#------------------------------------------------------------------------------
sub decompose_repo_name
{
    my $repo = shift;
    $repo =~ s:/$::;
    my $language;
    my $treebank;
    # Example: UD_Ancient_Greek-PROIEL
    if($repo =~ m/^UD_([A-Za-z_]+)(?:-([A-Za-z]+))?$/)
    {
        $language = $1;
        $treebank = $2;
        $language =~ s/_/ /g;
    }
    return ($language, $treebank);
}



#------------------------------------------------------------------------------
# Returns reference to hash of known UD treebank codes (key = treebank name,
# without the UD_ prefix but with underscores instead of spaces; value =
# language_treebank code). Reads the JSON file in the docs repository.
# Takes the path to the main UD folder (contains docs as subfolder). Default: .
#------------------------------------------------------------------------------
sub get_ltcode_hash
{
    my $path = shift;
    print STDERR ("WARNING: udlib::get_ltcode_hash() is obsolete because the file lcodes.json in docs is no longer maintained!\n");
    print STDERR ("WARNING: Use udlib::get_language_hash() instead, which reads docs-automation/codes_and_flags.yaml.\n");
    $path = '.' if(!defined($path));
    if (-d "$path/docs")
    {
        $path .= '/docs';
    }
    my $lcodes;
    if (-f "$path/gen_index/lcodes.json")
    {
        $lcodes = json_file_to_perl("$path/gen_index/lcodes.json");
        # For example:
        # $lcodes->{'Finnish-FTB'} eq 'fi_ftb'
    }
    die("Cannot find or read $path/docs/gen_index/lcodes.json") if (!defined($lcodes));
    return $lcodes;
}



#------------------------------------------------------------------------------
# Same as get_ltcode_hash() but collects only language names/codes, without the
# optional treebank identifier.
#------------------------------------------------------------------------------
sub get_lcode_hash
{
    my $path = shift;
    my $ltcodes = get_ltcode_hash($path);
    my %lcodes;
    foreach my $key (keys(%{$ltcodes}))
    {
        my $lkey = $key;
        my $lcode = $ltcodes->{$lkey};
        # Remove treebank name/code if any. Keep only language name/code.
        $lkey =~ s/-.*//;
        $lcode =~ s/_.*//;
        if(!exists($lcodes{$lkey}))
        {
            $lcodes{$lkey} = $lcode;
        }
        # Sanity check: all treebanks with one language name should use the same language code.
        else
        {
            if($lcodes{$lkey} ne $lcode)
            {
                die("Code conflict for language '$lkey': old code '$lcodes{$lkey}', new code '$lcode'");
            }
        }
    }
    return \%lcodes;
}



#------------------------------------------------------------------------------
# Returns list of UD_* folders in a given folder. Default: the current folder.
#------------------------------------------------------------------------------
sub list_ud_folders
{
    my $path = shift;
    $path = '.' if(!defined($path));
    opendir(DIR, $path) or die("Cannot read the contents of '$path': $!");
    my @folders = sort(grep {-d "$path/$_" && m/^UD_.+/} (readdir(DIR)));
    closedir(DIR);
    return @folders;
}



#------------------------------------------------------------------------------
# Scans a UD folder for CoNLL-U files. Uses the file names to guess the
# language code.
#------------------------------------------------------------------------------
sub get_ud_files_and_codes
{
    my $udfolder = shift; # e.g. "UD_Czech"; not the full path
    my $path = shift; # path to the superordinate folder; default: the current folder
    $path = '.' if(!defined($path));
    my $name;
    my $langname;
    my $tbkext;
    if($udfolder =~ m/^UD_(([^-]+)(?:-(.+))?)$/)
    {
        $name = $1;
        $langname = $2;
        $tbkext = $3;
        $langname =~ s/_/ /g;
    }
    else
    {
        print STDERR ("WARNING: Unexpected folder name '$udfolder'\n");
    }
    # Look for training, development or test data.
    my $section = 'any'; # training|development|test|any
    my %section_re =
    (
        # Training data in big treebanks is split into multiple files.
        'training'    => 'train(-[a-z])?(-[0-9])?',
        'development' => 'dev',
        'test'        => 'test',
        'any'         => '(train(-[a-z])?(-[0-9])?|dev|test)'
    );
    opendir(DIR, "$path/$udfolder") or die("Cannot read the contents of '$path/$udfolder': $!");
    my @files = sort(grep {-f "$path/$udfolder/$_" && m/.+-ud-$section_re{$section}\.conllu$/} (readdir(DIR)));
    closedir(DIR);
    my $n = scalar(@files);
    my $code;
    my $lcode;
    my $tcode;
    if($n>0)
    {
        if($n>1 && $section ne 'any')
        {
            print STDERR ("WARNING: Folder '$path/$udfolder' contains multiple ($n) files that look like $section data.\n");
        }
        $files[0] =~ m/^(.+)-ud-$section_re{$section}\.conllu$/;
        $lcode = $code = $1;
        if($code =~ m/^([^_]+)_(.+)$/)
        {
            $lcode = $1;
            $tcode = $2;
        }
    }
    my %record =
    (
        'folder' => $udfolder,
        'name'   => $name,
        'lname'  => $langname,
        'tname'  => $tbkext,
        'code'   => $code,
        'ltcode' => $code, # for compatibility with some tools, this code is provided both as 'code' and as 'ltcode'
        'lcode'  => $lcode,
        'tcode'  => $tcode,
        'files'  => \@files,
        $section => $files[0]
    );
    #print STDERR ("$udfolder\tlname $langname\ttname $tbkext\tcode $code\tlcode $lcode\ttcode $tcode\t$section $files[0]\n");
    return \%record;
}



#------------------------------------------------------------------------------
# Reads the README file of a treebank and finds the metadata lines. Example:
#=== Machine-readable metadata (DO NOT REMOVE!) ================================
#Data available since: UD v1.0
#License: CC BY-NC-SA 3.0
#Includes text: yes
#Genre: news
#Lemmas: converted from manual
#UPOS: converted from manual
#XPOS: manual native
#Features: converted from manual
#Relations: converted from manual
#Contributors: Zeman, Daniel; Hajič, Jan
#Contributing: elsewhere
#Contact: zeman@ufal.mff.cuni.cz
#===============================================================================
#------------------------------------------------------------------------------
sub read_readme
{
    my $folder = shift;
    my $path = shift; # path to the superordinate folder; default: the current folder
    $path = '.' if(!defined($path));
    my $filename = (-f "$path/$folder/README.txt") ? "$path/$folder/README.txt" : "$path/$folder/README.md";
    open(README, $filename) or return undef;
    binmode(README, ':utf8');
    my %metadata;
    my @attributes = ('Data available since', 'License', 'Genre', 'Contributors',
        'Includes text', 'Lemmas', 'UPOS', 'XPOS', 'Features', 'Relations', 'Contributing', 'Contact');
    my $attributes_re = join('|', @attributes);
    my $current_section_heading = '';
    my $current_section_text = '';
    while(<README>)
    {
        # Remove leading and trailing whitespace characters.
        s/\r?\n$//;
        s/^\s+//;
        s/\s+$//;
        s/\s+/ /g;
        # Is this a top-level section heading?
        # Note: We regard the machine-readable metadata as a section of its own; it does not have a proper heading but starts with "===".
        if(m/^\#([^\#]+|$)/ || m/^===\s*(.*?)\s*=+/)
        {
            my $heading = lc($1);
            $heading =~ s/^\s+//;
            $heading =~ s/\s+$//;
            # Collapse "acknowledgments" and "acknowledgements", both are correct.
            $heading =~ s/acknowledge?ments?/acknowledgments/;
            # Save the previous section before starting a new one.
            if($current_section_heading ne '' && $current_section_text ne '')
            {
                # Metadata may be enclosed in <pre>...</pre> in order to improve the rendering on Github.
                # However, that could mean that <pre> is now the last line of the last section.
                # If we keep it there and copy it to a web page, it will ruin all subsequent formatting.
                $current_section_text =~ s/\s*<pre>\s*$/\n/is;
                $metadata{sections}{$current_section_heading} = $current_section_text;
            }
            # Clear the buffer for the next section.
            $current_section_heading = $heading;
            $current_section_text = '';
        }
        # We do not include the heading line in the text of the section, but we do include everything else, including empty lines.
        else
        {
            $current_section_text .= "$_\n";
        }
        if(m/^($attributes_re):\s*(.*)$/i)
        {
            my $attribute = $1;
            my $value = $2;
            $value = '' if(!defined($value));
            if(exists($metadata{$attribute}))
            {
                print(`pwd`) if($folder !~ m/^UD_/);
                print("WARNING: Repeated definition of '$attribute' in $folder/$filename\n");
            }
            $metadata{$attribute} = $value;
            # Make it easier to check the number of the first release (we need to know whether this dataset is planned for future and shall be excluded now).
            if($attribute eq 'Data available since')
            {
                if($metadata{$attribute} =~ m/^UD\s*v?(\d+\.\d+)$/i)
                {
                    $metadata{'firstrelease'} = $1;
                }
            }
        }
        elsif(m/change\s*log/i)
        {
            $metadata{'changelog'} = 1;
        }
    }
    # The last section should be the metadata, which we do not need saved as section.
    # But if the README does not follow the guidelines, a previous section may not
    # be terminated properly and we have to save it now.
    if($current_section_heading ne '' && $current_section_text ne '')
    {
        # Metadata may be enclosed in <pre>...</pre> in order to improve the rendering on Github.
        # However, that could mean that <pre> is now the last line of the last section.
        # If we keep it there and copy it to a web page, it will ruin all subsequent formatting.
        $current_section_text =~ s/\s*<pre>\s*$/\n/is;
        $metadata{sections}{$current_section_heading} = $current_section_text;
    }
    close(README);
    return \%metadata;
}



#------------------------------------------------------------------------------
# Generates a human-readable information about a treebank, based on README and
# data, intended for the UD web (i.e. using MarkDown syntax).
#------------------------------------------------------------------------------
sub generate_markdown_treebank_overview
{
    my $folder = shift;
    # We need to know the number of the latest release in order to generate the links to search engines.
    my $release = shift;
    if($release !~ m/^\d+\.\d+$/)
    {
        # Let's be mean and throw an exception. We do not want to generate docs
        # pages with wrong or empty release numbers in links.
        confess("Unrecognized UD release number '$release'.");
    }
    my $crelease = $release;
    $crelease =~ s/\.//;
    my $treebank_name = $folder;
    $treebank_name =~ s/[-_]/ /g;
    my $language_name = $folder;
    $language_name =~ s/^UD_//;
    $language_name =~ s/-.*//;
    $language_name =~ s/_/ /g;
    my $filescan = get_ud_files_and_codes($folder);
    my $metadata = read_readme($folder);
    my $md = "\# $treebank_name\n\n";
    if(!defined($metadata))
    {
        $md .= "<b>ERROR:</b> Cannot read the README file: $!";
        return $md;
    }
    # Language-specific documentation, e.g. for Polish: http://universaldependencies.org/pl/index.html
    $md .= "Language: [$language_name](/$filescan->{lcode}/index.html) (code: `$filescan->{lcode}`)";
    my $language_data = get_language_hash(); # we could supply path to the yaml file; but let the function try the default path now
    if(defined($language_data) && exists($language_data->{$language_name}{family}))
    {
        my $family = $language_data->{$language_name}{family};
        $family =~ s/^IE,/Indo-European,/;
        $md .= "<br/>\nFamily: $family";
    }
    $md .= "\n\n";
    $md .= "This treebank has been part of Universal Dependencies since the $metadata->{'Data available since'} release.\n\n";
    $md .= "The following people have contributed to making this treebank part of UD: ";
    $md .= join(', ', map {my $x = $_; if($x =~ m/^(.+),\s*(.+)$/) {$x = "$2 $1"} $x} (split(/\s*;\s*/, $metadata->{Contributors})));
    $md .= ".\n\n";
    $md .= "Repository: [$folder](https://github.com/UniversalDependencies/$folder)<br />\n";
    $md .= "Search this treebank on-line: [PML-TQ](https://lindat.mff.cuni.cz/services/pmltq/\#!/treebank/ud$filescan->{code}$crelease)<br />\n";
    $md .= "Download all treebanks: [UD $release](/#download)\n\n";
    $md .= "License: $metadata->{License}";
    $md .= ". The underlying text is not included; the user must obtain it separately and then merge with the UD annotation using a script distributed with UD" if($metadata->{'Includes text'} eq 'no');
    $md .= "\n\n";
    $md .= "Genre: ";
    $md .= join(', ', split(/\s+/, $metadata->{Genre}));
    $md .= "\n\n";
    my $scrambled_email = $metadata->{Contact};
    $scrambled_email =~ s/\@/&nbsp;(æt)&nbsp;/g;
    $scrambled_email =~ s/\./&nbsp;•&nbsp;/g;
    $md .= "Questions, comments?\n";
    $md .= "General annotation questions (either $language_name-specific or cross-linguistic) can be raised in the [main UD issue tracker](https://github.com/UniversalDependencies/docs/issues).\n";
    $md .= "You can report bugs in this treebank in the [treebank-specific issue tracker on Github](https://github.com/UniversalDependencies/$folder/issues).\n";
    $md .= "If you want to collaborate, please contact [$scrambled_email].\n";
    if($metadata->{Contributing} eq 'here')
    {
        $md .= "Development of the treebank happens directly in the UD repository, so you may submit bug fixes as pull requests against the dev branch.\n";
    }
    elsif($metadata->{Contributing} eq 'here source')
    {
        $md .= "Development of the treebank happens in the UD repository but not directly in the final CoNLL-U files.\n";
        $md .= "You may submit bug fixes as pull requests against the dev branch but you have to go to the folder called `not-to-release` and locate the source files there.\n";
        $md .= "Contact the treebank maintainers if in doubt.\n";
    }
    elsif($metadata->{Contributing} eq 'elsewhere')
    {
        $md .= "Development of the treebank happens outside the UD repository.\n";
        $md .= "If there are bugs, either the original data source or the conversion procedure must be fixed.\n";
        $md .= "Do not submit pull requests against the UD repository.\n";
    }
    elsif($metadata->{Contributing} eq 'to be adopted')
    {
        $md .= "The UD version of this treebank currently does not have a maintainer.\n";
        $md .= "If you know the language and want to help, please consider adopting the treebank.\n";
    }
    $md .= "\n";
    $md .= "| Annotation | Source |\n";
    $md .= "|------------|--------|\n";
    foreach my $annotation (qw(Lemmas UPOS XPOS Features Relations))
    {
        $md .= "| $annotation | ";
        if($metadata->{$annotation} eq 'manual native')
        {
            $md .= "annotated manually";
            # It probably does not make sense to speak about "UD style" lemmatization.
            # And it would be definitely wrong with XPOS.
            unless($annotation =~ m/^(Lemmas|XPOS)$/)
            {
                $md .= ", natively in UD style";
            }
            $md .= " |\n";
        }
        elsif($metadata->{$annotation} eq 'converted from manual')
        {
            $md .= "annotated manually in non-UD style, automatically converted to UD |\n";
        }
        elsif($metadata->{$annotation} eq 'converted with corrections')
        {
            $md .= "annotated manually in non-UD style, automatically converted to UD, with some manual corrections of the conversion |\n";
        }
        elsif($metadata->{$annotation} eq 'automatic')
        {
            $md .= "assigned by a program, not checked manually |\n";
        }
        elsif($metadata->{$annotation} eq 'automatic with corrections')
        {
            $md .= "assigned by a program, with some manual corrections, but not a full manual verification |\n";
        }
        elsif($metadata->{$annotation} eq 'not available')
        {
            $md .= "not available |\n";
        }
        elsif($metadata->{$annotation} =~ m/\w/)
        {
            $md .= "(unrecognized value: \"$metadata->{$annotation}\") |\n";
        }
        else
        {
            $md .= "(undocumented) |\n";
        }
    }
    $md .= "\n";
    $md .= "\#\# Description\n".$metadata->{sections}{summary};
    $md .= "\n".$metadata->{sections}{introduction};
    $md .= "\#\# Acknowledgments\n".$metadata->{sections}{acknowledgments};
    return $md;
}



#------------------------------------------------------------------------------
# Reads a CoNLL-U file and collects statistics about features.
#------------------------------------------------------------------------------
sub collect_features_from_conllu_file
{
    my $file = shift; # relative or full path
    my $hash = shift; # ref to hash where the statistics are collected
    my $key = shift; # identification of the current dataset in the hash (e.g. language code)
    open(FILE, $file) or die("Cannot read $file: $!");
    while(<FILE>)
    {
        if(m/^\d+\t/)
        {
            chomp();
            my @fields = split(/\t/, $_);
            my $features = $fields[5];
            unless($features eq '_')
            {
                my @features = split(/\|/, $features);
                foreach my $feature (@features)
                {
                    my ($f, $vv) = split(/=/, $feature);
                    # There may be several values delimited by commas.
                    my @values = split(/,/, $vv);
                    foreach my $v (@values)
                    {
                        $hash->{$f}{$v}{$key}++;
                        $hash->{$f}{$v}{TOTAL}++;
                    }
                }
            }
        }
    }
    return $hash;
}



#------------------------------------------------------------------------------
# Reads all CoNLL-U files in a folder and collects statistics about features.
#------------------------------------------------------------------------------
sub collect_features_from_ud_folder
{
    my $udfolder = shift; # relative or full path
    my $hash = shift; # ref to hash where the statistics are collected
    my $key = shift; # identification of the current dataset in the hash (e.g. language code)
    opendir(DIR, $udfolder) or die("Cannot read the contents of '$udfolder': $!");
    my @files = sort(grep {-f "$udfolder/$_" && m/.+\.conllu$/} (readdir(DIR)));
    closedir(DIR);
    foreach my $file (@files)
    {
        collect_features_from_conllu_file("$udfolder/$file", $hash, $key);
    }
}



#------------------------------------------------------------------------------
# Finds all UD subfolders in the current folder, scans them for CoNLL-U files,
# reads these files and collects statistics about feature values in them.
#------------------------------------------------------------------------------
sub scan
{
    my @folders = list_ud_folders();
    my %hash;
    foreach my $folder (@folders)
    {
        my $record = get_ud_files_and_codes($folder);
        # Skip folders without data.
        next if(!defined($record->{lcode}));
        collect_features_from_ud_folder($folder, \%hash, $record->{lcode});
    }
    ###!!! Temporary debugging. List languages that use VerbForm=Ger.
    my %gerhash = %{$hash{VerbForm}{Ger}};
    my @keys = sort(grep {$gerhash{$_}>0} (keys(%gerhash)));
    print STDERR ("VerbForm=Ger\t", join(' ', map {"$_($gerhash{$_})"} (@keys)), "\n");
}



1;
