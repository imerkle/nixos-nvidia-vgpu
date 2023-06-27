fridaFlake: { pkgs, lib, config, buildPythonPackage, ... }:

let
  
  # UNCOMMENT this to pin the version of pkgs if this stops working
  #pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/06278c77b5d162e62df170fec307e83f1812d94b.tar.gz") {
  #    # config.allowUnfree = true;
  #};

  cfg = config.hardware.nvidia.vgpu;

  mdevctl = pkgs.callPackage ./mdevctl {};
  frida = fridaFlake.packages.${pkgs.system}.frida-tools;

  myVgpuVersion = "525.105.14";
  
  # maybe take a look at https://discourse.nixos.org/t/how-to-add-custom-python-package/536/4
  vgpu_unlock = pkgs.python310Packages.buildPythonPackage {
    pname = "nvidia-vgpu-unlock";
    version = "unstable-2021-04-22";

    src = pkgs.fetchFromGitHub {
      owner = "Yeshey";
      repo = "vgpu_unlock";
      rev = "7db331d4a2289ff6c1fb4da50cf445d9b4227421";
      sha256 = "sha256-K7e/9q7DmXrrIFu4gsTv667bEOxRn6nTJYozP1+RGHs=";
    };

    propagatedBuildInputs = [ frida ];
    
    doCheck = false; # Disable running checks during the build
    
    installPhase = ''
      mkdir -p $out/bin
      cp vgpu_unlock $out/bin/
      substituteInPlace $out/bin/vgpu_unlock \
              --replace /bin/bash ${pkgs.bash}/bin/bash
    '';
  };
in
{
  options = {
    hardware.nvidia.vgpu = {
      enable = lib.mkEnableOption "vGPU support";

      unlock.enable = lib.mkOption {
        default = false;
        type = lib.types.bool;
        description = "Unlock vGPU functionality for consumer grade GPUs";
      };

      # submodule
      fastapi-dls = lib.mkOption {
        description = "Set up fastapi-dls host server";
        type = with lib.types; submodule {
          options = {
            enable = lib.mkOption {
              default = false;
              type = lib.types.bool;
              description = "Set up fastapi-dls host server";
            };
            docker-directory = lib.mkOption {
              description = "Path to your folder with docker containers";
              default = /opt/docker;
              example = /dockers;
              type = lib.types.path;
            };
            local_ipv4 = lib.mkOption {
              description = "your ipv4, needed for the fastapi-dls server";
              example = "192.168.1.81";
              type = lib.types.str;
            };
            timezone = lib.mkOption {
              description = "your timezone according to this list: https://docs.diladele.com/docker/timezones.html, needs to be the same as in the VM, needed for the fastapi-dls server";
              example = "Europe/Lisbon";
              type = lib.types.str;
            };
          };
        };
      };
      
    };
  };

  config = lib.mkMerge [

 (lib.mkIf cfg.enable {
    hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable.overrideAttrs ( # CHANGE stable to legacy_470 to pin the version of the driver if it stops working
      { patches ? [], postUnpack ? "", postPatch ? "", preFixup ? "", ... }@attrs: {
      # Overriding https://github.com/NixOS/nixpkgs/tree/nixos-unstable/pkgs/os-specific/linux/nvidia-x11
      # that gets called from the option hardware.nvidia.package from here: https://github.com/NixOS/nixpkgs/blob/nixos-22.11/nixos/modules/hardware/video/nvidia.nix
      name = "NVIDIA-Linux-x86_64-525.105.17-merged-vgpu-kvm-patched-${config.boot.kernelPackages.kernel.version}";
      version = "${myVgpuVersion}";

      # the new driver (getting from my Google drive)
      src = pkgs.fetchurl {
              name = "NVIDIA-Linux-x86_64-525.105.17-merged-vgpu-kvm-patched.run"; # So there can be special characters in the link below: https://github.com/NixOS/nixpkgs/issues/6165#issuecomment-141536009
              url = "https://drive.google.com/u/1/uc?id=17NN0zZcoj-uY2BELxY2YqGvf6KtZNXhG&export=download&confirm=t&uuid=e2729c36-3bb7-4be6-95b0-08e06eac55ce&at=AKKF8vzPeXmt0W_pxHE9rMqewfXY:1683158182055";
              sha256 = "sha256-g8BM1g/tYv3G9vTKs581tfSpjB6ynX2+FaIOyFcDfdI=";
            };

      postPatch = if postPatch != null then postPatch + ''
        # Move path for vgpuConfig.xml into /etc
        sed -i 's|/usr/share/nvidia/vgpu|/etc/nvidia-vgpu-xxxxx|' nvidia-vgpud

        substituteInPlace sriov-manage \
          --replace lspci ${pkgs.pciutils}/bin/lspci \
          --replace setpci ${pkgs.pciutils}/bin/setpci
      '' else ''
        # Move path for vgpuConfig.xml into /etc
        sed -i 's|/usr/share/nvidia/vgpu|/etc/nvidia-vgpu-xxxxx|' nvidia-vgpud

        substituteInPlace sriov-manage \
          --replace lspci ${pkgs.pciutils}/bin/lspci \
          --replace setpci ${pkgs.pciutils}/bin/setpci
      '';

      /*
      postPatch = postPatch + ''
        # Move path for vgpuConfig.xml into /etc
        sed -i 's|/usr/share/nvidia/vgpu|/etc/nvidia-vgpu-xxxxx|' nvidia-vgpud

        substituteInPlace sriov-manage \
          --replace lspci ${pkgs.pciutils}/bin/lspci \
          --replace setpci ${pkgs.pciutils}/bin/setpci
      ''; */

      # HACK: Using preFixup instead of postInstall since nvidia-x11 builder.sh doesn't support hooks
      preFixup = preFixup + ''
        for i in libnvidia-vgpu.so.${myVgpuVersion} libnvidia-vgxcfg.so.${myVgpuVersion}; do
          install -Dm755 "$i" "$out/lib/$i"
        done
        patchelf --set-rpath ${pkgs.stdenv.cc.cc.lib}/lib $out/lib/libnvidia-vgpu.so.${myVgpuVersion}
        install -Dm644 vgpuConfig.xml $out/vgpuConfig.xml

        for i in nvidia-vgpud nvidia-vgpu-mgr; do
          install -Dm755 "$i" "$bin/bin/$i"
          # stdenv.cc.cc.lib is for libstdc++.so needed by nvidia-vgpud
          patchelf --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
            --set-rpath $out/lib "$bin/bin/$i"
        done
        install -Dm755 sriov-manage $bin/bin/sriov-manage
      '';
    });

    systemd.services.nvidia-vgpud = {
      description = "NVIDIA vGPU Daemon";
      wants = [ "syslog.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "forking";
        ExecStart = lib.strings.concatStringsSep " " [
          # Won't this just break if cfg.unlock.enable = false?
          (lib.optionalString cfg.unlock.enable "${vgpu_unlock}/bin/vgpu_unlock")
          "${lib.getBin config.hardware.nvidia.package}/bin/nvidia-vgpud"
        ];
        ExecStopPost = "${pkgs.coreutils}/bin/rm -rf /var/run/nvidia-vgpud";
        Environment = [ "__RM_NO_VERSION_CHECK=1" ]; # Avoids issue with API version incompatibility when merging host/client drivers
      };
    };

    systemd.services.nvidia-vgpu-mgr = {
      description = "NVIDIA vGPU Manager Daemon";
      wants = [ "syslog.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "forking";
        KillMode = "process";
        ExecStart = lib.strings.concatStringsSep " " [
          # Won't this just break if cfg.unlock.enable = false?
          (lib.optionalString cfg.unlock.enable "${vgpu_unlock}/bin/vgpu_unlock")
          "${lib.getBin config.hardware.nvidia.package}/bin/nvidia-vgpu-mgr"
        ];
        ExecStopPost = "${pkgs.coreutils}/bin/rm -rf /var/run/nvidia-vgpu-mgr";
        Environment = [ "__RM_NO_VERSION_CHECK=1"];
      };
    };

    environment.etc."nvidia-vgpu-xxxxx/vgpuConfig.xml".source = config.hardware.nvidia.package + /vgpuConfig.xml;

    boot.kernelModules = [ "nvidia-vgpu-vfio" ];

    environment.systemPackages = [ mdevctl];
    services.udev.packages = [ mdevctl ];

  })

    (lib.mkIf cfg.fastapi-dls.enable {

      # fastapi-dls docker service, need to run this code before running the module
      /*
      WORKING_DIR=/opt/docker/fastapi-dls/cert

      sudo mkdir -p /opt/docker/fastapi-dls/cert
      mkdir -p $WORKING_DIR
      cd $WORKING_DIR
      # create instance private and public key for singing JWT's
      openssl genrsa -out $WORKING_DIR/instance.private.pem 2048 
      openssl rsa -in $WORKING_DIR/instance.private.pem -outform PEM -pubout -out $WORKING_DIR/instance.public.pem
      # create ssl certificate for integrated webserver (uvicorn) - because clients rely on ssl
      openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout  $WORKING_DIR/webserver.key -out $WORKING_DIR/webserver.crt
      */
      virtualisation.oci-containers.containers = {
        fastapi-dls = {
          image = "collinwebdesigns/fastapi-dls:latest";
          volumes = [
            "${cfg.fastapi-dls.docker-directory}/fastapi-dls/cert:/app/cert:rw"
            "dls-db:/app/database"
          ];
          # Set environment variables
          environment = {
            TZ = "${cfg.fastapi-dls.timezone}";
            DLS_URL = "${cfg.fastapi-dls.local_ipv4}"; # this should grab your hostname or your IP!
            DLS_PORT = "443";
            LEASE_EXPIRE_DAYS="90";
            DATABASE = "sqlite:////app/database/db.sqlite";
            DEBUG = "true";
          };
          extraOptions = [
          ];
          # Publish the container's port to the host
          ports = [ "443:443" ];
          # Automatically start the container
          autoStart = true;
        };
      };
    })

    /* Something you can do to automate getting the your local IP:
      https://discourse.nixos.org/t/for-nixos-on-aws-ec2-how-to-get-ip-address/15616/12?u=yeshey

      With something like:
        environmentFiles = lib.mkOption {
          description = "enviroonmentFiles for docker";
          default = [];
          example = ["/my-ip"];
          type = lib.arr lib.types.path;
        };

      systemd.services.my-awesome-service = {
        description = "writes a file to /my-ip";
        serviceConfig.PassEnvironment = "DISPLAY";
        script = ''
          echo "DLS_URL=$(${pkgs.busybox}/bin/ip a | grep "scope" | grep -Po '(?<=inet )[\d.]+' | head -n 2 | tail -n 1)" > /my-ip;
          echo "success!"
        '';
        wantedBy = [ "multi-user.target" ]; # starts after login
      };
     */

  ];
}
