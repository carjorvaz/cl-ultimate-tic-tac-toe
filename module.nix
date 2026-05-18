{ self }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ultimate-tic-tac-toe;
  runtimeStateDir = "/var/lib/${cfg.stateDirectory}";
  version = if cfg.version == null then "unknown" else cfg.version;

  runService = pkgs.writeShellScript "run-ultimate-tic-tac-toe" ''
    set -euo pipefail

    state_directory="''${STATE_DIRECTORY:-${runtimeStateDir}}"
    install -m 0700 -d "$state_directory" "$state_directory/cache"

    export HOME="$state_directory"
    export XDG_CACHE_HOME="$state_directory/cache"
    export UTTT_ROOM_DB="${cfg.roomDatabasePath}"

    if [ ! -s "$state_directory/session-secret" ]; then
      umask 077
      ${lib.getExe pkgs.openssl} rand -hex 32 > "$state_directory/session-secret"
    fi

    export PORT="${toString cfg.port}"
    export UTTT_VERSION="${version}"
    export SESSION_SECRET="$(cat "$state_directory/session-secret")"
    exec ${lib.getExe cfg.package}
  '';
in
{
  options.services.ultimate-tic-tac-toe = {
    enable = lib.mkEnableOption "Ultimate Tic Tac Toe web app";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "inputs.cl-ultimate-tic-tac-toe.packages.${pkgs.stdenv.hostPlatform.system}.default";
      description = "Package providing the ultimate-tic-tac-toe executable.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "ultimate-tic-tac-toe";
      description = "User account under which the service runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "ultimate-tic-tac-toe";
      description = "Group under which the service runs.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4242;
      description = "Loopback HTTP port for the web app.";
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "ultimate-tic-tac-toe";
      description = "systemd StateDirectory name used for persistent service state.";
    };

    roomDatabasePath = lib.mkOption {
      type = lib.types.str;
      default = "${runtimeStateDir}/rooms.sqlite3";
      defaultText = lib.literalExpression ''"/var/lib/''${config.services.ultimate-tic-tac-toe.stateDirectory}/rooms.sqlite3"'';
      description = "Path to the SQLite room database.";
    };

    version = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = config.system.configurationRevision;
      defaultText = lib.literalExpression "config.system.configurationRevision";
      description = "Version string exposed through the app runtime.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.ultimate-tic-tac-toe = {
      description = "Ultimate Tic Tac Toe web app";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = runService;
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        RestartSec = "5s";
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0700";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ runtimeStateDir ];
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        CapabilityBoundingSet = "";
        LockPersonality = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
      };
    };

    users.users.${cfg.user} = {
      inherit (cfg) group;
      isSystemUser = true;
    };
    users.groups.${cfg.group} = { };
  };
}
