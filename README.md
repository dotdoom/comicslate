[![CircleCI](https://circleci.com/gh/dotdoom/comicslate.svg?style=shield)](https://circleci.com/gh/dotdoom/comicslate)


## Host system configuration

* for `vmtouch`

  ```
  # echo vm.max_map_count=512000 > /etc/sysctl.d/comicslate.conf
  # sysctl -p /etc/sysctl.d/comicslate.conf
  ```

## Update

```
$ password="$(docker exec comicslate getent shadow root | cut -d: -f2)"
$ docker stop comicslate && docker rm comicslate
$ docker run --detach --net=host --restart=unless-stopped \
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

* use container network without userland-proxy, if it helps to avoid downtime

* enable [live-restore](https://docs.docker.com/config/containers/live-restore/)
