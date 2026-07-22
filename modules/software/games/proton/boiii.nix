{
  software.games.entries = {
    boiii = {
      command = "boiii";
      desktopName = "BOIII";
      basePath = "pc/Call of Duty/boiii";
      runner.umu = {
        exe = "boiii.exe";
        proton = "ge-proton";
        protonVersion = "10-34";
      };
    };

    boiiiSteam = {
      command = "boiii-steam";
      desktopName = "BOIII Steam";
      gamescope.resolutions = [ ];
      basePath = "$HOME/Games/saves/wine/default/drive_c/Program Files (x86)/Steam";
      runner.umu = {
        exe = "Steam.exe";
        proton = "ge-proton";
        protonVersion = "10-34";
      };
    };
  };
}
