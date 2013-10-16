package App::Followme::Initialize;
use 5.008005;
use strict;
use warnings;

use IO::File;
use File::Spec::Functions qw(splitdir catfile);

our $VERSION = "0.90";
our $modeline;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(initialize);

#----------------------------------------------------------------------
# Initialize a new web site

sub initialize {
    my ($directory) = @_;

    for (;;) {
        my ($file, $text) = next_file();
        last unless defined $file;
        
        copy_file($file, $text, $directory);
    }
    
    return;
}

#----------------------------------------------------------------------
# Create a copy of the input file

sub copy_file {
    my ($file, $text, $directory) = @_;

    my @dirs;    
    push(@dirs, splitdir($directory)) if $directory;
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
    
    my @dirs = split('/', $file);
    $file = catfile(@dirs);
    
    return ($file, $text);
}

1;
__DATA__
#--%X--%X followme.cfg
module = App::Followme::FormatPages
module = App::Followme::ConvertPages
#--%X--%X blog/followme.cfg
module = App::Followme::CreateIndexes
module = App::Followme::CreateNews
index_file = archive.html
news_file = index.html
#--%X--%X templates/page.htm
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<!-- section meta -->
<title>{{title}}</title>
<!-- endsection meta -->
</head>
<body>
<div id="header">
<h1>Site Title</h1>
</div>
<div id="sidebar">
<!-- section navigation -->
<!-- endsection navigation -->
<!-- section sidebar -->
<!-- endsection sidebar -->
</div>
<div id="content">
<!-- section content -->
<h2>{{title}}</h2>

{{body}}    
<!-- endsection content-->
</div>
</body>
</html>

#--%X--%X templates/news.htm
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<!-- section meta -->
<title>{{title}}</title>
<!-- endsection meta -->
</head>
<body>
<div id="header">
<h1>Site Title</h1>
</div>
<div id="sidebar">
<!-- section navigation -->
<!-- endsection navigation -->
<!-- section sidebar -->
<!-- endsection sidebar -->
</div>
<div id="content">
<!-- section content -->
<!-- loop -->
{{body}}
<p><a href="{{url}}">Written on {{month}} {{day}}, {{year}}</a></p>
<!-- endloop -->
<!-- endsection content-->
</div>
</body>
</html>

#--%X--%X templates/index.htm
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<!-- section meta -->
<title>{{title}}</title>
<!-- endsection meta -->
</head>
<body>
<div id="header">
<h1>Site Title</h1>
</div>
<div id="sidebar">
<!-- section navigation -->
<!-- endsection navigation -->
<!-- section sidebar -->
<!-- endsection sidebar -->
</div>
<div id="content">
<!-- section content -->
<h2>{{title}}</h2>

<ul>
<!-- loop --><li><a href="{{url}}">{{title}}</a></li>
<!-- endloop -->
</ul>
<!-- endsection content-->
</div>
</body>
</html>

