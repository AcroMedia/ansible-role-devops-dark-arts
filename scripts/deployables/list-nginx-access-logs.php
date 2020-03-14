#!/usr/bin/php
<?php

/**
 * For collecting paths of all possible NGINX access logs on a given server.
 *
 * Usage:
 * ssh REMOTE_HOST -tq 'sudo /usr/bin/php --' < ./bin/list-nginx-access-logs.php |sort|uniq
 */

function main () {
  # See https://regex101.com/r/jWX6na/2
  $re = '/^[ \t]*access_log (.*);/mxUs';
  $conf = shell_exec('/usr/sbin/nginx -Tq');
  preg_match_all($re, $conf, $matches, PREG_SET_ORDER, 0);
  foreach ($matches as $match) {
    $config_values = explode(' ', $match[1]);
    foreach ($config_values as $candidate) {
      if (!empty($candidate)) {
        if (substr($candidate, 0, 1) == '/') {
          echo $candidate . "\n";
        }
      }
    }
  }
}

main();
