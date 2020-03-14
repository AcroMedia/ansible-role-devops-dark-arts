#!/usr/bin/php
<?php

/**
 * Usage:
 *
 * ssh REMOTE_HOST -tq 'sudo /usr/bin/php --' < ./bin/list-nginx-server-names.php |sort|uniq
 */


function main () {
  # See https://regex101.com/r/jWX6na/5
  $re = '/^[ \t]*server_name (.*);/mxUs';
  $str = shell_exec('/usr/sbin/nginx -Tq');
  preg_match_all($re, $str, $matches, PREG_SET_ORDER, 0);
  foreach ($matches as $match) {
    $server_names = explode(' ', $match[1]);
    foreach ($server_names as $server_name) {
      if (! in_array((string)trim($server_name), array('_', '', 'localhost', 's_hash_bucket_size', "\n", '128'))) {
        echo $server_name . "\n";
      }
    }
  }
}

main();
