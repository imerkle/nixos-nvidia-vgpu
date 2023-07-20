{ pkgs, lib, config, ... }:

let
  gnrl-driver-version = "525.125.06";
  # grid driver and wdys driver aren't actually used, but their versions are needed to find some filenames
  vgpu-driver-version = "525.125.03";
  grid-driver-version = "525.125.06";
  wdys-driver-version = "529.11";
  grid-version = "15.3";
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
      nativeBuildInputs = [ pkgs.p7zip pkgs.coreutils];
        system = "x86_64-linux";
        src = pkgs.fetchFromGitHub {
          owner = "imerkle";
          repo = "vGPU-Unlock-patcher";
          rev = "11b75d69a0a0273650e08cefb85d0045e0bc135f";
          sha256 = "1ri8338353i4qwaipwai930w941fcm1ib0sp6k3l0ny6axrlxfy7";
          fetchSubmodules = true;
        };
        original = pkgs.fetchurl {
          url = "https://download.nvidia.com/XFree86/Linux-x86_64/${gnrl-driver-version}/NVIDIA-Linux-x86_64-${gnrl-driver-version}.run";
          sha256 = "17av8nvxzn5af3x6y8vy5g6zbwg21s7sq5vpa1xc6cx8yj4mc9xm";
        };
        zip1 = pkgs.fetchurl {
          url = "https://github.com/justin-himself/NVIDIA-VGPU-Driver-Archive/releases/download/${grid-version}/NVIDIA-GRID-Linux-KVM-${vgpu-driver-version}-${grid-driver-version}-${wdys-driver-version}.7z.001";
          sha256 = "1x0xcn8lk6q53z7rdyv785x0xl0z5mx581kmy96qzfnim2ac22sn";
        };
        zip2 = pkgs.fetchurl {
          url = "https://github.com/justin-himself/NVIDIA-VGPU-Driver-Archive/releases/download/${grid-version}/NVIDIA-GRID-Linux-KVM-${vgpu-driver-version}-${grid-driver-version}-${wdys-driver-version}.7z.002";
          sha256 = "1259mplzy1651q5ji9na7cr1vp2ga6lsj230pkivdms3x1vwdcl2";
        };
        buildPhase = ''
          mkdir -p $out
          cd $TMPDIR
          ln -s $zip1 NVIDIA-GRID-Linux-KVM-${vgpu-driver-version}-${grid-driver-version}-${wdys-driver-version}.7z.001
          ln -s $zip2 NVIDIA-GRID-Linux-KVM-${vgpu-driver-version}-${grid-driver-version}-${wdys-driver-version}.7z.002
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
              description = "Your ipv4 or local hostname, needed for the fastapi-dls server. Leave blank to autodetect using hostname";
              default = "";
              example = "192.168.1.81";
              type = lib.types.str;
            };
            timezone = lib.mkOption {
              description = "Your timezone according to this list: https://docs.diladele.com/docker/timezones.html, needs to be the same as in the VM. Leave blank to autodetect";
              default = "";
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
    hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable.overrideAttrs (
      { patches ? [], postUnpack ? "", postPatch ? "", preFixup ? "", ... }@attrs: {
      # Overriding https://github.com/NixOS/nixpkgs/tree/nixos-unstable/pkgs/os-specific/linux/nvidia-x11
      # that gets called from the option hardware.nvidia.package from here: https://github.com/NixOS/nixpkgs/blob/nixos-22.11/nixos/modules/hardware/video/nvidia.nix
      name = "NVIDIA-Linux-x86_64-${gnrl-driver-version}-merged-vgpu-kvm-patched-${config.boot.kernelPackages.kernel.version}";
      version = "${gnrl-driver-version}";

      # the new driver (compiled in a derivation above)
      src = "${compiled-driver}/NVIDIA-Linux-x86_64-${gnrl-driver-version}-merged-vgpu-kvm-patched.run";

      ibtSupport = true;
      patches = null;

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
        ExecStartPre = "/bin/bash -c 'mkdir /etc/systemd/system/nvidia-vgpud.service.d'";
        ExecStart = "${lib.getBin config.hardware.nvidia.package}/bin/nvidia-vgpud";
        ExecStopPost = "${pkgs.coreutils}/bin/rm -rf /var/run/nvidia-vgpud";
        Environment = [ "__RM_NO_VERSION_CHECK=1"]; # Avoids issue with API version incompatibility when merging host/client drivers
        #Environment = [  ]; # Avoids issue with API version incompatibility when merging host/client drivers        
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
        Environment = [ "__RM_NO_VERSION_CHECK=1" "LD_PRELOAD=/home/slim/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so" ];
      };
    };

    environment.etc."nvidia-vgpu-xxxxx/vgpuConfig.xml".source = config.hardware.nvidia.package + /vgpuConfig.xml;

    boot.kernelModules = [ "nvidia-vgpu-vfio" ];

    environment.systemPackages = [ mdevctl];
    services.udev.packages = [ mdevctl ];

  })

    (lib.mkIf cfg.fastapi-dls.enable {
      virtualisation.oci-containers.containers = {
        fastapi-dls = {
          image = "collinwebdesigns/fastapi-dls";
          imageFile = pkgs.dockerTools.pullImage {
            imageName = "collinwebdesigns/fastapi-dls";
            imageDigest = "sha256:6fa90ce552c4e9ecff9502604a4fd42b3e67f52215eb6d8de03a5c3d20cd03d1";
            sha256 = "1y642miaqaxxz3z8zkknk0xlvzxcbi7q7ylilnxhxfcfr7x7kfqa";
          };
          volumes = [
            "${cfg.fastapi-dls.docker-directory}/fastapi-dls/cert:/app/cert:rw"
            "dls-db:/app/database"
          ];
          # Set environment variables
          environment = {
            TZ = if cfg.fastapi-dls.timezone == "" then config.time.timeZone else "${cfg.fastapi-dls.timezone}";
            DLS_URL = if cfg.fastapi-dls.local_ipv4 == "" then config.networking.hostName else "${cfg.fastapi-dls.local_ipv4}";
            DLS_PORT = "443";
            LEASE_EXPIRE_DAYS="90";
            DATABASE = "sqlite:////app/database/db.sqlite";
            DEBUG = "true";
          };
          extraOptions = [
          ];
          # Publish the container's port to the host
          ports = [ "443:443" ];
          # Do not automatically start the container, it will be managed
          autoStart = false;
        };
      };

      systemd.timers.fastapi-dls-mgr = {
        wantedBy = [ "multi-user.target" ];
        timerConfig = {
          OnActiveSec = "1s";
          OnUnitActiveSec = "1h";
          AccuracySec = "1s";
          Unit = "fastapi-dls-mgr.service";
        };
      };

      systemd.services.fastapi-dls-mgr = {
        path = [ pkgs.openssl ];
        script = ''
        WORKING_DIR=${cfg.fastapi-dls.docker-directory}/fastapi-dls/cert
        CERT_CHANGED=false
        recreate_private () {
          rm -f $WORKING_DIR/instance.private.pem
          openssl genrsa -out $WORKING_DIR/instance.private.pem 2048
        }
        recreate_public () {
          rm -f $WORKING_DIR/instance.public.pem
          openssl rsa -in $WORKING_DIR/instance.private.pem -outform PEM -pubout -out $WORKING_DIR/instance.public.pem
        }
        recreate_certs () {
          rm -f $WORKING_DIR/webserver.key
          rm -f $WORKING_DIR/webserver.crt 
          openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $WORKING_DIR/webserver.key -out $WORKING_DIR/webserver.crt -subj "/C=XX/ST=StateName/L=CityName/O=CompanyName/OU=CompanySectionName/CN=CommonNameOrHostname"
        }
        check_recreate() {
          if [ ! -e $WORKING_DIR/instance.private.pem ]; then
            recreate_private
            recreate_public
            recreate_certs
            CERT_CHANGED=true
          fi
          if [ ! -e $WORKING_DIR/instance.public.pem ]; then
            recreate_public
            recreate_certs
            CERT_CHANGED=true
          fi 
          if [ ! -e $WORKING_DIR/webserver.key ] || [ ! -e $WORKING_DIR/webserver.crt ]; then
            recreate_certs
            CERT_CHANGED=true
          fi
          if ( ! openssl x509 -checkend 864000 -noout -in $WORKING_DIR/webserver.crt); then
            recreate_certs
            CERT_CHANGED=true
          fi
        }
        if [ ! -d $WORKING_DIR ]; then
          mkdir -p $WORKING_DIR
        fi
        check_recreate
        if ( ! systemctl is-active --quiet docker-fastapi-dls.service ); then
          systemctl start podman-fastapi-dls.service
        elif $CERT_CHANGED; then
          systemctl stop podman-fastapi-dls.service
          systemctl start podman-fastapi-dls.service
        fi
        '';
        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };
    })
  ];
}
