{ config, lib, pkgs, ... }:

let
  # The script path we want to run
  sdcardScript = pkgs.writeScriptBin "sdcard-upload"
    (builtins.readFile ./immich-sdcard-upload.sh).overrideAttrs
    (oldAttrs: rec {
      buildCommand = ''
        mkdir -p $out/bin
        cp ${./immich-sdcard-upload.sh} $out/bin/sdcard-upload
        patchShebangs $out/bin/sdcard-upload
      '';
    });
in
{
  options = {
    sdcard-upload = {
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

  config = lib.mkIf config.sdcard-upload.enable {
    # Environment file with dynamic variables
    environment.etc."sdcard-upload.env".text = ''
      IMMICH_SERVER_URL_FILE=${config.sdcard-upload.immichServerUrlFile}
      IMMICH_USERNAME_FILE=${config.sdcard-upload.immichUsernameFile}
      IMMICH_PASSWORD_FILE=${config.sdcard-upload.immichPasswordFile}
      SD_CARD_SERIALS="${config.sdcard-upload.sdCardSerials}"
    '';

    # Systemd service definition
    systemd.services.sdcard-upload = {
      description = "SD Card Upload Service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${sdcardScript}/bin/sdcard-upload";
        EnvironmentFile = "/etc/sdcard-upload.env";
      };
      user = "sdcard-upload-user";
      group = "sdcard-upload-user";
    };

    # udev rule for triggering the systemd service
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEMS=="usb", KERNEL=="sd[a-z]", ENV{ID_SERIAL}=="?*", ENV{ID_BUS}=="usb", ENV{ID_TYPE}=="disk", RUN+="/run/current-system/sw/bin/systemctl start sdcard-upload.service"
    '';
  };
}
