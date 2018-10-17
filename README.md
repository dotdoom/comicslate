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
$ docker run --detach --name=comicslate --restart=unless-stopped \
	--hostname comicslate.org \
	-p 80:80 -p 443:443 -p 21:21 -p 10100-10200:10100-10200 \
	--mount type=bind,source=/var/www,target=/var/www \
	comicslate:latest
$ docker exec -it comicslate bash
$ passwd
```
