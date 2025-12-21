{ self }:

{
  lib,
  pkgs,
  config,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    toInt
    match
    mapAttrs'
    literalExpression
    mkPackageOption
    getExe
    getExe'
    attrValues
    all
    elemAt
    elem
    ;
  cfg = config.services.scpsl-server;

  singleAttrOf =
    elemType:
    types.addCheck (types.attrsOf elemType) (
      actual: (lib.isAttrs actual) && ((lib.lists.length (lib.attrValues actual)) == 1)
    );

  format = pkgs.formats.yaml { };
in

{
  options.services.scpsl-server = {
    enable = mkEnableOption "SCP:SL server";

    package = mkPackageOption pkgs "scpsl-server" { };

    eula = mkEnableOption "" // {
      description = "Whether to accept the eula";
    };

    openFirewall = mkEnableOption "" // {
      description = "Whether to open the ports of every instance";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/srv/scpsl";
      description = ''
        The data directory containing the configuration files
      '';
    };

    user = mkOption {
      type = types.str;
      default = "scpsl";
      description = ''
        The user to run the server with
      '';
    };

    group = mkOption {
      type = types.str;
      default = "scpsl";
      description = ''
        The group to run the server with
      '';
    };

    servers = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:

          {
            options = {
              enable = mkEnableOption "an SCP:SL instance" // {
                default = true;
              };

              autoStart = mkEnableOption "auto starting the instance on boot" // {
                default = true;
              };

              socketPath = mkOption {
                type = types.functionTo types.path;
                description = ''
                  Function from a server name to the path at which the server's tmux socket is placed.
                '';
                default = name: "/run/scpsl/${name}.sock";
                defaultText = literalExpression ''name: "/run/scpsl/''${name}.sock"'';
              };

              settings = mkOption {
                type = types.submodule {
                  freeformType = format.type;

                  options.port = mkOption {
                    type = types.port;
                    default = if (match "[0-9]{1,5}" name != null) then toInt name else 7777;
                    description = ''
                      The port for this instance
                    '';
                  };
                };
                default = { };
              };

              adminSettings = mkOption {
                type = types.submodule {
                  freeformType = format.type;

                  options = {
                    Members = mkOption {
                      type = with types; listOf (singleAttrOf str);
                      default = [ ];
                      description = ''
                        A list of an a steam 64 id followed by @steam mapped to a role defined
                        in {option}`services.scpsl-server.servers.<name>.adminSettings.Roles`
                      '';
                    };

                    Roles = mkOption {
                      type = types.listOf types.str;
                      default = [
                        "owner"
                        "admin"
                        "moderator"
                      ];
                    };
                  };
                };
                default = { };
              };
            };
          }
        )
      );
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.eula;
        message = ''
          You must accept the eula to run an SCP:SL server
        '';
      }
      {
        assertion = cfg.enable && cfg.servers != { };
        message = ''
          Enabling SCP:SL without configuring a server doesn't work
        '';
      }
      {
        assertion = all (
          conf:
          all (
            member: elem (elemAt (attrValues member) 0) conf.adminSettings.Roles
          ) conf.adminSettings.Members
        ) (attrValues cfg.servers);
        message = ''
          Members can only have a role defined in
          {option}`services.scpsl-server.servers.<name>.adminSettings.Roles`
        '';
      }
    ];

    nixpkgs.overlays = [
      (final: prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system}) scpsl-server;
      })
    ];

    networking.firewall.allowedUDPPorts = mkIf cfg.openFirewall (
      map (conf: conf.settings.port) (attrValues cfg.servers)
    );

    users.users.scpsl = mkIf (cfg.user == "scpsl") {
      inherit (cfg) group;
      description = "SCP Secret Laboratory server service user";
      home = cfg.dataDir;
      createHome = true;
      homeMode = "770";
      isSystemUser = true;
    };

    users.groups.scpsl = mkIf (cfg.group == "scpsl") { };

    systemd.services = mapAttrs' (name: conf: {
      name = "scpsl-server-${name}";
      value =
        let
          # Don't expose executable in PATH
          tmux = getExe pkgs.tmux;
          yq = getExe pkgs.yq-go;

          socket = conf.socketPath name;
          rootDir = "${cfg.dataDir}/.config/SCP Secret Laboratory";
          configDir = "${rootDir}/config";
          templateDir = "${cfg.package}/share/scpsl-server/ConfigTemplates";
        in
        {
          inherit (conf) enable;
          description = "SCP:SL server ${name}";
          wantedBy = mkIf conf.autoStart [ "multi-user.target" ];
          after = [ "network.target" ];

          startLimitIntervalSec = 120;
          startLimitBurst = 5;

          serviceConfig = {
            Type = "forking";
            GuessMainPID = true;

            ExecStartPre = getExe (
              pkgs.writeShellApplication {
                name = "scpsl-server-${name}-start-pre";
                text =
                  let
                    port = toString conf.settings.port;

                    ensureDirectories = ''
                      [[ ! -d "${configDir}" ]] && mkdir -p "${configDir}"
                      [[ ! -d "${configDir}/${port}" ]] && mkdir -p "${configDir}/${port}"
                      [[ ! -h "$HOME/${port}" ]] && ln -sf "${configDir}/${port}" "$HOME/${port}"
                    '';

                    settings = format.generate "nix_config_gameplay.yaml" conf.settings;
                    adminSettings = format.generate "nix_config_remoteadmin.yaml" conf.adminSettings;
                    mergeConfigs = ''
                      ${yq} -r -I1 '
                          . * load("${adminSettings}")
                          | (.[][][] | select(kind == "seq")) style="flow"
                        ' \
                        ${templateDir}/config_remoteadmin.template.txt \
                        > "$HOME/${port}/config_remoteadmin.txt"

                      ${yq} -r -I1 '
                          del(.port_queue, .geoblocking_whitelist, .geoblocking_blacklist)
                          | . * load("${settings}")
                          | .spawn_protect_team style="flow"
                        ' \
                        ${templateDir}/config_gameplay.template.txt \
                        > "$HOME/${port}/config_gameplay.txt"

                      sed -Ei 's/\"//g' "$HOME/${port}/config_"{gameplay,remoteadmin}.txt
                    '';
                  in
                  ''
                    ${ensureDirectories}
                    ${mergeConfigs}
                  '';
              }
            );

            ExecStart = getExe (
              pkgs.writeShellApplication {
                name = "scpsl-server-${name}-start";
                text = ''
                  cd ${cfg.package}/share/scpsl-server

                  ${tmux} -S ${socket} new -d ./LocalAdmin "${toString conf.settings.port}" --acceptEULA --useDefault

                  # See https://github.com/Infinidoge/nix-minecraft/issues/5
                  ${tmux} -S ${socket} server-access -aw nobody
                '';
              }
            );

            ExecStartPost = getExe (
              pkgs.writeShellApplication {
                name = "scpsl-server-${name}-start-post";
                text = ''
                  ${getExe' pkgs.coreutils "chmod"} 660 ${socket} 
                '';
              }
            );

            ExecStop = "${
              getExe (
                pkgs.writeShellApplication {
                  name = "scpsl-server-${name}-stop";
                  text = ''
                    function server_running {
                      ${tmux} -S ${socket} has-session
                    }

                    if ! server_running ; then
                      exit 0
                    fi

                    ${tmux} -S ${socket} send-keys C-u "quit" Enter

                    while server_running; do sleep 1s; done
                  '';
                }
              )
            } $MAINPID";

            TimeoutStopSec = "1min 15s";

            User = cfg.user;
            Group = cfg.group;

            # Default directory for management sockets
            RuntimeDirectory = "scpsl";
            RuntimeDirectoryPreserve = "yes";

            # Hardening
            SocketBindAllow = [ conf.settings.port ];
            CapabilityBoundingSet = [ "" ];
            DeviceAllow = [ "" ];
            LockPersonality = true;
            PrivateDevices = true;
            PrivateTmp = true;
            PrivateUsers = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
              "AF_NETLINK"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            UMask = "0007";
          };
        };
    }) cfg.servers;
  };
}
