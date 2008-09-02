#!/usr/local/bin/perl
#
# postfix-module by Guillaume Cottenceau <gc@mandrakesoft.com>,
# for webmin by Jamie Cameron
#
# Copyright (c) 2000 by Mandrakesoft
#
# Permission to use, copy, modify, and distribute this software and its
# documentation under the terms of the GNU General Public License is hereby 
# granted. No representations are made about the suitability of this software 
# for any purpose. It is provided "as is" without express or implied warranty.
# See the GNU General Public License for more details.
#
#
# A form for controling debugging features.
#
# << Here are all options seen in Postfix sample-debug.cf >>

require './postfix-lib.pl';


$access{'debug'} || &error($text{'debug_ecannot'});
&ui_print_header(undef, $text{'debug_title'}, "");

$default = $text{'opts_default'};
$none = $text{'opts_none'};
$no_ = $text{'opts_no'};

# Start of form
print &ui_form_start("save_opts.cgi");
print &ui_table_start($text{'debug_title'}, "width=100%", 4);

&option_freefield("debug_peer_list", 65);

&option_freefield("debug_peer_level", 15);

print &ui_table_end();
print &ui_form_end([ [ undef, $text{'opts_save'} ] ]);

&ui_print_footer("", $text{'index_return'});

