{ config, lib, pkgs, ... }:

let
  # The script path we want to run
  immich-sdcard-sync-bin =
    let
      src = builtins.readFile ./immich-sdcard-sync.sh;
      script = (pkgs.writeScriptBin "immich-sdcard-sync" src).overrideAttrs
        (old: {
          buildCommand = "${old.buildCommand}\n patchShebangs $out";
        });
    in 
    pkgs.symlinkJoin {
      name = "immich-sdcard-sync";
      paths = [ pkgs.jq pkgs.curl pkgs.util-linux pkgs.rsync script ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = "wrapProgram $out/bin/immich-sdcard-sync --prefix PATH : $out/bin";
    };
in
{
  options = {
    immich-sdcard-sync = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the SD card upload systemd service and udev rule.";
      };

      immichServerUrlFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to the Immich server URL file.";
        default = "/home/sdcard-upload-user/immich_server_url";
      };

      immichUsernameFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to the Immich username file.";
        default = "/home/sdcard-upload-user/immich_email";
      };

      immichPasswordFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to the Immich password file.";
        default = "/home/sdcard-upload-user/immich_password";
      };

      sdCardSerials = lib.mkOption {
        type = lib.types.str;
        description = "Space-separated list of SD card serial numbers.";
        default = "1234567890ABCDEF 0987654321FEDCBA";
      };
    };
  };

  config = lib.mkIf config.immich-sdcard-sync.enable {
    # Environment file with dynamic variables
    environment.etc."immich-sdcard-sync.env".text = ''
      IMMICH_SERVER_URL_FILE=${config.immich-sdcard-sync.immichServerUrlFile}
      IMMICH_USERNAME_FILE=${config.immich-sdcard-sync.immichUsernameFile}
      IMMICH_PASSWORD_FILE=${config.immich-sdcard-sync.immichPasswordFile}
      SD_CARD_SERIALS="${config.immich-sdcard-sync.sdCardSerials}"
    '';

    # Systemd service definition
    systemd.services.immich-sdcard-sync = {
      description = "SD Card Upload Service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${immich-sdcard-sync-bin}/bin/immich-sdcard-sync";
        EnvironmentFile = "/etc/immich-sdcard-sync.env";
      };
    };

    # udev rule for triggering the systemd service
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEMS=="usb", KERNEL=="sd[a-z]", ENV{ID_SERIAL}=="?*", ENV{ID_BUS}=="usb", ENV{ID_TYPE}=="disk", RUN+="${pkgs.systemd.out}/bin/systemctl start immich-sdcard-sync.service"
    '';
  };
}
