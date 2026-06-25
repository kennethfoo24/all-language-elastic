# php-apache

## Instructions

Spins up a PHP application on port 8080.

Launch with `./run.sh`. This runs the application in detached mode.

Then connect to [http://localhost:8080](http://localhost:8080)

You can run an interactive shell on the container with:

```
docker exec -it simple-php sh
```

Access container logs with:

```
docker logs simple-php
```

## Endpoints

Endpoints are defined in the `app` folder:
* `/`: returns a hello world.
* `/add-tag.php`: placeholder endpoint for custom tag instrumentation.
* `/exception.php`: throws an exception — useful for testing error capture.
* `/add-span.php`: calls a traced function — placeholder for custom span instrumentation.

## Tear down

Run `docker-compose down`
