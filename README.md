# Immich SD Card Sync Service

Automate the synchronization of images from SD cards to your Immich server on NixOS. This project provides a NixOS module that detects the insertion of SD cards with specified serial numbers and automatically uploads their images to an Immich server using a systemd service triggered by udev rules.

## Features

- **Automatic Syncing**: Automatically uploads images from inserted SD cards to an Immich server.
- **Serial Number Filtering**: Only syncs SD cards with serial numbers specified in the configuration.
- **Systemd Integration**: Utilizes systemd services for handling the upload process.
- **Udev Rules**: Detects SD card insertion events to trigger the upload service.
- **Flake Support**: Provides a flake-based configuration for modern NixOS setups.

## Prerequisites

- **NixOS**: Ensure you are running NixOS.
- **Immich Server**: Access to a running Immich server.
- **SD Cards**: SD cards with known serial numbers you wish to sync upon insertion.

## Installation and Usage

### Using a Flake-based NixOS Configuration

1. **Clone the Repository**

   ```bash
   git clone https://github.com/your-repo/immich-sd-card-sync.git
   cd immich-sd-card-sync
   ```

2. **Set Up Your Flake Configuration**

   Ensure your `flake.nix` is set up as follows:

   ```nix
   {
     description = "Immich SD Card Sync Service";

     inputs = {
       nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
       flake-utils.url = "github:numtide/flake-utils";
     };

     outputs = { self, nixpkgs, flake-utils }: flake-utils.lib.eachDefaultSystem (system:
       let
         pkgs = nixpkgs.legacyPackages.${system};
       in
       {
         # Expose the NixOS module in the flake output
         nixosModules.immichSdCardSync = { config, lib, ... }: import ./immich-sd-card-sync.nix { inherit lib pkgs config; };

         # Add a formatter using nixpkgs-fmt (Removed as per user request)
       }
     );
   }
   ```

3. **Configure NixOS to Use the Module**

   In your `configuration.nix`, add the flake and configure the module:

   ```nix
   {
     inputs = {
       immichSdCardSync.url = "path:/path/to/immich-sd-card-sync";
     };

     outputs = { nixpkgs, immichSdCardSync, ... }: {
       nixosConfigurations.mySystem = nixpkgs.lib.nixosSystem {
         system = "x86_64-linux";
         modules = [
           immichSdCardSync.nixosModules.immichSdCardSync
           {
             sdcard-upload = {
               enable = true;
               immichServerUrlFile = "/home/sdcard-upload-user/immich_server_url";
               immichUsernameFile = "/home/sdcard-upload-user/immich_email";
               immichPasswordFile = "/home/sdcard-upload-user/immich_password";
               sdCardSerials = "1234567890ABCDEF 0987654321FEDCBA";
             };
           }
         ];
       };
     };
   }
   ```

   **Replace:**
   - `/path/to/immich-sd-card-sync` with the actual path to your cloned repository.
   - `/home/sdcard-upload-user/...` with the actual paths to your Immich server credentials.
   - `1234567890ABCDEF 0987654321FEDCBA` with your SD card serial numbers.

4. **Rebuild Your NixOS Configuration**

   Apply the changes by rebuilding your NixOS system:

   ```bash
   sudo nixos-rebuild switch --flake /path/to/immich-sd-card-sync#mySystem
   ```

### Using a Traditional (Non-Flake) NixOS Configuration

1. **Clone the Repository**

   ```bash
   git clone https://github.com/your-repo/immich-sd-card-sync.git
   cd immich-sd-card-sync
   ```

2. **Import the Module into `configuration.nix`**

   Add the module to your NixOS configuration:

   ```nix
   { config, pkgs, ... }:

   let
     immichSdCardSync = import /path/to/immich-sd-card-sync/immich-sd-card-sync.nix;
   in {
     imports = [ immichSdCardSync ];

     sdcard-upload = {
       enable = true;
       immichServerUrlFile = "/home/sdcard-upload-user/immich_server_url";
       immichUsernameFile = "/home/sdcard-upload-user/immich_email";
       immichPasswordFile = "/home/sdcard-upload-user/immich_password";
       sdCardSerials = "1234567890ABCDEF 0987654321FEDCBA";
     };
   }
   ```

   **Replace:**
   - `/path/to/immich-sd-card-sync` with the actual path to your cloned repository.
   - `/home/sdcard-upload-user/...` with the actual paths to your Immich server credentials.
   - `1234567890ABCDEF 0987654321FEDCBA` with your SD card serial numbers.

3. **Rebuild Your NixOS Configuration**

   Apply the changes by rebuilding your NixOS system:

   ```bash
   sudo nixos-rebuild switch
   ```

## Configuration Options

The module provides several options for customization:

- **`sdcard-upload.enable`** (`bool`):  
  Enables or disables the SD card upload service.

- **`sdcard-upload.immichServerUrlFile`** (`string`):  
  Path to the file containing the URL of the Immich server.

- **`sdcard-upload.immichUsernameFile`** (`string`):  
  Path to the file containing the username/email for Immich authentication.

- **`sdcard-upload.immichPasswordFile`** (`string`):  
  Path to the file containing the password for Immich authentication.

- **`sdcard-upload.sdCardSerials`** (`string`):  
  Space-separated list of SD card serial numbers that will trigger the upload process.

## How It Works

1. **udev Rule**: Detects when an SD card with a specified serial number is inserted.
2. **Systemd Service**: The `sdcard-upload.service` is triggered by the udev rule and uploads images from the SD card to the Immich server.
3. **Configuration**: The service and its behavior can be customized via NixOS options.

## Usage

1. **Insert an SD Card**:  
   Insert an SD card whose serial number matches one of those specified in `sdCardSerials`. This action triggers the upload process.

2. **Check Service Status**:  
   Verify the status of the upload service:

   ```bash
   sudo systemctl status sdcard-upload.service
   ```

3. **View Logs**:  
   Monitor the logs to see the upload process in action:

   ```bash
   journalctl -u sdcard-upload.service -f
   ```

## Contributing

Contributions are welcome! Please open issues or submit pull requests for any enhancements or bug fixes.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgements

- [Immich](https://immich.app/) for providing the image server solution.
- [NixOS](https://nixos.org/) community for their robust package management and configuration system.
