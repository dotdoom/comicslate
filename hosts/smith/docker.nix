{ pkgs, ... }:
let
  docker-comicslate = ./docker-comicslate.yaml;
in
{
  virtualisation.docker.enable = true;
  systemd.services.docker-comicslate = {
    description = "docker comicslate";

    after = [ "docker.service" ];
    requires = [ "docker.service" ];

    wantedBy = [ "multi-user.target" ];

    # reloadTriggers doesn't work as expected here because changing docker file
    # changes its path, which subsequently changes ExecStart/ExecStop command
    # line, and triggers a restart.
    reloadIfChanged = true;

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose -f ${docker-comicslate} up -d";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose -f ${docker-comicslate} up -d";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose -f ${docker-comicslate} down";
    };
  };
}
