# Docker image for comicslate.org webserver

[![Docker Build Status](https://img.shields.io/docker/build/dotdoom/comicslate.svg)](https://hub.docker.com/r/dotdoom/comicslate/builds/)
[![MicroBadger Size](https://img.shields.io/microbadger/image-size/dotdoom/comicslate.svg)](https://hub.docker.com/r/dotdoom/comicslate/tags/)

## Host system configuration

* for `vmtouch` (locking most frequently accessed data in memory)

  ```
  # echo vm.max_map_count=512000 > /etc/sysctl.d/comicslate.conf
  # sysctl -p /etc/sysctl.d/comicslate.conf
  ```

* for Docker (optimization)

  * enable [live-restore](
    https://docs.docker.com/config/containers/live-restore/), which allows
    containers to keep running even when Docker daemon is restarted, for example
    due to `docker-ce` package upgrade on the host system.

  * disable [userland-proxy](https://docs.docker.com/v1.7/articles/networking/),
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

  Update `/etc/docker/daemon.json`

  ```json
  {
    "live-restore": true,
    "userland-proxy": false
  }
  ```

  To apply the settings, restart Docker daemon with `systemctl restart docker`.

## Getting (new) certificates

* disable HTTPS backend check in CloudFlare for the websites that do not have a
  valid certificate (on the Crypto page, set SSL to Flexible)

* use `docker run` command line from below, but instead type `docker run -it`.
  This will start a container in debug mode and a shell session inside it

* run the following commands

  ```shell
  # Set your email
  $ EMAIL=example@gmail.com

  # Walk through /var/www to get certificate for every domain (assuming that all
  # files with '.' in the name are domain names).
  $ for vhost_path in /var/www/*.*; do
    domain="$(basename "${vhost_path?}")"
    certbot certonly \
      --agree-tos \
      --email "${EMAIL?}" \
      --domain "${domain?}" \
      --webroot \
      --webroot-path "${vhost_path?}"
  done
  ```

## Update

Use [v2tec/watchtower](https://github.com/v2tec/watchtower) for completely
automated updates, or use the following procedure for startup or manual update:

```shell
$ alias docker_run_comicslate='docker run \
    --detach --restart=unless-stopped --net=host \
    --publish 80:80 --publish 443:443 --publish 21:21 \
    --publish 10100-20100:10100-20100 \
    --ulimit memlock=1024000000:1024000000 \
    --hostname=comicslate.org --name=comicslate \
    --mount type=bind,source=/var/www,target=/var/www \
    dotdoom/comicslate:latest'
$ docker pull dotdoom/comicslate:latest &&
    docker rename comicslate{,_old} &&
    docker stop comicslate_old &&
    docker_run_comicslate &&
    docker logs -f comicslate

# Verify that the new website works.

^C
$ docker rm comicslate_old; docker image prune
```

If `docker run` fails or the new website doesn't work

```shell
^C
$ docker stop comicslate; \
    docker rename comicslate{,_failed} &&
    docker rename comicslate{_old,} &&
    docker_run_comicslate
```

The previous container will be launched and `comicslate_failed` container will
stay around for inspection. Once it's done, that container can be removed with
`docker rm comicslate_failed`.

## Useful commands

```shell
$ docker logs comicslate
$ docker exec -it comicslate bash
```

## TODO

* consider newer nullmailer (2+ has easier configuration) and certbot (0.19+
  supports certificate renewal hook directories), available from
  stretch-backports
