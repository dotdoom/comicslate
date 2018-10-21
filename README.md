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

## First run

* use `docker run` command line from below, but with `-it bash`

* disable HTTPS backend check in CloudFlare (on the Crypto page,
  set SSL to Flexible)

* start Apache with `apachectl -D NoSSL`

* use `update-certificates.sh` script to obtain certificates

## Update

```shell
$ docker pull dotdoom/comicslate:latest
$ password="$(docker exec comicslate getent shadow root | cut -d: -f2)"
$ docker rename comicslate{,_old}
$ docker stop comicslate_old && docker run --detach --restart=unless-stopped \
	--net=host \
	--publish 80:80 --publish 443:443 --publish 21:21 \
	--publish 10100-10200:10100-10200 \
	--ulimit memlock=1024000000:1024000000 \
	--hostname=comicslate.org --name=comicslate \
	--mount type=bind,source=/var/www,target=/var/www \
	dotdoom/comicslate:latest
$ docker exec comicslate usermod -p "${password?}" root

# Verify that the new website works.

$ docker rm comicslate_old
$ docker image prune
```

If `docker run` fails or the new website doesn't work

```shell
$ docker stop comicslate
$ docker rename comicslate{,_failed}
$ docker rename comicslate{_old,}
$ docker run ... # see arguments above
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

* consider usefulness of `uodate-certificates.sh` vs `certbot -q renew` which is
  already in cron.d, and only needs Apache and vsftpd reload hooks put into
  `/etc/letsencrypt`. Initial certificate fetch instructions can be put here.

* fix cron backups, and make sure it emails on failures
