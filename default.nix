{ pkgs, lib, config, ... }:

let
  gnrl-driver-version = "530.41.03";
  # grid driver and wdys driver aren't actually used, but their versions are needed to find some filenames
  vgpu-driver-version = "525.105.14";
  grid-driver-version = "525.105.17";
  wdys-driver-version = "528.89";
  grid-version = "15.2";
  kernel-at-least-6 = if lib.strings.versionAtLeast config.boot.kernelPackages.kernel.version "6.0" then "true" else "false";
in
let
  
  # UNCOMMENT this to pin the version of pkgs if this stops working
  #pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/06278c77b5d162e62df170fec307e83f1812d94b.tar.gz") {
  #    # config.allowUnfree = true;
  #};

  cfg = config.hardware.nvidia.vgpu;

  mdevctl = pkgs.callPackage ./mdevctl {};

  compiled-driver = pkgs.stdenv.mkDerivation rec{
    name = "driver-compile";
      nativeBuildInputs = [ pkgs.p7zip pkgs.coreutils pkgs.which pkgs.patchelf pkgs.zstd ];
        system = "x86_64-linux";
        src = pkgs.fetchFromGitHub {
          owner = "VGPU-Community-Drivers";
          repo = "vGPU-Unlock-patcher";
          rev = "d8f4dfcafe2b678fe7f6a2c30088320be327988f";
          sha256 = "0sknir82zm6j8p6lx7532l4q2g2yawjzh1221a29q05l4vawq554";
          fetchSubmodules = true;
        };
        original = pkgs.fetchurl {
          url = "https://download.nvidia.com/XFree86/Linux-x86_64/${gnrl-driver-version}/NVIDIA-Linux-x86_64-${gnrl-driver-version}.run";
          sha256 = "1cc4nyna0bifz4aywjjz08mn20hn7hsdl78nblzm11ccjrma29xf";
        };
        zip1 = pkgs.fetchurl {
          url = "https://github.com/justin-himself/NVIDIA-VGPU-Driver-Archive/releases/download/${grid-version}/NVIDIA-GRID-Linux-KVM-${vgpu-driver-version}-${grid-driver-version}-${wdys-driver-version}.7z.001";
          sha256 = "15s85dhifqski3r10wvsfrvbhill7hv2wx1qqbyq1jz1hqjyr4r1";
        };
        zip2 = pkgs.fetchurl {
          url = "https://github.com/justin-himself/NVIDIA-VGPU-Driver-Archive/releases/download/${grid-version}/NVIDIA-GRID-Linux-KVM-${vgpu-driver-version}-${grid-driver-version}-${wdys-driver-version}.7z.002";
          sha256 = "0dsd5bkssw83jyyiqx0sbnrg9qd7cninhjd49a4lq6qdk2y4dgfl";
        };
        zip3 = pkgs.fetchurl {
          url = "https://github.com/justin-himself/NVIDIA-VGPU-Driver-Archive/releases/download/${grid-version}/NVIDIA-GRID-Linux-KVM-${vgpu-driver-version}-${grid-driver-version}-${wdys-driver-version}.7z.003";
          sha256 = "0xixw5h0bmaz8964lzfdfvn184m9f4zmrk2wypqcfv1wpf2ri6pg";
        };
        buildPhase = ''
          mkdir -p $out
          cd $TMPDIR
          ln -s $zip1 NVIDIA-GRID-Linux-KVM-${vgpu-driver-version}-${grid-driver-version}-${wdys-driver-version}.7z.001
          ln -s $zip2 NVIDIA-GRID-Linux-KVM-${vgpu-driver-version}-${grid-driver-version}-${wdys-driver-version}.7z.002
          ln -s $zip3 NVIDIA-GRID-Linux-KVM-${vgpu-driver-version}-${grid-driver-version}-${wdys-driver-version}.7z.003
          ${pkgs.p7zip}/bin/7z e -y NVIDIA-GRID-Linux-KVM-${vgpu-driver-version}-${grid-driver-version}-${wdys-driver-version}.7z.001 NVIDIA-GRID-Linux-KVM-${vgpu-driver-version}-${grid-driver-version}-${wdys-driver-version}/Host_Drivers/NVIDIA-Linux-x86_64-${vgpu-driver-version}-vgpu-kvm.run
          cp -a $src/* .
          cp -a $original NVIDIA-Linux-x86_64-${gnrl-driver-version}.run
          if ${kernel-at-least-6}; then
             sh ./patch.sh --repack --lk6-patches general-merge 
          else
             sh ./patch.sh --repack general-merge 
          fi
          cp -a NVIDIA-Linux-x86_64-${gnrl-driver-version}-merged-vgpu-kvm-patched.run $out
        '';
  };
in
{
  options = {
    hardware.nvidia.vgpu = {
      enable = lib.mkEnableOption "vGPU support";

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
              default = "/opt/docker";
              example = "/dockers";
              type = lib.types.str;
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
      # name = "NVIDIA-Linux-x86_64-${gnrl-driver-version}-merged-vgpu-kvm-patched-${config.boot.kernelPackages.kernel.version}";
      version = "${gnrl-driver-version}";

      # the new driver (compiled in a derivation above)
      src = "${compiled-driver}/NVIDIA-Linux-x86_64-${gnrl-driver-version}-merged-vgpu-kvm-patched.run";

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
        for i in libnvidia-vgpu.so.${vgpu-driver-version} libnvidia-vgxcfg.so.${vgpu-driver-version}; do
          install -Dm755 "$i" "$out/lib/$i"
        done
        patchelf --set-rpath ${pkgs.stdenv.cc.cc.lib}/lib $out/lib/libnvidia-vgpu.so.${vgpu-driver-version}
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
        ExecStart = "${lib.getBin config.hardware.nvidia.package}/bin/nvidia-vgpud";
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
        ExecStart = "${lib.getBin config.hardware.nvidia.package}/bin/nvidia-vgpu-mgr";
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
