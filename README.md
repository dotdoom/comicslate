[![CircleCI](https://circleci.com/gh/dotdoom/comicslate.svg?style=shield)](https://circleci.com/gh/dotdoom/comicslate)


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

```shell
$ alias docker_run_comicslate='docker run \
    --detach --restart=unless-stopped --net=host \
    --publish 80:80 --publish 443:443 --publish 21:21 \
    --publish 10100-10200:10100-10200 \
    --ulimit memlock=1024000000:1024000000 \
    --hostname=comicslate.org --name=comicslate \
    --mount type=bind,source=/var/www,target=/var/www \
    dotdoom/comicslate:latest'
$ docker pull dotdoom/comicslate:latest &&
    password="$(docker exec comicslate getent shadow root | cut -d: -f2)" &&
    docker rename comicslate{,_old} &&
    docker stop comicslate_old &&
    docker_run_comicslate &&
    docker exec comicslate usermod -p "${password?}" root

# Verify that the new website works.

$ docker rm comicslate_old; docker image prune
```

If `docker run` fails or the new website doesn't work

```shell
$ docker stop comicslate; \
    docker rename comicslate{,_failed} && \
    docker rename comicslate{_old,} && \
    docker_run_comicslate
```

The previous container will be launched and `comicslate_failed` container will
stay around to inspect. Once done, it can be removed with
`docker rm comicslate_failed`.

## Useful commands

```shell
$ docker logs comicslate
$ docker exec -it comicslate bash
```

## TODO

* consider using `VOLUME` for certificates and password

* consider newer nullmailer (2+ has easier configuration) and certbot (0.19+
  supports certificate renewal hook directories), available from
  stretch-backports
