[![CircleCI](https://circleci.com/gh/dotdoom/comicslate.svg?style=shield)](https://circleci.com/gh/dotdoom/comicslate)


## Host system configuration

* for `vmtouch`

  ```
  # echo vm.max_map_count=512000 > /etc/sysctl.d/comicslate.conf
  # sysctl -p /etc/sysctl.d/comicslate.conf
  ```

## Operating

```
$ docker logs comicslate
$ docker stop comicslate && docker rm comicslate
$ docker run --detach --net=host --restart=unless-stopped \
	--ulimit memlock=1024000000:1024000000 \
	--hostname=comicslate.org --name=comicslate \
	--mount type=bind,source=/var/www,target=/var/www \
	dotdoom/comicslate:latest
$ docker exec -it comicslate bash
$ passwd
```

## TODO

* backup

* persist password across upgrades

* use container network without userland-proxy, if it helps to avoid downtime

* enable [live-restore](https://docs.docker.com/config/containers/live-restore/)

* lameduck for restart
