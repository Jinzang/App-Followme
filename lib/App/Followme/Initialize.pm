package App::Followme::Initialize;
use 5.008005;
use strict;
use warnings;

use Cwd;
use IO::File;
use File::Spec::Functions qw(splitdir catfile);
our $VERSION = "1.13";

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(initialize);

use constant CMD_PREFIX => '#>>>';

#----------------------------------------------------------------------
# Initialize a new web site

sub initialize {
    my ($directory) = @_;

    chdir($directory) if defined $directory;
    my ($read, $unread) = data_readers();

    for (;;) {
        my ($file, $text) = next_file($read, $unread);
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
# Return closures to read the data section of this file

sub data_readers {
    my @pushback;

    my $read = sub {
        if (@pushback) {
            return pop(@pushback);
        } else {
            return <DATA>;
        }
    };

    my $unread = sub {
        my ($line) = @_;
        push(@pushback, $line);
    };

    return ($read, $unread);
}

#----------------------------------------------------------------------
# Is the line a command?

sub is_command {
    my ($line) = @_;

    my $prefix = CMD_PREFIX;
    return $line =~ /^$prefix/;
}

#----------------------------------------------------------------------
# Get the name and contents of the next file

sub next_file {
    my ($read, $unread) = @_;

    my $line = $read->();
    return unless defined $line;

    my ($cmd, $file) = parse_command($line);
    die "Command not supported: $line" unless $cmd eq 'copy';

    my @dirs = split('/', $file);
    $file = catfile(@dirs);

    my @lines;
    while ($line = $read->()) {
        if (is_command($line)) {
            $unread->($line);
            last;

        } else {
            push(@lines, $line);
        }
    }

    my $text = join('', @lines);
    return ($file, $text);
}

#----------------------------------------------------------------------
# Parse command read from the data file

sub parse_command {
    my ($line) = @_;

    die "Command not found: $line" unless is_command($line);

    my $prefix = CMD_PREFIX;
    $line =~ s/^$prefix//;

    my ($cmd, $file) = split(' ', $line);
    die "Bad command line: $line" unless defined $file;

    return ($cmd, $file);
}

1;
__DATA__
#>>>copy index.html
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<!-- section meta -->
<title>Page Title</title>
<!-- endsection meta -->
</head>
<body>
<div id="header">
<h1>Site Title</h1>
</div>
<div id="content">
<!-- section content -->
<h2>Page Title</h2>

<p>Page text.</p>
<!-- endsection content-->
</div>
</body>
</html>
#>>>copy followme.cfg
run_before = App::Followme::FormatPage
run_before = App::Followme::ConvertPage

#>>>copy archive/followme.cfg
run_before = App::Followme::CreateNews
news_index_file = index.html
news_file = ../blog.html
#>>>copy templates/news_index.htm
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

#>>>copy templates/news.htm
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

#>>>copy templates/page.htm
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
<div id="content">
<!-- section content -->
<h2>$title</h2>
$body
<!-- endsection content-->
</div>
</body>
</html>

#>>>copy templates/gallery.htm
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<!-- section meta -->
<title>$title</title>
<style>
div.float {
  float: left;
  padding: 10px;
  vertical-align: top;
  }
div.float p {
   text-align: center;
   }
</style>
<script>
var win = null;
function pop(mypage,myname,w,h){
  LeftPosition = (screen.width) ? (screen.width-w)/2 : 0;
  TopPosition = (screen.height) ? (screen.height-h)/2 : 0;
  settings = 'height='+h+',width='+w+',top='+TopPosition+
  ',left='+LeftPosition+',status=no,scrollbars=no,resizable=no'
  win = window.open(mypage,myname,settings)
}
</script>
<!-- endsection meta -->
</head>
<body>
<div id="header">
<h1>Site Title</h1>
</div>
<div id="content">
<!-- section content -->
<div class="spacer">
  &nbsp;
</div>
<!-- for @loop -->
<div class="float">
  <a target="_blank"
  onclick="pop(this.href,'_blank',
  '$photo_width','$photo_height');return false"
  href="$photo_url"><img width="$thumb_width" height="$thumb_height"
  src="$thumb_url"></a><br>
  <p>$title</p>
</div>
<!-- endfor -->
<div class="spacer">
  &nbsp;
</div>
<!-- endsection content-->
</div>
</body>
</html>
#>>>copy templates/index.htm
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
