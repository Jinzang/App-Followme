package App::Followme::Initialize;
use 5.008005;
use strict;
use warnings;

use Cwd;
use IO::File;
use File::Spec::Functions qw(splitdir catfile);

our $VERSION = "0.99";
our $modeline;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(initialize);

#----------------------------------------------------------------------
# Initialize a new web site

sub initialize {
    my ($directory) = @_;
    chdir($directory) if defined $directory;
    
    for (;;) {
        my ($file, $text) = next_file();
        last unless defined $file;
        
        copy_file($file, $text);
    }
    
    return;
}

#----------------------------------------------------------------------
# Create a copy of the input file

sub copy_file {
    my ($file, $text) = @_;

    my $current_directory = getcwd();
    my @dirs = splitdir($file);
    my $base = pop(@dirs);
    
    foreach my $dir (@dirs) {
        if (! -d $dir) {
            mkdir ($dir) or die "Couldn't create $dir: $!\n";
        }
        chdir($dir);
    }
    
    return if -e $base;    

    my $out = IO::File->new($base, 'w') or die "Can't write $file";
    print $out $text;        
    close($out);
    
    chdir($current_directory);
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
run_before = App::Followme::FormatPage
run_before = App::Followme::ConvertPage
#--%X--%X archive/followme.cfg
run_before = App::Followme::CreateNews
news_index_file = index.html
news_file = ../blog.html
#--%X--%X templates/page.htm
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<!-- section meta -->
<title>$title</title>
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
<h2>$title</h2>
$body    
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
<title>$title</title>
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
<!-- for @loop -->
<h2>$title</h2>
$body
<p><a href="$url">Written on $month $day, $year</a></p>
<!-- endfor -->
<!-- endsection content-->
</div>
</body>
</html>

#--%X--%X templates/news_index.htm
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<!-- section meta -->
<title>$title</title>
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
<h2>$title</h2>

<ul>
<!-- for @loop -->
<li><a href="$url">$title</a></li>
<!-- endfor -->
</ul>
<!-- endsection content-->
</div>
</body>
</html>

#--%X--%X templates/index.htm
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<!-- section meta -->
<title>$title</title>
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
<h2>$title</h2>

<ul>
<!-- for @loop -->
<li><a href="$url">$title</a></li>
<!-- endfor -->
</ul>
<!-- endsection content-->
</div>
</body>
</html>

