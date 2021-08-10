# Docker image for comicslate.org webserver

![Docker Build](https://github.com/dotdoom/comicslate/actions/workflows/ci.yml/badge.svg)
![Docker Image Size (latest by date)](https://img.shields.io/docker/image-size/dotdoom/comicslate)

## Build configuration

Get a personal access token (Read, Write and Delete permission) from
https://hub.docker.com/settings/security and set `DOCKERHUB_USERNAME` and
`DOCKERHUB_TOKEN` secrets in GitHub repository.

## Host system configuration

- for `vmtouch` (optimization, locking most frequently accessed data in memory)

  ```
  # echo vm.max_map_count=1024000 > /etc/sysctl.d/comicslate.conf
  # sysctl -p /etc/sysctl.d/comicslate.conf
  ```

- for Docker (optimization)

  - enable [live-restore](https://docs.docker.com/config/containers/live-restore/), which allows
    containers to keep running even when Docker daemon is restarted, for example
    due to `docker-ce` package upgrade on the host system.

  - disable [userland-proxy](https://docs.docker.com/v1.7/articles/networking/),
    which means that Docker will use iptables rules instead of spawning a
    proxy process to forward each port from host to container. Note that due to
    a [missing optimization](https://github.com/moby/moby/issues/11185), each
    exposed port will get a separate set of iptables rules.

    For iptables rules to be added, you have to remove `--net=host` from the
    `docker run` command line below, and keep `--publish` port lists up to date.

    If you decide to keep `--net=host`, it would mean that container can use any
    host ports (which is less secure). On the other hand, using `--net=host`
    means that ports allocation is accounted for by the kernel. If any other
    container or application will try to reuse one of the ports, kernel system
    call will complain in an obvious way. In case of iptables rules, the traffic
    will be silently intercepted by the container.

  - [switch](https://docs.docker.com/config/containers/logging/configure/)
    logging driver to "local" to enable automatic log rotation. A long-running
    container will accumulate a lot of logs, and `docker logs` will struggle
    scanning through them to display the most recent entries.

  Update `/etc/docker/daemon.json`:

  ```json
  {
    "live-restore": true,
    "userland-proxy": false,
    "log-driver": "local"
  }
  ```

  To apply the settings, restart Docker daemon with `systemctl restart docker`.

## Optional features

- save alias user for `www-data` (for FTP access) to `/var/www/.htsecure/shadow`
  in the form of `passwordhash username`. FTP has to be accessed by `www-data`
  to ensure readability of created files and directories by the web server.

## Getting certificates from scratch

1. disable HTTPS backend check in CloudFlare (on the Crypto page, set SSL to
   Flexible)

1. use `docker run` command line from below, but instead type `docker run -it`.
   This will start a container in debug mode and a shell session inside it

1. run the following commands

   ```shell
   $ EMAIL=example@gmail.com
   $ DOMAINS=({test.,}comicslate.org)
   $ for domain in "${DOMAINS[@]?}"; do
       certbot certonly \
           --agree-tos \
           --email "${EMAIL?}" \
           --domain "${domain?}" \
           --domain "www.${domain?}" \
           --webroot \
           --webroot-path /var/www/html
     done
   ```

## Getting certificates for a new domain

1. configure the new domain in `apache2.conf` without SSL support (i.e.
   `VirtualHost *:80` only), no ~~`Use SSL`~~

1. update the server

1. add the new domain to CloudFlare, but make it DNS-only (no HTTPS proxy).
   Alternatively, set SSL to Flexible on the Crypto page, but this setting is
   website-wide, so it is a security risk for other domains in the same site

1. run the following command

   ```shell
   $ EMAIL=example@gmail.com
   $ DOMAIN=test2.comicslate.org
   $ docker exec -it comicslate certbot certonly \
       --agree-tos \
       --email "${EMAIL?}" \
       --domain "${DOMAIN?}" \
       --webroot \
       --webroot-path /var/www/html
   ```

1. enable HTTPS proxy for the domain on CloudFlare, set SSL to "Full (strict)",
   add `VirtualHost *:443` section to `apache2.conf` with `Use SSL` and update
   the server

## Update

Use [watchtower](https://github.com/containrrr/watchtower) for completely
automated updates, and use the following procedure for startup, manual update or
**rollback to `stable`**:

```shell
# Replace "stable" with "latest" to run from a regular image.
$ comicslate_image=dotdoom/comicslate:stable

$ alias docker_run_comicslate='docker run \
    --detach --restart=unless-stopped --net=host \
    --publish 80:80 --publish 443:443 --publish 21:21 \
    --publish 10100-20100:10100-20100 \
    --ulimit memlock=2048000000 \
    --hostname=comicslate.org --name=comicslate \
    --add-host=comicslate.org:127.0.0.1 \
    --mount type=bind,source=/var/www,target=/var/www \
    "${comicslate_image}"'
$ docker pull $comicslate_image &&
    docker rename comicslate{,_old} &&
    docker stop comicslate_old &&
    docker_run_comicslate &&
    docker logs -f comicslate
```

Verify that the website works, and if so (unless you want to inspect old one):

```shell
^C
$ docker rm comicslate_old; docker image prune
```

Don't forget to push the changes (from your workstation) to `stable` branch:

```shell
$ git fetch && git push origin origin/master:stable
```

## Useful commands

```shell
# Recent logs for container, with following (^C to stop following).
$ docker logs --since 48h -f comicslate

# Enter a running container.
$ docker exec -it comicslate bash

# Start a container that otherwise fails to start.
$ comicslate_image=dotdoom/comicslate:latest
$ docker run -it --net=host --mount type=bind,source=/var/www,target=/var/www \
    $comicslate_image
# When it's even more broken, you can omit --net=host, or even add
# "--entrypoint bash" before image name.
```
