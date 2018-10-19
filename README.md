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
    exposed port will get a separate set of `iptables` rules. For this to work,
    you have to remove `--net=host` from the `docker run` command line below,
    and keep `--publish` port lists up to date.

    If you keep `--net=host`, it would mean that container can use any host
    ports (which is less secure). On the other hand, using `--net=host` means
    that ports allocation is accounted for by the kernel, and kernel will fail
    system call for another process to listen on a used port, as opposed to
    `iptables` which will silently intercept the traffic and always route it
    into the container.

  Update `/etc/docker/daemon.json`:

  ```
  {
    "live-restore": true,
    "userland-proxy": false
  }
  ```

  To apply the settings, restart Docker daemon with `systemctl restart docker`.

## Update

```
$ docker pull dotdoom/comicslate:latest
$ password="$(docker exec comicslate getent shadow root | cut -d: -f2)"
$ docker stop comicslate && docker rm comicslate
$ docker run --detach --net=host --restart=unless-stopped \
	--publish 80:80 --publish 443:443 --publish 21:21 \
	--publish 10100-10200:10100-10200 \
	--ulimit memlock=1024000000:1024000000 \
	--hostname=comicslate.org --name=comicslate \
	--mount type=bind,source=/var/www,target=/var/www \
	dotdoom/comicslate:latest
$ docker exec comicslate usermod -p "${password?}" root
```

## Useful commands

```
$ docker logs comicslate
$ docker exec -it comicslate bash
```

## TODO

* backup
