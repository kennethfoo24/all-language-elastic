<?php

function doRiskyThing() {
    sleep(1);
    throw new Exception('Oops!');
}

doRiskyThing();

echo 'Throwing an exception';
?>