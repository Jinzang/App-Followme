#!/usr/bin/env perl
use strict;

use Test::More tests => 15;

use Cwd;
use IO::File;
use File::Path qw(rmtree);
use File::Spec::Functions qw(catdir catfile rel2abs splitdir);

#----------------------------------------------------------------------
# Load package

my @path = splitdir(rel2abs($0));
pop(@path);
pop(@path);

my $lib = catdir(@path, 'lib');
unshift(@INC, $lib);

eval "use App::Followme::FIO";
eval "use App::Followme::NestedText";

my $test_dir = catdir(@path, 'test');

rmtree($test_dir);
mkdir $test_dir or die $!;
chmod 0755, $test_dir;

chdir $test_dir or die $!;
$test_dir = cwd();

#----------------------------------------------------------------------
# Test trim_string

do {
	my $str;
	$str = App::Followme::NestedText::trim_string($str);
	is($str, '', "trim undefined string"); # test 1
	
	$str = " A very fine string with whitespace  ";
	$str = App::Followme::NestedText::trim_string($str);
	is($str, "A very fine string with whitespace", 
	    "trim string with blanks"); # test 2	
};

#----------------------------------------------------------------------
# Test parsing simple config

do {
	my $text = <<EOQ;
    name1: value1
    name2: value2
    name3: value3
EOQ

	my %value = (name1 => 'value1', name2 => 'value2', name3 => 'value3');
	my %config = nt_parse_string($text);
	is_deeply(\%config, \%value, "parse simple config"); # test 3
};

#----------------------------------------------------------------------
# Test parsing simple array

do {
	my $text = <<EOQ;
    name1: value1
    array_name: 
        - subvalue1
        - subvalue2
        - subvalue3
EOQ

	my %value = (name1 => 'value1',
				 array_name => ["subvalue1", "subvalue2", "subvalue3"],
				);
	my %config = nt_parse_string($text);
	is_deeply(\%config, \%value, "parse simple array"); # test 4
};

#----------------------------------------------------------------------
# Test parsing simple hash

do {
	my $text = <<EOQ;
    name1: value1
    hash_name:
        subname1: subvalue1
        subname2: subvalue2
        subname3: subvalue3
EOQ

	my %value = (name1 => 'value1',
				 hash_name => {subname1 => "subvalue1", 
							   subname2 => "subvalue2", 
							   subname3 => "subvalue3"},
				);
	my %config = nt_parse_string($text);
	is_deeply(\%config, \%value, "parse simple hash"); # test 5
};

#----------------------------------------------------------------------
# Test parsing long string

do {
	my $text = <<EOQ;
    name1: value1
    name2:
        > A longer value
        > split across lines
        > however many you need
    name3: value3
EOQ

	my %value = (name1 => 'value1', 
				 name2 => 'A longer value split across lines however many you need', 
				 name3 => 'value3');
	my %config = nt_parse_string($text);
	is_deeply(\%config, \%value, "parse simple config"); # test 6
};

#----------------------------------------------------------------------
# Test parsing comments and blank lines

do {
	my $text = <<EOQ;
	# This is a test og parsing comments
    name1: value1
    
    name2: value2

    name3: value3

  # That's all folks! 
EOQ

	my %value = (name1 => 'value1', name2 => 'value2', name3 => 'value3');
	my %config = nt_parse_string($text);
	is_deeply(\%config, \%value, "parse blank lines and comments"); # test 7
};

#----------------------------------------------------------------------
# Test parsing multi-level hash

do {
	my $text = <<EOQ;
    name1: value1
    name2:
        subname1: subvalue1
        subname2:
            - 10
            - 20
            - 30
        subname3: subvalue3
    name3: value3
EOQ

	my %value = (name1 => 'value1',
				 name2 => {subname1 => "subvalue1", 
						   subname2 => [10, 20, 30], 
						   subname3 => "subvalue3"},
				 name3 => 'value3',
				);
				
	my %config = nt_parse_string($text);
	is_deeply(\%config, \%value, "parse multi-level hash"); # test 8
};

#----------------------------------------------------------------------
# Test parsing file contents

do {
	my $output = <<EOQ;
    name1: value1
    name2:
        subname1: subvalue1
        subname2:
            - 10
            - 20
            - 30
        subname3: subvalue3
    name3: value3
EOQ

	my %value = (name1 => 'value1',
				 name2 => {subname1 => "subvalue1", 
						   subname2 => [10, 20, 30], 
						   subname3 => "subvalue3"},
				 name3 => 'value3',
				);
				
	my $filename = catfile($test_dir, 'test.cfg');
    fio_write_page($filename, $output);
    
	my %config = nt_parse_file($filename);
	is_deeply(\%config, \%value, "parse file contents"); # test 9
   
};

#----------------------------------------------------------------------
# Test error cases

do {
	my %config;
	
	my $text = <<EOQ;
    - 1
    - 2
    - 3
EOQ

	eval{%config = nt_parse_string($text)};
	is($@, "Configuration must be a hash\n", 
	   "config is an array"); # test 10

	$text = <<EOQ;
    name1: value1
    name2:
        subname1: subvalue1
        subname2: subvalue2
  name3: value3
EOQ

	eval{%config = nt_parse_string($text)};
	my ($err, $msg) = split(/ at /, $@);
	is($err, "Bad indent", "badly indented data"); # test 11

	$text = <<EOQ;
    name1: value1
    - value2
    > value3
EOQ

	eval{%config = nt_parse_string($text)};
	($err, $msg) = split(/ at /, $@);
	is($err, "Missing indent", "mixed types in block"); # test 12

	$text = <<EOQ;
    name1: value1
    name2: value2
	    name3: value3
EOQ

	eval{%config = nt_parse_string($text)};
	($err, $msg) = split(/ at /, $@);
	is($err, "Duplicate value", 
	   "inconsistent indentation in block"); # test 13

	$text = <<EOQ;
    name1: value1
    name2: 
	    > value2
	        > value3
EOQ

	eval{%config = nt_parse_string($text)};
	($err, $msg) = split(/ at /, $@);
	is($err, "Indent under string", 
	   "inconsistent indentation in string"); # test 14

	$text = <<EOQ;
    name1: value1
    name2  value2

EOQ

	eval{%config = nt_parse_string($text)};
	($err, $msg) = split(/ at /, $@);
	is($err, "Bad tag", "missing tag"); # test 15
};
