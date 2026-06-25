<?php
function tracedFunction() {
    sleep(1);
}

tracedFunction();

echo 'Adding a span';
?>