requires 'perl', '5.008001';
recommends 'GD', 0;
recommends 'Net::FTP', '0';
recommends 'Text::Markdown', '1.000031';

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires => 'Test::Requires', 0;
};
