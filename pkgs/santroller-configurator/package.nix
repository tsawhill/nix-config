{
  lib,
  buildDotnetModule,
  fetchFromGitHub,
  dotnetCorePackages,
  libX11,
  libICE,
  libSM,
  libXi,
  libxcursor,
  libXext,
  libXrandr,
  fontconfig,
  libusb1,
  udev,
}:

buildDotnetModule rec {
  pname = "santroller-configurator";
  version = "10.8.1";

  src = fetchFromGitHub {
    owner = "Santroller";
    repo = "SantrollerConfigurator";
    tag = "v${version}";
    hash = "sha256-TQzw3VLeSdqtSIkZJul8psXv1LIdU2BA+EtK/qqM37s=";
  };

  projectFile = "santroller-configurator/SantrollerConfigurator.csproj";
  nugetDeps = ./deps.json;

  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.runtime_10_0;

  # GitVersion.MsBuild needs git history; skip it in nix build
  dotnetBuildFlags = [ "-p:SkipGitVersioning=true" ];
  dotnetFlags = [ "-p:GitVersion_NoFetchEnabled=true" ];

  runtimeDeps = [
    libX11
    libICE
    libSM
    libXi
    libxcursor
    libXext
    libXrandr
    fontconfig
    libusb1
    udev
  ];

  postInstall = ''
    # Install udev rules for Santroller devices
    install -Dm644 santroller-configurator/Assets/68-santroller.rules \
      $out/lib/udev/rules.d/68-santroller.rules
  '';

  executables = [ "SantrollerConfigurator" ];

  meta = {
    description = "Configuration tool for Santroller guitar controllers";
    homepage = "https://github.com/Santroller/SantrollerConfigurator";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "SantrollerConfigurator";
  };
}
