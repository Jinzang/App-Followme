package App::FollowmeSite;
use 5.008005;
use strict;
use warnings;

use IO::File;

our $VERSION = "0.74";
our $modeline;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(copy_file next_file);

#----------------------------------------------------------------------
# Create a copy of the input file

sub copy_file {
    my ($file, $text, $directory) = @_;

    my @dirs;    
    push(@dirs, split(/\//, $directory)) if $directory;
    push(@dirs, split(/\//, $file));
    my $base = pop(@dirs);
    
    my $path = '.';
    foreach my $dir (@dirs) {
        $path .= "/$dir";

        if (! -d $path) {
            mkdir ($path) or die "Couldn't create $path: $!\n";
        }
    }
    
    $path .= "/$base";
    return if -e $path;    

    my $out = IO::File->new($path, 'w') or die "Can't write $path";
    chomp $text;
    print $out $text;        
    close($out);
    
    return;
}

#----------------------------------------------------------------------
# Get the name and contents of the next file

sub next_file {
    
    $modeline ||= <DATA>;
    return unless $modeline;
    
    my ($comment, $file) = split(' ', $modeline);
    die "Bad modeline: $modeline\n" unless defined $file;
    
    my $text = '';
    $modeline = '';
    
    while (<DATA>) {
        if (/^\#--\%X--\%X/) {
            $modeline = $_;
            last;

        } else {
            $text .= $_;
        }
    }
    
    return ($file, $text);
}

1;
__DATA__
#--%X--%X template.html
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<!-- begin meta -->
<title>{{title}}</title>
<!-- end meta -->
</head>
<body>
<div id="header">
<h1>Site Title</h1>
</div>
<div id="content">
<!-- begin content -->
<h2>{{title}}</h2>

{{body}}    
<!-- end content-->
</div>
</body>
</html>

#--%X--%X {{archive_index}}_template.html
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<!-- begin meta -->
<title>{{title}}</title>
<!-- end meta -->
</head>
<body>
<div id="header">
<h1>Site Title</h1>
</div>
<div id="content">
<!-- begin content -->
<!-- loop -->
{{body}}
<p><a href="{{url}}">Written on {{month}} {{day}}, {{year}}</a></p>
<!-- endloop -->
<!-- end content-->
</div>
</body>
</html>

#--%X--%X {{archive_directory}}/index_template.html
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<!-- begin meta -->
<title>{{title}}</title>
<!-- end meta -->
</head>
<body>
<div id="header">
<h1>Site Title</h1>
</div>
<div id="content">
<!-- begin content -->
<h2>{{title}}</h2>

<ul>
<!-- loop --><li><a href="{{url}}">{{title}}</a></li>
<!-- endloop -->
</ul>
<!-- end content-->
</div>
</body>
</html>

