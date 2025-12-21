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
    unique
    ;
  cfg = config.services.scpsl-server;

  singleAttrOf =
    elemType:
    types.addCheck (types.attrsOf elemType) (
      actual: (lib.isAttrs actual) && ((lib.lists.length (lib.attrValues actual)) == 1)
    );

  mkEnableOpt =
    description:
    mkEnableOption ""
    // {
      inherit description;
      example = true;
    };

  mkOpt =
    type: default: description:
    mkOption {
      inherit type default description;
    };

  format = pkgs.formats.yaml { };
in

{
  options.services.scpsl-server = {
    enable = mkEnableOpt ''
      Whether to enable declarative management of SCP:SL
      servers. When enabled, servers defined using
      {option}`services.scpsl-server.servers`
      will be set up.
    '';

    package = mkPackageOption pkgs "scpsl-server" { };

    eula = mkEnableOpt ''
      Whether to accept [Northwood Studios' EULA][eula]. 
      This option must be set to `true` in order
      to run any SCP:SL server.

      [eula]: https://store.steampowered.com/eula/700330_eula_0
    '';

    openFirewall = mkEnableOpt ''
      Whether to open the ports of all servers defined
      in {option}`services.scpsl-server.servers`.
    '';

    dataDir = mkOpt types.path "/srv/scpsl" ''
      The data directory containing the configuration files
      and logs for all servers.
    '';

    user = mkOpt types.str "scpsl" ''
      The user that runs and creates the servers.
    '';

    group = mkOpt types.str "scpsl" ''
      The group that has access to the server and
      it's files. To attach to the tmux socket it is necessary
      for the user to be part of this group.
    '';

    servers = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:

          {
            options = {
              enable = mkEnableOpt ''
                Whether to enable this server.
              '';

              autoStart =
                mkEnableOpt ''
                  Whether to start this server on boot.
                  If set to false, use `systemctl start scpsl-server-<name>`
                  to start the server.
                ''
                // {
                  default = true;
                };

              socketPath = mkOption {
                type = types.functionTo types.path;
                description = ''
                  Function from the server's name to the path at which the server's tmux socket is placed.
                  Defaults to {file}`/run/scpsl/<name>.sock`. 
                '';
                default = name: "/run/scpsl/${name}.sock";
                defaultText = literalExpression ''name: "/run/scpsl/''${name}.sock"'';
                example = literalExpression ''_: ''${cfg.dataDir}/main-server.sock'';
              };

              settings = mkOption {
                type = types.submodule {
                  freeformType = format.type;

                  options.port = mkOption {
                    type = types.port;
                    default = if (match "[0-9]{1,5}" name != null) then toInt name else 7777;
                    description = ''
                      The port for this server.
                    '';
                    example = 7778;
                  };
                };
                description = ''
                  The gameplay configuration. See the
                  [Tech Support Public Wiki][gameplay-config] for more information.

                  [gameplay-config]: https://techwiki.scpslgame.com/books/server-guides/page/2-gameplay-config-setup
                '';
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
                        A list of an a steam 64 id followed by 
                        `@steam` mapped to a role defined in
                        {option}`services.scpsl-server.servers.<name>.adminSettings.Roles`.
                        Use this option to give a user administrative priviledges.
                      '';
                      example = literalExpression ''[ { "someSteam64Id@steam" = "owner"; } ]'';
                    };

                    Roles = mkOption {
                      type = types.listOf types.str;
                      default = [
                        "owner"
                        "admin"
                        "moderator"
                      ];
                      description = ''
                        List of role names that users are allowed to be assigned to.
                      '';
                      example = literalExpression ''[ "admin" ]'';
                    };
                  };
                };
                description = ''
                  The remote admin configuration. See the
                  [Tech Support Public Wiki][admin-config] for more information.

                  [admin-config]: https://techwiki.scpslgame.com/books/server-guides/page/3-remote-admin-config-setup
                '';
                default = { };
              };
            };
          }
        )
      );
      description = ''
        The individual server configuration. If the attribute of 
        {option}`services.scpsl-server.servers.<name>` is set
        to an integer value it's assumed to be the port the server
        binds to.
      '';
      default = { };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.eula;
        message = ''
          You must accept the eula to run an SCP:SL server.
        '';
      }
      {
        assertion = cfg.enable && cfg.servers != { };
        message = ''
          Enabling SCP:SL servers without configuring any servers doesn't have any effect.
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
      unique (map (conf: conf.settings.port) (attrValues cfg.servers))
    );

    users.users = mkIf (cfg.user == "scpsl") {
      scpsl = {
        inherit (cfg) group;
        description = "SCP Secret Laboratory server service user";
        home = cfg.dataDir;
        createHome = true;
        homeMode = "770";
        isSystemUser = true;
      };
    };

    users.groups = mkIf (cfg.group == "scpsl") { scpsl = { }; };

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
                      sed -Ei 's/^[[:space:]]{2}\-/ \-/' "$HOME/${port}/config_"{gameplay,remoteadmin}.txt
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

                    ${tmux} -S ${socket} send-keys -t 0 C-c

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
