#!/usr/bin/php
<?php
$file_to_process = $argv[1];
$fileStr = file_get_contents($file_to_process);
$newStr  = '';
$commentTokens = array(T_COMMENT);
if (defined('T_DOC_COMMENT')) {
    $commentTokens[] = T_DOC_COMMENT; // PHP 5
}
elseif (defined('T_ML_COMMENT')) {
    $commentTokens[] = T_ML_COMMENT;  // PHP 4
}
$tokens = token_get_all($fileStr);
foreach ($tokens as $token) {
    if (is_array($token)) {
        if (in_array($token[0], $commentTokens))
            continue;
        $token = $token[1];
    }
    $newStr .= $token;
}
$newStr = preg_replace("/\n+/", "\n", $newStr); // Remove extra remainin newlines
echo $newStr;
