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
# A form for controling ldap lookups.
#
# << Here are all options seen in Postfix sample-ldap.cf >>

require './postfix-lib.pl';


$access{'ldap'} || &error($text{'ldap_ecannot'});
&ui_print_header(undef, $text{'ldap_title'}, "");

$default = $text{'opts_default'};
$none = $text{'opts_none'};
$no_ = $text{'opts_no'};

if (!(&is_existing_parameter($ldap_timeout)))
{
    print "$text{'ldap_non_existent'}<p>\n";
    &ui_print_footer("", $text{'index_return'});
    exit;
}


print "<form action=save_opts.cgi>\n";
print "<table border width=100%>\n";
print "<tr $tb> <td><b>$text{'ldap_title'}</b></td></tr>\n";
print "<tr $cb> <td><table width=100%>\n";

print "<tr>\n";
&option_freefield($ldap_timeout, 15);
print "</tr>\n";

print "<tr>\n";
&option_radios_freefield("ldap_search_base", 65, $none);
print "</tr>\n";

print "<tr>\n";
&option_radios_freefield("ldap_server_host", 65, $none);
print "</tr>\n";

print "</table></td></tr></table><p>\n";
print "<input type=submit value=\"$text{'opts_save'}\"></form>\n";
&ui_print_footer("", $text{'index_return'});




