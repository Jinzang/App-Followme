requires 'perl', '5.008001';
requires 'Net::FTP', '0';
requires 'Text::Markdown', '1.000031';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

