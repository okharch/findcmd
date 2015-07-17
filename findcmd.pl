#!/usr/bin/env perl
# findcmd.pl - quick find command using fuzzy patterns

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Text::Soundex;

my $path_for_scripts = "$ENV{HOME}/bin";
my $max_script_size = 1024;
my $help = 0;
my $soundex_weight = 10; # score assigned to soundex hit
my $regex_weight = 20; # score assigned to regex hit 
my $line_weight = 1; # score assigned to line of cmd regex hit 
my %line; # location where particular alias/function is defined. is initialized in process_start_file

#http://www.linuxfromscratch.org/blfs/view/svn/postlfs/profile.html
my $start_files = join ":",map "$ENV{HOME}/$_",qw(.bashrc .profile .bash_profile);

## Parse options and print usage if there is a syntax error,
## or if usage was explicitly requested.
GetOptions(
    'help|?' => \$help, 
    'start_files=s',\$start_files,
    'soundex_weight=i' => \$soundex_weight,
    'line_weight=i' => \$line_weight,
    'regex_weight=i' => \$regex_weight,
    'path_for_scripts=s' => \$path_for_scripts,
    'max_script_size=i' => \$max_script_size,
);
my %path_for_scripts = map {$_ => undef} split /:/, $path_for_scripts;

my $cmd_info = rebuild_cmd_info();

pod2usage(1) if $help;
#pod2usage(-verbose => 2) if $man;
pod2usage("$0: please specify any sample(s) to find") unless @ARGV;

local $\ = local $, = "\n";


my (%hits);
# add soundex hits
my $arg_count = @ARGV;
for my $arg_pos (0..$#ARGV) {
    my $value = ($arg_count - $arg_pos) * $soundex_weight;
    my $arg_soundex = soundex($ARGV[$arg_pos]);
    # add soundex match command hits
    $hits{$_} += $value for @{$cmd_info->{soundex}{$arg_soundex}||[]};
}

# process start file
my @start_files = split /:/, $start_files;
process_start_file(@start_files);

$cmd_info = $cmd_info->{plain};

for my $type (qw(alias function bin)) {
    my $cmds = $cmd_info->{$type};
    my @cmd_name = keys %$cmds;
    for my $arg_pos (0..$#ARGV) {
        my $value = ($arg_count - $arg_pos) * $regex_weight;
        my $re = $ARGV[$arg_pos];
        # add regex match hits
        $hits{"$type:$_"} += $value for grep m{$re}, @cmd_name;
    }
    next unless $line_weight;
    # add regex matches on lines (content) of the command
    for my $cmd_name (grep $cmds->{$_}, @cmd_name) {
        my $lines = $cmds->{$cmd_name};
        die "$cmd_name no lines" unless ref($lines);
        for my $arg_pos (0..$#ARGV) {
            my $re = $ARGV[$arg_pos];
            my $value = ($arg_count - $arg_pos) * $line_weight;
           $hits{"$type:$cmd_name"} += $value for grep m{$re}, @$lines;
        }
    }
}

print "$_".(exists $line{$_}?" $line{$_}":"") for sort {$hits{$a} <=> $hits{$b}} keys %hits;

sub rebuild_cmd_info {
    my %plain = (
        'function' => build_function(),
        'alias' => build_alias(),
        'bin' => build_bin(),
    );
    # build soundex
    my %soundex;
    if ($soundex_weight) {
        for my $type (qw(function alias bin)) {
            push @{$soundex{$_->[1]}},"$type:$_->[0]" for grep defined($_->[1]), map [$_,soundex($_)], keys %{$plain{$type}};
        }
    }
    return {soundex => \%soundex, plain => \%plain};
}

sub build_function {
    my @functions = `/bin/bash --login -c "typeset -f"`;
    my %functions;
    my ($function,@lines);
    for (@functions) {
        chomp;
        if (m{^(\S+) \(\)}) { # this starts new function definition
            $functions{$function} = \@lines if $function;
            @lines = ();
            $function = $1;
            next;
        }
        s/^\s+//;
        push @lines,$_  unless m{^[{}]$}; # don't put to lines "{" and "}"
    }
    $functions{$function} = @lines?\@lines:undef if $function;
    return \%functions;
}

sub build_alias {
    return {map { m{^alias (.*?)=(.*?)\s*$} ? ($1 => [$2]) : () } `/bin/bash --login -c "alias"`};
}

sub ls_bin {
    my (%bin,$current_path);
    my $PATH = join " ",map qq{"$_"}, split /:/, $ENV{PATH}; 
    #print STDERR $PATH;exit;
    open my $ls, "-|", "ls -l --time-style=+%s $PATH";
    while (<$ls>) {
        chomp;
        my ($path) = m{^(.*?):\s*$};
        if ($path) {
            $current_path = $path;
            next;
        }
        my ($type,$size,$timestamp,$name) = m{^(.).*?\s(\d+)\s+(\d+)\s+(.*)};
        next unless $name;
        # collect timestamp only for small scripts from $path_for_scripts
        $bin{"$current_path/$name"} = !exists($path_for_scripts{$current_path}) || !$line_weight || $type =~ /[ld]/ || $size > $max_script_size ? undef : $timestamp;
    }
    return \%bin;
}

sub build_bin {
    my $ls_bin = ls_bin;
    my $bin_cache = {};
    my @bin_remove = grep !exists $ls_bin->{$_}, keys %$bin_cache;
    # load lines for new and updated small bins having $HOME in the path (local bins)
    my @bin_update = grep $ls_bin->{$_} && (!exists $bin_cache->{$_} || $bin_cache->{$_}[0] != $ls_bin->{$_}), keys %$ls_bin;
    delete @{$bin_cache}{@bin_remove} if @bin_remove;
    for my $bin (@bin_update) {
        open(my $f, $bin);
        my @lines;
        while (<$f>) {
            # skip lines which contains no alphabet chars
            next unless m{[a-zA-Z]}; 
            chomp;
            push @lines, $_;
        }
        $bin_cache->{$bin} = [$ls_bin->{$bin},\@lines];
    }
    $ls_bin->{$_} = $bin_cache->{$_}[1] for keys %$bin_cache;
    return $ls_bin; # {file => \@lines || undef}
}

my %sf_processed;
sub process_start_file {
    my @files = grep -f,@_;
    return unless @files;
    for my $file (@files) {
        next if exists $sf_processed{$file};
        my ($cwd) = $file =~ m{(.*)/};
        $sf_processed{$file} = undef;
        open(my $fh, $file);
        while (<$fh>) {
            $line{"alias:$_"} = "$file:$." for m{^alias\s+(\S+?)=};
            $line{"function:$_"} = "$file:$." for m{^function\s+(\S+?)},m{^([^ ()]+)\s*\(\)};
            # process sourced scripts
            for (m{^\.\s+(\S+)},m{^\s*source\s+(\S+)}) {
                s/~/$ENV{HOME}/; # change "~" to $HOME
                s{^./}{$cwd/}; # change ./ to current working directory
                my $f = $_;
                # if file does not have full path let's look for it in PATH
                my ($fullpath) = m{^/}?$_:grep(-f $_,map "$_/$f", split /:/, $ENV{PATH});
                process_start_file($fullpath);
            }
        }
    }
}

__END__

=head1 NAME

findcmd.pl - quick find command using fuzzy patterns

=head1 SYNOPSIS

findcmd.pl [options] patter1 [pattern2 ...]

Increments hits for list of all bash functions, aliases, bin files from PATH by looking at their name and content for specified patterns.
It then lists names with non zero hits sorted by hits incrementally (the best match goes bottom)

 Options:
   -help                    brief help message
   
   -start_files ~/.bashrc   set of files which bash use to load commands. this is for resoving where aliases and functions are defined
                            you can separate several start files using ":"
                            
   -soundex_weight 10       if pattern matches bin name using soundex algorithm it 
                            adds 10 to hits on this bin.
                            If you don't want use soundex comparison use 
                            -soundex_weight 0
   -line_weight 1           for each line of bin that matches pattern regexp it 
                            increments hits by 1. 
                            If you don't want grepping over bin's lines use 
                            -line_weight 0
   -regex_weight 20         if pattern matches bin name using regexp comparison it 
                            adds 20 to hits on this bin
   -path_for_scripts ~/bin  Look for script lines only if script belongs to specified directories.
                            You can specify multiple pathes using 
                            ":" delimiter in a way you do for regular PATH env variable.
   -max_script_size 1024        Maximal size of file that will be considered as script so it's lines will be examined.

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.


=back

=head1 DESCRIPTION

B<findcmd.pl> builds the list of all commands (aliases, functions, binary over PATH) that is defined in ~./profile (see bash login invocation).
Take into account that commands defined at .bashrc (interactive invocation) are not available to search over.
It is good if you remember there was some command that sounds like this, but do not remember it's exact spelling
It also shows where particular alias/function has been defined

=cut
