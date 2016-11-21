# Common Perl functions to manipulate UD repositories.
# Copyright © 2016 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

package udlib;



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
    my $section = 'training'; # training|development|test
    my %section_re =
    (
        # Training data in UD_Czech are split to four files.
        'training'    => 'train(-[clmv])?',
        'development' => 'dev',
        'test'        => 'test'
    );
    opendir(DIR, "$path/$udfolder") or die("Cannot read the contents of '$path/$udfolder': $!");
    my @files = sort(grep {-f "$path/$udfolder/$_" && m/.+-ud-$section_re{$section}\.conllu$/} (readdir(DIR)));
    closedir(DIR);
    my $n = scalar(@files);
    my $code;
    my $lcode;
    my $tcode;
    if($n==0)
    {
        print STDERR ("WARNING: No $section data found in '$path/$udfolder'\n");
    }
    else
    {
        if($n>1)
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
        'lcode'  => $lcode,
        'tcode'  => $tcode,
        $section => $files[0]
    );
    print STDERR ("$udfolder\tlname $langname\ttname $tbkext\tcode $code\tlcode $lcode\ttcode $tcode\t$section $files[0]\n");
    return \%record;
}



#------------------------------------------------------------------------------
# Reads the README file of a treebank and finds the metadata lines. Example:
#=== Machine-readable metadata ================================================
#Documentation status: partial
#Data source: automatic
#Data available since: UD v1.2
#License: CC BY-NC-SA 2.5
#Genre: fiction
#Contributors: Celano, Giuseppe G. A.; Zeman, Daniel
#==============================================================================
#------------------------------------------------------------------------------
sub read_readme
{
    my $folder = shift;
    my $filename = (-f "$folder/README.txt") ? "$folder/README.txt" : "$folder/README.md";
    open(README, $filename) or return;
    binmode(README, ':utf8');
    my %metadata;
    my @attributes = ('Documentation status', 'Data source', 'Data available since', 'License', 'Genre', 'Contributors');
    my $attributes_re = join('|', @attributes);
    while(<README>)
    {
        s/\r?\n$//;
        s/^\s+//;
        s/\s+$//;
        s/\s+/ /g;
        if(m/^($attributes_re):\s*(.*)$/i)
        {
            my $attribute = $1;
            my $value = $2;
            $value = '' if(!defined($value));
            if(exists($metadata{$attribute}))
            {
                print("WARNING: Repeated definition of '$attribute' in $folder/$filename\n");
            }
            $metadata{$attribute} = $value;
            if($attribute eq 'Data available since')
            {
                if($metadata{$attribute} =~ m/^UD v1\.(\d)$/ && $1 <= 3)
                {
                    $metadata{'release'} = 1;
                }
            }
        }
        elsif(m/change\s*log/i)
        {
            $metadata{'changelog'} = 1;
        }
    }
    close(README);
    return \%metadata;
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
